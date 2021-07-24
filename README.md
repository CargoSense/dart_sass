# DartSass

[![CI](https://github.com/CargoSense/dart_sass/actions/workflows/main.yml/badge.svg)](https://github.com/CargoSense/dart_sass/actions/workflows/main.yml)

Mix tasks for installing and invoking [sass](https://github.com/sass/dart-sass/).

## Installation

If you are going to build assets in production, then you add
`dart_sass` as a dependency on all environments but only start it
in dev:

```elixir
def deps do
  [
    {:dart_sass, "~> 0.1", runtime: Mix.env() == :dev}
  ]
end
```

However, if your assets are precompiled during development,
then it only needs to be a dev dependency:

```elixir
def deps do
  [
    {:dart_sass, "~> 0.1", only: :dev}
  ]
end
```

Once installed, change your `config/config.exs` to pick your
dart_sass version of choice:

```elixir
config :dart_sass, version: "1.36.0"
```

Now you can install sass by running:

```bash
$ mix sass.install
```

And invoke sass with:

```bash
$ mix sass default assets/css/app.scss priv/static/assets/app.css
```

If you need additional load paths you may specify them:

```bash
$ mix sass default assets/css/app.scss --load-path=assets/node_modules/bulma priv/static/assets/app.css
```

The executable is kept at `_build/sass`.

### Profiles

The first argument to `dart_sass` is the execution profile.
You can define multiple execution profiles with the current
directory, the OS environment, and default arguments to the
`dart_sass` task:

```elixir
config :dart_sass,
  version: "1.36.0",
  default: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
```

When `mix sass default` is invoked, the task arguments will be appended
to the ones configured above.

## Acknowledgements

This package is based on the excellent [esbuild](https://github.com/phoenixframework/esbuild) by Wojtek Mach and José Valim.

## License

Copyright (c) 2021 CargoSense, Inc.

dart_sass source code is licensed under the [MIT License](LICENSE.md).
