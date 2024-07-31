# CHANGELOG

## v0.7.1

  * Update references to Dart Sass version to use latest `1.77.8` release
  * Update README to reflect minor version increase to `~> 0.7`, Dart Sass to `1.77.8`, edge Phoenix to `~> 1.7.14`
  * Fix Warning for elixir 1.17

## v0.7.0 (2023-06-27)

  * Require Elixir v1.11+
  * Mark inets and ssl as optional apps
  * Ensure the install task only loads the runtime config with `--runtime-config`

## v0.6.0 (2023-04-19)

**Potentially breaking change:** Due to a change in the upstream package structure, you must specify a `:version` >= 1.58.0 on Linux platforms.

- Updates Sass version to `1.61.0`.
- Renames DartSass.bin_path/0 to `DartSass.bin_paths/0`.
- Supports installation of newer upstream packages on Linux platforms. (h/t @azizk)
- Overriding `:path` disables version checking.
- Explicitly depends on `inets` and `ssl`. (h/t @josevalim)

## v0.5.1 (2022-08-26)

- Update Sass version to `1.54.5`
- Skip platform check when given a custom path (h/t @jgelens)
- Use only TLS 1.2 on OTP versions less than 25.

## v0.5.0 (2022-04-28)

- Support upstream arm64 binaries
- Update Sass version to `1.49.11`

## v0.4.0 (2022-01-19)

- Update Sass version to `1.49.0`
- Attach system target architecture to saved esbuild executable (h/t @cw789)
- Use user cache directory (h/t @josevalim)
- Add support for 32bit linux (h/t @derek-zhou)
- Support `HTTP_PROXY/HTTPS_PROXY` to fetch esbuild (h/t @iaddict)
- Fallback to \_build if Mix.Project is not available
- Allow `config :dart_sass, :path, path` to configure the path to the Sass executable (or snapshot)
- Support OTP 24 on Apple M1 architectures (via Rosetta2)

## v0.3.0 (2021-10-04)

- Use Rosetta2 for Apple M1 architectures until dart-sass ships native

## v0.2.1 (2021-09-23)

- Apply missing `--runtime-config` flag check to `mix sass.install`

## v0.2.0 (2021-09-21)

- No longer load `config/runtime.exs` by default, instead support `--runtime-config` flag
- Update initial `sass` version to `1.39.0`
- `mix sass.install --if-missing` also checks version

## v0.1.2 (2021-08-23)

- Fix target detection on FreeBSD (h/t @julp)
- Extract archive with charlist cwd option (h/t @michallepicki)

## v0.1.1 (2021-07-30)

- Fix installation path/unzip on windows
- Add wrapper script to address zombie processes

## v0.1.0 (2021-07-25)

- First release
