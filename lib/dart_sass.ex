defmodule DartSass do
  @moduledoc """
  DartSass is a installer and runner for [Sass](https://sass-lang.com/dart-sass).

  ## Profiles

  You can define multiple configuration profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :dart_sass,
        version: "1.43.4",
        default: [
          args: ~w(css/app.scss ../priv/static/assets/app.css),
          cd: Path.expand("../assets", __DIR__)
        ]

  ## Dart Sass configuration

  There are three global configurations for the `dart_sass` application:

    * `:version` - the expected Sass version.

    * `:sass_path` - the path to the Sass snapshot or executable. By default
      it is automatically downloaded and placed inside the `_build` directory
      of your current app.

    * `:dart_path` - the path to the Dart VM executable. By default it is
      automatically downloaded and placed inside the `_build` directory
      of your current app. Note that the Dart Sass release for your
      operating system may not require a separate Dart executable.

  Overriding the `:sass_path` or `:dart_path` option is not recommended,
  as we will automatically download and manage Dart Sass for you,
  but in case you can't download it (for example, you are building
  from source), you may want to set the paths to a configurable
  system location. In your config files, do:

      config :dart_sass,
        sass_path: System.get_env("MIX_SASS_PATH")
        dart_path: System.get_env("MIX_SASS_DART_PATH")

  And then you can install Dart Sass elsewhere and configure the relevant
  environment variables.
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
    "1.43.4"
  end

  @doc """
  Returns the configured Sass version.
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
    case detect_platform() do
      %{cmd: sass, args: []} -> File.exists?(sass)
      %{cmd: dart, args: [snapshot]} -> File.exists?(dart) and File.exists?(snapshot)
    end
  end

  @doc """
  Returns information about the current environment.
  """
  def detect_platform do
    case :os.type() do
      {:unix, :darwin} ->
        %{platform: :macos, cmd: dart_path(), args: [snapshot_path()]}

      {:unix, osname} ->
        %{platform: osname, cmd: sass_path(), args: []}

      {:win32, _osname} ->
        %{platform: :windows, cmd: dart_path(), args: [snapshot_path()]}
    end
  end

  @doc false
  def dart_path do
    Application.get_env(:dart_sass, :dart_path) || build_path("dart")
  end

  @doc false
  def snapshot_path do
    Application.get_env(:dart_sass, :sass_path) || build_path("sass.snapshot")
  end

  @doc false
  def sass_path do
    Application.get_env(:dart_sass, :sass_path) || build_path("sass")
  end

  defp build_path(path) do
    if Code.ensure_loaded?(Mix.Project) do
      Path.join(Path.dirname(Mix.Project.build_path()), path)
    else
      "_build/#{path}"
    end
  end

  # TODO: Remove when dart-sass will exit when stdin is closed.
  @doc false
  def script_path() do
    Path.join(:code.priv_dir(:dart_sass), "dart_sass.bash")
  end

  @doc """
  Returns the version of the Sass executable (or snapshot).

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

  defp sass(extra_args) do
    %{cmd: cmd, args: args, platform: platform} = detect_platform()
    args = args ++ extra_args

    # TODO: Remove when dart-sass will exit when stdin is closed.
    # Link: https://github.com/sass/dart-sass/pull/1411
    cond do
      "--watch" in args and platform != :windows ->
        {script_path(), [cmd] ++ args}

      true ->
        {cmd, args}
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

    platform = detect_platform()
    name = "dart-sass-#{version}-#{target(platform)}"
    url = "https://github.com/sass/dart-sass/releases/download/#{version}/#{name}"
    archive = fetch_body!(url)

    case unpack_archive(Path.extname(name), archive, tmp_dir) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    case platform do
      %{platform: :linux, cmd: sass} ->
        File.rm(sass)
        File.cp!(Path.join([tmp_dir, "dart-sass", "sass"]), sass)

      %{platform: :macos, cmd: dart, args: [snapshot]} ->
        File.rm(dart)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart"]), dart)
        File.rm(snapshot)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot)

      %{platform: :windows, cmd: dart, args: [snapshot]} ->
        File.rm(dart)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart.exe"]), dart)
        File.rm(snapshot)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot)
    end
  end

  defp unpack_archive(".zip", zip, cwd) do
    with {:ok, _} <- :zip.unzip(zip, cwd: to_charlist(cwd)), do: :ok
  end

  defp unpack_archive(_, tar, cwd) do
    :erl_tar.extract({:binary, tar}, [:compressed, cwd: to_charlist(cwd)])
  end

  # Available targets: https://github.com/sass/dart-sass/releases
  defp target(%{platform: :windows}) do
    case :erlang.system_info(:wordsize) * 8 do
      32 -> "windows-ia32.zip"
      64 -> "windows-x64.zip"
    end
  end

  defp target(%{platform: platform}) do
    arch_str = :erlang.system_info(:system_architecture)
    [arch | _] = arch_str |> List.to_string() |> String.split("-")

    # TODO: remove "arm" when we require OTP 24
    arch =
      if platform == :macos and arch in ["aarch64", "arm"] do
        # Using Rosetta2 for M1 until sass/dart-sass runs native
        # Link: https://github.com/sass/dart-sass/issues/1125
        "amd64"
      else
        arch
      end

    case arch do
      "amd64" -> "#{platform}-x64.tar.gz"
      "x86_64" -> "#{platform}-x64.tar.gz"
      "i686" -> "#{platform}-ia32.tar.gz"
      "i386" -> "#{platform}-ia32.tar.gz"
      _ -> raise "could not download dart_sass for architecture: #{arch_str}"
    end
  end

  defp fetch_body!(url) do
    url = String.to_charlist(url)
    Logger.debug("Downloading dart-sass from #{url}")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    if proxy = System.get_env("HTTP_PROXY") || System.get_env("http_proxy") do
      Logger.debug("Using HTTP_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:proxy, {{String.to_charlist(host), port}, []}}])
    end

    if proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      Logger.debug("Using HTTPS_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:https_proxy, {{String.to_charlist(host), port}, []}}])
    end

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
