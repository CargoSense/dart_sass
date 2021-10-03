defmodule DartSass do
  @moduledoc """
  DartSass is a installer and runner for [sass](https://sass-lang.com/dart-sass).

  ## Profiles

  You can define multiple dart_sass profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :dart_sass,
        version: "1.39.0",
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
    "1.39.0"
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

  # TODO: Remove when dart-sass will exit when stdin is closed.
  @doc false
  def script_path() do
    Path.join(:code.priv_dir(:dart_sass), "dart_sass.bash")
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
    {path, args} =
      case bin_paths() do
        {sass, nil} -> {sass, args}
        {vm, snapshot} -> {vm, [snapshot] ++ args}
      end

    # TODO: Remove when dart-sass will exit when stdin is closed.
    # Link: https://github.com/sass/dart-sass/pull/1411
    cond do
      "--watch" in args and not match?({:win32, _}, :os.type()) ->
        {script_path(), [path] ++ args}

      true ->
        {path, args}
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

    {path, args} = sass(args ++ extra_args)

    path
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
    version = configured_version()
    tmp_dir = Path.join(System.tmp_dir!(), "cs-dart-sass")
    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    name = "dart-sass-#{version}-#{target()}"
    url = "https://github.com/sass/dart-sass/releases/download/#{version}/#{name}"
    archive = fetch_body!(url)

    case unpack_archive(Path.extname(name), archive, tmp_dir) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    sass_path = sass_path()
    snapshot_path = snapshot_path()
    vm_path = vm_path()

    case :os.type() do
      {:win32, _} ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart.exe"]), vm_path)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot_path)

      {:unix, :darwin} ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart"]), vm_path)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot_path)

      _ ->
        File.cp!(Path.join([tmp_dir, "dart-sass", "sass"]), sass_path)
    end
  end

  defp unpack_archive(".zip", zip, cwd) do
    with {:ok, _} <- :zip.unzip(zip, cwd: to_charlist(cwd)), do: :ok
  end

  defp unpack_archive(_, tar, cwd) do
    :erl_tar.extract({:binary, tar}, [:compressed, cwd: to_charlist(cwd)])
  end

  # Available targets: https://github.com/sass/dart-sass/releases
  # Can be manually specified for environments like the Apple M1 (for example: macos-x64 instead of aarch64-x64 to use Intel with Rosetta)
  defp target do
    case Application.fetch_env(:dart_sass, :binary_download_target) do
      {:ok, target} -> target
      :error -> guess_target()
    end
  end

  defp guess_target do
    case :os.type() do
      {:win32, _} ->
        case :erlang.system_info(:wordsize) * 8 do
          32 -> "windows-ia32.zip"
          64 -> "windows-x64.zip"
        end

      {:unix, osname} ->
        arch_str = :erlang.system_info(:system_architecture)
        [arch | _] = arch_str |> List.to_string() |> String.split("-")
        osname = if osname == :darwin, do: :macos, else: osname

        case arch do
          "amd64" -> "#{osname}-x64.tar.gz"
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
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, {url, []}, http_options, []) do
      {:ok, {{_, 302, _}, headers, _}} ->
        {'location', download} = List.keyfind(headers, 'location', 0)
        options = [body_format: :binary]

        case :httpc.request(:get, {download, []}, http_options, options) do
          {:ok, {{_, 200, _}, _, body}} ->
            body

          other ->
            raise "couldn't fetch #{download}: #{inspect(other)}"
        end

      other ->
        raise "couldn't fetch #{url}: #{inspect(other)}"
    end
  end
end
