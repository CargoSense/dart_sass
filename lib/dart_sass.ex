defmodule DartSass do
  @moduledoc """
  DartSass is a installer and runner for [Sass](https://sass-lang.com/dart-sass).

  ## Profiles

  You can define multiple configuration profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :dart_sass,
        version: "1.49.0",
        default: [
          args: ~w(css/app.scss ../priv/static/assets/app.css),
          cd: Path.expand("../assets", __DIR__)
        ]

  ## Dart Sass configuration

  There are two global configurations for the `dart_sass` application:

    * `:version` - the expected Sass version.

    * `:path` - the path to the Sass executable. By default
      it is automatically downloaded and placed inside the `_build` directory
      of your current app. Note that if your system architecture requires a
      separate Dart VM executable to run, then `:path` should be defined as a
      list of absolute paths.

  Overriding the `:path` is not recommended, as we will automatically
  download and manage `sass` for you. But in case you can't download
  it (for example, the GitHub releases are behind a proxy), you may want to
  set the `:path` to a configurable system location.

  For instance, you can install `sass` globally with `npm`:

      $ npm install -g sass

  Then the executable will be at:

      NPM_ROOT/sass/sass.js

  Where `NPM_ROOT` is the result of `npm root -g`.

  Once you find the location of the executable, you can store it in a
  `MIX_SASS_PATH` environment variable, which you can then read in
  your configuration file:

      config :dart_sass, path: System.get_env("MIX_SASS_PATH")

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
    "1.49.0"
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
  Returns the path to the `sass` executable.

  Depending on your system target architecture, the path may be
  preceeded by the path to the Dart VM executable.
  """
  def bin_path do
    platform = platform()

    cond do
      env_path = Application.get_env(:dart_sass, :path) ->
        List.wrap(env_path)

      Code.ensure_loaded?(Mix.Project) ->
        bin_path(platform, Path.dirname(Mix.Project.build_path()))

      true ->
        bin_path(platform, "_build")
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
    path = bin_path()

    with true <- path_exists?(path),
         {result, 0} <- cmd(path, ["--version"]) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  defp cmd(path, args) do
    cmd(path, args, [])
  end

  defp cmd([command | args], extra_args, opts) do
    System.cmd(command, args ++ extra_args, opts)
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.
  """
  def run(profile, extra_args) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    config_args = config[:args] || []

    opts = [
      cd: config[:cd] || File.cwd!(),
      env: config[:env] || %{},
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    args = config_args ++ extra_args
    path = bin_path()

    # TODO: Remove when dart-sass will exit when stdin is closed.
    # Link: https://github.com/sass/dart-sass/pull/1411
    path =
      if "--watch" in args and platform() != :windows do
        [script_path() | path]
      else
        path
      end

    path
    |> cmd(args, opts)
    |> elem(1)
  end

  @doc """
  Installs, if not available, and then runs `sass`.

  Returns the same as `run/2`.
  """
  def install_and_run(profile, args) do
    unless path_exists?(bin_path()) do
      install()
    end

    run(profile, args)
  end

  @doc """
  Installs dart-sass with `configured_version/0`.
  """
  def install do
    version = configured_version()
    tmp_opts = if System.get_env("MIX_XDG"), do: %{os: :linux}, else: %{}

    tmp_dir =
      freshdir_p(:filename.basedir(:user_cache, "cs-sass", tmp_opts)) ||
        freshdir_p(Path.join(System.tmp_dir!(), "cs-sass")) ||
        raise "could not install sass. Set MIX_XDG=1 and then set XDG_CACHE_HOME to the path you want to use as cache"

    platform = platform()
    name = "dart-sass-#{version}-#{target_extname(platform)}"
    url = "https://github.com/sass/dart-sass/releases/download/#{version}/#{name}"
    archive = fetch_body!(url)

    case unpack_archive(Path.extname(name), archive, tmp_dir) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    path = bin_path()

    case platform do
      :linux ->
        [sass | _] = path
        File.rm(sass)
        File.cp!(Path.join([tmp_dir, "dart-sass", "sass"]), sass)

      :macos ->
        [dart, snapshot | _] = path
        File.rm(dart)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart"]), dart)
        File.rm(snapshot)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot)

      :windows ->
        [dart, snapshot | _] = path
        File.rm(dart)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "dart.exe"]), dart)
        File.rm(snapshot)
        File.cp!(Path.join([tmp_dir, "dart-sass", "src", "sass.snapshot"]), snapshot)
    end
  end

  defp bin_path(platform, base_path) do
    target = target(platform)

    case platform do
      :linux ->
        [Path.join(base_path, "sass-#{target}")]

      _ ->
        [
          Path.join(base_path, "dart-#{target}"),
          Path.join(base_path, "sass.snapshot-#{target}")
        ]
    end
  end

  defp platform do
    case :os.type() do
      {:unix, :darwin} -> :macos
      {:unix, :linux} -> :linux
      {:unix, osname} -> raise "dart_sass is not available for osname: #{inspect(osname)}"
      {:win32, _} -> :windows
    end
  end

  defp path_exists?(path) do
    Enum.all?(path, &File.exists?/1)
  end

  defp freshdir_p(path) do
    with {:ok, _} <- File.rm_rf(path),
         :ok <- File.mkdir_p(path) do
      path
    else
      _ -> nil
    end
  end

  defp unpack_archive(".zip", zip, cwd) do
    with {:ok, _} <- :zip.unzip(zip, cwd: to_charlist(cwd)), do: :ok
  end

  defp unpack_archive(_, tar, cwd) do
    :erl_tar.extract({:binary, tar}, [:compressed, cwd: to_charlist(cwd)])
  end

  defp target_extname(platform) do
    target = target(platform)

    case platform do
      :windows -> "#{target}.zip"
      _ -> "#{target}.tar.gz"
    end
  end

  # Available targets: https://github.com/sass/dart-sass/releases
  defp target(:windows) do
    case :erlang.system_info(:wordsize) * 8 do
      32 -> "windows-ia32"
      64 -> "windows-x64"
    end
  end

  defp target(platform) do
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
      "amd64" -> "#{platform}-x64"
      "x86_64" -> "#{platform}-x64"
      "i686" -> "#{platform}-ia32"
      "i386" -> "#{platform}-ia32"
      _ -> raise "dart_sass not available for architecture: #{arch_str}"
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
