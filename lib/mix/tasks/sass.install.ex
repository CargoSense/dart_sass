defmodule Mix.Tasks.Sass.Install do
  @moduledoc """
  Installs dart-sass under `_build`.

  ```bash
  $ mix sass.install
  $ mix sass.install --if-missing
  ```

  By default, it installs #{DartSass.latest_version()} but you
  can configure it in your config files, such as:

      config :dart_sass, :version, "#{DartSass.latest_version()}"

  ## Options

    * `--runtime-config` - load the runtime configuration
        before executing command

    * `--if-missing` - install only if the given version
        does not exist

  """

  @shortdoc "Installs dart-sass under _build"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    valid_options = [runtime_config: :boolean, if_missing: :boolean]

    case OptionParser.parse_head!(args, strict: valid_options) do
      {opts, []} ->
        if opts[:runtime_config], do: Mix.Task.run("app.config")

        if opts[:if_missing] && latest_version?() do
          :ok
        else
          if function_exported?(Mix, :ensure_application!, 1) do
            Mix.ensure_application!(:inets)
            Mix.ensure_application!(:ssl)
          end

          DartSass.install()
        end

      {_, _} ->
        Mix.raise("""
        Invalid arguments to sass.install, expected one of:

            mix sass.install
            mix sass.install --runtime-config
            mix sass.install --if-missing
        """)
    end
  end

  defp latest_version?() do
    version = DartSass.configured_version()
    match?({:ok, ^version}, DartSass.bin_version())
  end
end
