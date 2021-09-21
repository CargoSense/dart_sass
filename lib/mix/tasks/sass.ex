defmodule Mix.Tasks.Sass do
  @moduledoc """
  Invokes sass with the given args.

  Usage:

      $ mix sass TASK_OPTIONS PROFILE SASS_ARGS

  Example:

      $ mix sass default assets/css/app.scss priv/static/assets/app.css

  If dart-sass is not installed, it is automatically downloaded.
  Note the arguments given to this task will be appended
  to any configured arguments.

  ## Options

    * `--runtime-config` - load the runtime configuration before executing
      command

  Note flags to control this Mix task must be given before the profile:

      $ mix sass --runtime-config default assets/css/app.scss
  """

  @shortdoc "Invokes sass with the profile and args"

  use Mix.Task

  @impl true
  def run(args) do
    switches = [runtime_config: :boolean]
    {opts, remaining_args} = OptionParser.parse_head!(args, switches: switches)

    if opts[:runtime_config] do
      Mix.Task.run("app.config")
    else
      Application.ensure_all_started(:dart_sass)
    end

    Mix.Task.reenable("sass")
    install_and_run(remaining_args)
  end

  defp install_and_run([profile | args] = all) do
    case DartSass.install_and_run(String.to_atom(profile), args) do
      0 -> :ok
      status -> Mix.raise("`mix sass #{Enum.join(all, " ")}` exited with #{status}")
    end
  end

  defp install_and_run([]) do
    Mix.raise("`mix sass` expects the profile as argument")
  end
end
