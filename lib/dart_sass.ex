defmodule DartSass do
  @moduledoc """
  DartSass is a installer and runner for [Sass](https://sass-lang.com/guide).

  ## Profiles

  You can define multiple configuration profiles. By default, there is a
  profile called `:default` which you can configure its args, current
  directory and environment:

      config :dart_sass,
        version: "1.97.3",
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

  Note that overriding `:path` disables version checking.
  """

  use Application
  require Logger

  @doc false
  def start(_, _) do
    unless Application.get_env(:dart_sass, :path) do
      unless Application.get_env(:dart_sass, :version) do
        Logger.warning("""
        dart_sass version is not configured. Please set it in your config files:

            config :dart_sass, :version, "#{latest_version()}"
        """)
      end

      configured_version = configured_version()

      case bin_version() do
        {:ok, ^configured_version} ->
          :ok

        {:ok, version} ->
          Logger.warning("""
          Outdated dart-sass version. Expected #{configured_version}, got #{version}. \
          Please run `mix sass.install` or update the version in your config files.\
          """)

        :error ->
          :ok
      end
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  @doc false
  # Latest known version at the time of publishing.
  def latest_version, do: "1.97.3"

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
      unknown dart_sass profile. Make sure the profile named #{inspect(profile)} is defined in your config files, such as:

          config :dart_sass,
            #{profile}: [
              args: ~w(css/app.scss:../priv/static/assets/app.css),
              cd: Path.expand("../assets", __DIR__)
            ]
      """
  end

  defp dest_bin_paths(base_path) do
    target = target()
    ["dart", "sass.snapshot"] |> Enum.map(&Path.join(base_path, "#{&1}-#{target}"))
  end

  @doc """
  Returns the path to the `dart` VM executable and to the `sass` executable.
  """
  def bin_paths do
    cond do
      env_path = Application.get_env(:dart_sass, :path) ->
        List.wrap(env_path)

      Code.ensure_loaded?(Mix.Project) ->
        dest_bin_paths(Path.dirname(Mix.Project.build_path()))

      true ->
        dest_bin_paths("_build")
    end
  end

  # TODO: Remove when dart-sass will exit when stdin is closed.
  @doc false
  def script_path() do
    Path.join(:code.priv_dir(:dart_sass), "dart_sass.bash")
  end

  @doc """
  Returns the version of the Sass executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    paths = bin_paths()

    with true <- paths_exist?(paths),
         {result, 0} <- cmd(paths, ["--version"]) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  defp cmd([command_path | bin_paths], extra_args, opts \\ []) do
    System.cmd(command_path, bin_paths ++ extra_args, opts)
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

    # TODO: Remove when dart-sass will exit when stdin is closed.
    # Link: https://github.com/sass/dart-sass/pull/1411
    paths =
      if "--watch" in args and not windows?(),
        do: [script_path() | bin_paths()],
        else: bin_paths()

    paths
    |> cmd(args, opts)
    |> elem(1)
  end

  defp windows?, do: elem(:os.type(), 0) == :win32

  @doc """
  Installs, if not available, and then runs `sass`.

  Returns the same as `run/2`.
  """
  def install_and_run(profile, args) do
    unless paths_exist?(bin_paths()) do
      install()
    end

    run(profile, args)
  end

  @doc """
  Installs Sass with `configured_version/0`.
  """
  def install do
    target = target()
    version = configured_version()

    # Release name changes stabilized on v1.74.1, so we require at least that version.
    if Version.match?(version, "< 1.74.1") do
      raise "Installing dart_sass on requires version >= 1.74.1, got: #{inspect(version)}"
    end

    tmp_opts = if System.get_env("MIX_XDG"), do: %{os: :linux}, else: %{}

    tmp_dir =
      freshdir_p(:filename.basedir(:user_cache, "cs-sass", tmp_opts)) ||
        freshdir_p(Path.join(System.tmp_dir!(), "cs-sass")) ||
        raise "could not install sass. Set MIX_XDG=1 and then set XDG_CACHE_HOME to the path you want to use as cache"

    extname = if windows?(), do: "zip", else: "tar.gz"
    name = "dart-sass-#{version}-#{target}.#{extname}"
    url = "https://github.com/sass/dart-sass/releases/download/#{version}/#{name}"
    archive = fetch_body!(url)

    case unpack_archive(Path.extname(name), archive, tmp_dir) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    [dart, snapshot] = bin_paths()

    bin_suffix = if windows?(), do: ".exe", else: ""

    for {src_name, dest_path} <- [{"dart#{bin_suffix}", dart}, {"sass.snapshot", snapshot}] do
      File.rm(dest_path)
      File.cp!(Path.join([tmp_dir, "dart-sass", "src", src_name]), dest_path)
    end
  end

  defp paths_exist?(paths) do
    Enum.all?(paths, &File.exists?/1)
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

  # Available targets: https://github.com/sass/dart-sass/releases
  # * android-arm
  # * android-arm64
  # * android-riscv64
  # * android-x64
  # * linux-arm-musl
  # * linux-arm
  # * linux-arm64-musl
  # * linux-arm64
  # * linux-riscv64-musl
  # * linux-riscv64
  # * linux-x64-musl
  # * linux-x64
  # * macos-arm64
  # * macos-x64
  # * windows-arm64
  # * windows-x64
  defp target do
    arch_str = :erlang.system_info(:system_architecture)
    target_triple = arch_str |> List.to_string() |> String.split("-")

    {arch, abi} =
      case target_triple do
        [arch, _vendor, _system, abi] -> {arch, abi}
        [arch, _vendor, abi] -> {arch, abi}
        [arch | _] -> {arch, nil}
      end

    case {:os.type(), arch, abi, :erlang.system_info(:wordsize) * 8} do
      {{:win32, _}, "aarch64", _abi, 64} ->
        "windows-arm64"

      {{:win32, _}, _arch, _abi, 64} ->
        "windows-x64"

      {{:unix, :darwin}, arch, _abi, 64} when arch in ~w(arm aarch64) ->
        "macos-arm64"

      {{:unix, :darwin}, "x86_64", _abi, 64} ->
        "macos-x64"

      {{:unix, _osname}, "aarch64", abi, 64} ->
        "linux-arm64" <> maybe_add_abi_suffix(abi)

      {{:unix, _osname}, "arm", abi, 32} ->
        "linux-arm" <> maybe_add_abi_suffix(abi)

      {{:unix, _osname}, arch, abi, 64} when arch in ~w(x86_64 amd64) ->
        "linux-x64" <> maybe_add_abi_suffix(abi)

      {_os, _arch, _abi, _wordsize} ->
        raise "dart_sass is not available for architecture: #{arch_str}"
    end
  end

  defp maybe_add_abi_suffix("musl"), do: "-musl"
  defp maybe_add_abi_suffix(_), do: ""

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
    cacertfile = cacertfile() |> String.to_charlist()

    http_options = [
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        versions: protocol_versions()
      ]
    ]

    case :httpc.request(:get, {url, []}, http_options, []) do
      {:ok, {{_, 302, _}, headers, _}} ->
        {~c"location", download} = List.keyfind(headers, ~c"location", 0)
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

  defp protocol_versions do
    if otp_version() < 25 do
      [:"tlsv1.2"]
    else
      [:"tlsv1.2", :"tlsv1.3"]
    end
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  defp cacertfile() do
    Application.get_env(:dart_sass, :cacerts_path) || CAStore.file_path()
  end
end
