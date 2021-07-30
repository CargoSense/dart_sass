defmodule DartSass do
  @moduledoc """
  DartSass is a installer and runner for [sass](https://sass-lang.com/dart-sass).

  ## Profiles

  You can define multiple dart_sass profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :dart_sass,
        version: "1.36.0",
        default: [
          args: ~w(css/app.scss ../priv/static/assets/app.css),
          cd: Path.expand("../assets", __DIR__)
        ]
  """

  use Application
  require Logger

  @doc false
  def start(_, _) do
    unless Application.get_env(:dart_sass, :version) do
      Logger.warn("""
      dart_sass version is not configured. Please set it in your config files:

          config :dart_sass, :version, "#{latest_version()}"
      """)
    end

    configured_version = configured_version()

    case bin_version() do
      {:ok, ^configured_version} ->
        :ok

      {:ok, version} ->
        Logger.warn("""
        Outdated dart-sass version. Expected #{configured_version}, got #{version}. \
        Please run `mix sass.install` or update the version in your config files.\
        """)

      :error ->
        :ok
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  @doc false
  # Latest known version at the time of publishing.
  def latest_version do
    "1.36.0"
  end

  @doc """
  Returns the configured dart-sass version.
  """
  def configured_version do
    Application.get_env(:dart_sass, :version, latest_version())
  end

  @doc """
  Returns the configuration for the given profile.

  Returns nil if the profile does not exist.
  """
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:dart_sass, profile) ||
      raise ArgumentError, """
      unknown dart_sass profile. Make sure the profile is defined in your config files, such as:

          config :dart_sass,
            #{profile}: [
              args: ~w(css/app.scss ../priv/static/assets/app.css),
              cd: Path.expand("../assets", __DIR__)
            ]
      """
  end

  @doc """
  Checks whether or not dart-sass is installed.
  """
  def installed? do
    case bin_paths() do
      {sass, nil} -> File.exists?(sass)
      {vm, snapshot} -> File.exists?(vm) and File.exists?(snapshot)
    end
  end

  @doc """
  Returns the path to the executable.

  The executable may not be available if it was not yet installed.
  """
  def bin_path do
    {path, _snapshot} = bin_paths()
    path
  end

  @doc """
  Returns the path to the executable and optional snapshot.

  Depending on your environment, sass may be invoked through a
  portable instance of the Dart VM. In such case, this function
  will return a tuple of `{Dart, Snapshot}`, otherwise it will
  return `{Sass, Nil}`.
  """
  def bin_paths do
    case :os.type() do
      {:unix, :darwin} -> {vm_path(), snapshot_path()}
      {:win32, _} -> {vm_path(), snapshot_path()}
      _ -> {sass_path(), nil}
    end
  end

  @doc false
  def sass_path() do
    Path.join(Path.dirname(Mix.Project.build_path()), "sass")
  end

  @doc false
  def snapshot_path do
    Path.join(Path.dirname(Mix.Project.build_path()), "sass.snapshot")
  end

  @doc false
  def vm_path do
    Path.join(Path.dirname(Mix.Project.build_path()), "dart")
  end

  @doc """
  Returns the version of the dart_sass executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    {path, args} = sass(["--version"])

    with true <- File.exists?(path),
         {result, 0} <- System.cmd(path, args) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  defp sass(args) do
    case bin_paths() do
      {sass, nil} -> {sass, args}
      {vm, snapshot} -> {vm, [snapshot] ++ args}
    end
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.
  """
  def run(profile, extra_args) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    args = config[:args] || []

    opts = [
      cd: config[:cd] || File.cwd!(),
      env: config[:env] || %{},
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    {sass_path, args} = sass(args ++ extra_args)

    sass_path
    |> System.cmd(args, opts)
    |> elem(1)
  end

  @doc """
  Installs, if not available, and then runs `sass`.

  Returns the same as `run/2`.
  """
  def install_and_run(profile, args) do
    unless installed?() do
      install()
    end

    run(profile, args)
  end

  @doc """
  Installs dart-sass with `configured_version/0`.
  """
  def install do
    version = DartSass.configured_version()
    tmp_dir = Path.join(System.tmp_dir!(), "cs-dart-sass")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    name = "dart-sass-#{version}-#{target()}"
    url = "https://github.com/sass/dart-sass/releases/download/#{version}/#{name}"
    tar = fetch_body!(url)

    case :erl_tar.extract({:binary, tar}, [:compressed, cwd: tmp_dir]) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    bin_path = DartSass.bin_path()
    snapshot_path = DartSass.snapshot_path()
    vm_path = DartSass.vm_path()

    case :os.type() do
      {:win32, _} ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart.exe"]), vm_path)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot_path)

      {:unix, :darwin} ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart"]), vm_path)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot_path)

      _ ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "sass"]), bin_path)
    end
  end

  # Available targets: https://github.com/sass/dart-sass/releases
  defp target do
    case :os.type() do
      {:win32, _} ->
        "windows-#{:erlang.system_info(:wordsize) * 8}.zip"

      {:unix, osname} ->
        arch_str = :erlang.system_info(:system_architecture)
        [arch | _] = arch_str |> List.to_string() |> String.split("-")
        osname = if osname == :darwin, do: :macos, else: osname

        case arch do
          "x86_64" -> "#{osname}-x64.tar.gz"
          _ -> raise "could not download dart_sass for architecture: #{arch_str}"
        end
    end
  end

  defp fetch_body!(url) do
    url = String.to_charlist(url)
    Logger.debug("Downloading dart-sass from #{url}")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    cacertfile = CAStore.file_path() |> String.to_charlist()

    http_options = [
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    options = [body_format: :binary, cookies: :enabled]

    case :httpc.request(:get, {url, []}, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body

      other ->
        raise "couldn't fetch #{url}: #{inspect(other)}"
    end
  end
end
