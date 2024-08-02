#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
set -vx

mix local.hex --force
mix deps.get
