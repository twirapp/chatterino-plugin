#!/bin/sh
# Runs the plugin test suite from a scratch directory, so runtime files
# (cache.json) don't pollute the repository.
set -e

plugin_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

cd "$scratch"
lua5.4 "$plugin_dir/tests/test.lua" "$plugin_dir"
