defmodule Mix.Tasks.Sass do
  @moduledoc """
  Invokes sass with the given args.

  Usage:

  ```bash
  $ mix sass CONTEXT ARGS
  ```

  Example:

  ```bash
  $ mix sass default assets/css/app.scss priv/static/assets/app.css
  ```

  If dart-sass is not installed, it is automatically downloaded.
  Note the arguments given to this task will be appended
  to any configured arguments.
  """

  @shortdoc "Invokes sass with the profile and args"

  use Mix.Task

  @impl true
  def run([profile | args] = all) do
    if Code.ensure_loaded?(Mix.Tasks.App.Config) do
      Mix.Task.run("app.config")
    end

    case DartSass.install_and_run(String.to_atom(profile), args) do
      0 -> :ok
      status -> Mix.raise("`mix sass #{Enum.join(all, " ")}` exited with #{status}")
    end

    Mix.Task.reenable("sass")
  end

  def run([]) do
    Mix.raise("`mix sass` expects the profile as argument")
  end
end
