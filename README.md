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
    {:dart_sass, "~> 0.3", runtime: Mix.env() == :dev}
  ]
end
```

However, if your assets are precompiled during development,
then it only needs to be a dev dependency:

```elixir
def deps do
  [
    {:dart_sass, "~> 0.3", only: :dev}
  ]
end
```

Once installed, change your `config/config.exs` to pick your
dart_sass version of choice:

```elixir
config :dart_sass, version: "1.49.0"
```

Now you can install dart-sass by running:

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

The executable may be kept at `_build/sass-TARGET`. However in most cases
running dart-sass requires two files: the portable Dart VM is kept at
`_build/dart-TARGET` and the Sass snapshot is kept at `_build/sass.snapshot-TARGET`.
Where `TARGET` is your system target architecture.

## Profiles

The first argument to `dart_sass` is the execution profile.
You can define multiple execution profiles with the current
directory, the OS environment, and default arguments to the
`sass` task:

```elixir
config :dart_sass,
  version: "1.49.0",
  default: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
```

When `mix sass default` is invoked, the task arguments will be appended
to the ones configured above.

## Adding to Phoenix

To add `dart_sass` to an application using Phoenix, you need only four steps.
Note that installation requires that Phoenix watchers can accept `MFArgs`
tuples – so you must have Phoenix > v1.5.9.

First add it as a dependency in your `mix.exs`:

```elixir
def deps do
  [
    {:phoenix, "~> 1.6.0-rc.0"},
    {:dart_sass, "~> 0.2", runtime: Mix.env() == :dev}
  ]
end
```

Now let's configure `dart_sass` to use `assets/css/app.scss` as the input file and
compile CSS to the output location `priv/static/assets/app.css`:

```elixir
config :dart_sass,
  version: "1.49.0",
  default: [
    args: ~w(css/app.scss ../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]
```

> Note: if you are using esbuild (the default from Phoenix v1.6),
> make sure you remove the `import "../css/app.css"` line at the
> top of assets/js/app.js so `esbuild` stops generating css files.

> Note: make sure the "assets" directory from priv/static is listed
> in the :only option for Plug.Static in your endpoint file at,
> for instance `lib/my_app_web/endpoint.ex`.

For development, we want to enable watch mode. So find the `watchers`
configuration in your `config/dev.exs` and add:

```elixir
  sass: {
    DartSass,
    :install_and_run,
    [:default, ~w(--embed-source-map --source-map-urls=absolute --watch)]
  }
```

Note we are embedding source maps with absolute URLs and enabling the file system watcher.

Finally, back in your `mix.exs`, make sure you have an `assets.deploy`
alias for deployments, which will also use the `--style=compressed` option:

```elixir
"assets.deploy": [
  "esbuild default --minify",
  "sass default --no-source-map --style=compressed",
  "phx.digest"
]
```

## FAQ
### Compatibility with Alpine Linux (`mix sass default` exited with 2)
Dart-native executables rely on [glibc](https://www.gnu.org/software/libc/) to be present. Because Alpine Linux uses [musl](https://musl.libc.org/) instead, you have to add the package [alpine-pkg-glibc](https://github.com/sgerrand/alpine-pkg-glibc) to your installation. Follow the installation guide in the README.

Example for Docker (has to be added before running `mix sass`):
```Dockerfile
RUN wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
RUN wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.34-r0/glibc-2.34-r0.apk
RUN apk add glibc-2.34-r0.apk
```

In case you get the error `../../runtime/bin/eventhandler_linux.cc: 412: error: Failed to start event handler thread 1`, it means that your Docker installation or the used Docker-in-Docker image, is using a version below Docker 20.10.6. This error is related to an [updated version of the musl library](https://about.gitlab.com/blog/2021/08/26/its-time-to-upgrade-docker-engine). It can be resolved by using the [alpine-pkg-glibc](https://github.com/sgerrand/alpine-pkg-glibc) with the version 2.33 instead of 2.34.

Notes: The Alpine package gcompat vs libc6-compat will not work.

## Acknowledgements

This package is based on the excellent [esbuild](https://github.com/phoenixframework/esbuild) by Wojtek Mach and José Valim.

## License

Copyright (c) 2021 CargoSense, Inc.

dart_sass source code is licensed under the [MIT License](LICENSE.md).
