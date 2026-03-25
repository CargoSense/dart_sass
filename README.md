# DartSass

**Install and run [Dart Sass](https://github.com/sass/dart-sass) using Elixir.**

[![Package](https://img.shields.io/hexpm/v/dart_sass?logo=elixir&style=for-the-badge)](https://hex.pm/packages/dart_sass)
[![Downloads](https://img.shields.io/hexpm/dt/dart_sass?logo=elixir&style=for-the-badge)](https://hex.pm/packages/dart_sass)
[![Build](https://img.shields.io/github/actions/workflow/status/CargoSense/dart_sass/ci.yml?branch=main&logo=github&style=for-the-badge)](https://github.com/CargoSense/dart_sass/actions/workflows/ci.yml)

## Installation

Add DartSass to your project's dependencies in `mix.exs` and run `mix deps.get`.

If your application builds assets in production, configure DartSass as a runtime application in development:

```elixir
def deps do
  [
    {:dart_sass, "~> 0.7", runtime: Mix.env() == :dev}
  ]
end
```

If your application's assets are precompiled during development, configure DartSass as a dependency for the development environment only:

```elixir
def deps do
  [
    {:dart_sass, "~> 0.7", only: :dev}
  ]
end
```

Next, update your application's `config/config.exs` to set [a Dart Sass version](https://github.com/sass/dart-sass/releases):

```elixir
config :dart_sass, version: "1.97.3"
```

You may now install Dart Sass by running:

```bash
mix sass.install
```

Invoke the `sass` executable by running:

```bash
mix sass default assets/css/app.scss priv/static/assets/app.css
```

Additional load paths may be specified using the `--load-path` flag:

```bash
mix sass default assets/css/app.scss --load-path=assets/node_modules/bulma priv/static/assets/app.css
```

> [!NOTE]
> The `sass` executable may be installed to `_build/sass-<arch>`. In most cases, running Dart Sass requires the portable Dart virtual machine (`_build/dart-<arch>`) and the Sass snapshot (`_build/sass.snapshot-<arch>`) where `<arch>` is your system's architecture (e.g. `linux-arm64`).

## Configuring profiles

DartSass requires an execution profile as its first argument. You may define multiple execution profiles using the current directory, the environment, and default arguments:

```elixir
config :dart_sass,
  version: "1.97.3",
  default: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
```

Invoking `mix sass default` appends the task arguments to the ones configured above.

## Using with Phoenix

> [!NOTE]
> Using DartSass with [Phoenix](https://phoenixframework.org) requires Phoenix v1.5.10 or newer.

First, add Phoenix as a dependency to your application's `mix.exs`:

```elixir
def deps do
  [
    {:phoenix, "~> 1.7.14"},
    {:dart_sass, "~> 0.7", runtime: Mix.env() == :dev}
  ]
end
```

Next, configure DartSass to use `assets/css/app.scss` as the input file and set the output file to `../priv/static/assets/app.css`:

```elixir
config :dart_sass,
  version: "1.97.3",
  default: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
```

> [!NOTE]
> If your application uses [esbuild](https://esbuild.github.io), remove `import "../css/app.css"` from your application's `assets/js/app.js`. This change will prevent esbuild from _also_ generating CSS files.

> [!NOTE]
> Be sure to add `assets` (alongside other files from `priv/static`) to `Plug.Static`'s `only` filter in your application's `endpoint.ex` file.
>
> ```elixir
> plug Plug.Static,
>   at: "/",
>   from: :my_app,
>   only: ~w(assets favicon.ico robots.txt)
> ```

In development mode, configure Dart Sass' `--watch` flag in your application's `config/dev.exs` file:

```elixir
config :my_app,
  # …
  watchers: [
    sass: {
      DartSass,
      :install_and_run,
      [:default, ~w(--embed-source-map --source-map-urls=absolute --watch)]
    }
  ]
```

The configuration above also enables embedded source maps using aboslute URLs. Consult the [Dart Sass Command-Line Interface documentation](https://sass-lang.com/documentation/cli/dart-sass/) for a complete list and description of supported options.

> [!NOTE]
> When using the `--watch` option, the `sass` process is invoked using a Bash script to ensure graceful termination of the `sass` process when stdin closes. This script _is not_ invoked on Windows platforms, so using the `--watch` option may result in orphaned processes.

Finally, in your application's `mix.exs`, create or update the `assets.deploy` alias to include `sass` (in this example, configuring the output style):

```elixir
defp aliases do
  [
    # …
    "assets.deploy": [
      "esbuild default --minify",
      "sass default --no-source-map --style=compressed",
      "phx.digest"
    ],
    # …
  ]
end
```

## Acknowledgements

This package is based on [Wojtek Mach](https://github.com/wojtekmach)'s and [José Valim](https://github.com/josevalim)'s excellent [esbuild](https://github.com/phoenixframework/esbuild) installer.

## License

DartSass is freely available under the [MIT License](https://opensource.org/licenses/MIT).
