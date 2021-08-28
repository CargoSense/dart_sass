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

  You can pass the `--if-missing` flag to only install it if
  one does not yet exist.
  """

  @shortdoc "Installs dart-sass under _build"
  use Mix.Task

  @impl true
  def run(args) do
    case OptionParser.parse_head!(args, strict: [if_missing: :boolean]) do
      {opts, []} ->
        if opts[:if_missing] && latest_version?() do
          :ok
        else
          if Code.ensure_loaded?(Mix.Tasks.App.Config) do
            Mix.Task.run("app.config")
          end

          DartSass.install()
        end

      {_, _} ->
        Mix.raise("""
        Invalid arguments to sass.install, expected one of:

            mix sass.install
            mix sass.install --if-missing
        """)
    end
  end

  defp latest_version?() do
    version = DartSass.configured_version()
    match?({:ok, ^version}, DartSass.bin_version())
  end
end
