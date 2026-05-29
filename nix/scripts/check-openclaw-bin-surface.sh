#!/bin/sh
set -eu

if [ -z "${OPENCLAW_PACKAGE:-}" ]; then
  echo "OPENCLAW_PACKAGE is not set" >&2
  exit 1
fi

bin_dir="${OPENCLAW_PACKAGE}/bin"
openclaw_bin="${bin_dir}/openclaw"

if [ ! -x "$openclaw_bin" ]; then
  echo "Missing executable: $openclaw_bin" >&2
  exit 1
fi

extra_bins="$(find "$bin_dir" -mindepth 1 -maxdepth 1 -print | while IFS= read -r entry; do
  name="$(basename "$entry")"
  if [ "$name" != "openclaw" ]; then
    printf '%s\n' "$name"
  fi
done)"

if [ -n "$extra_bins" ]; then
  echo "openclaw package exposes internal runtime tools in bin:" >&2
  printf '%s\n' "$extra_bins" >&2
  exit 1
fi

if ! grep -q 'PATH' "$openclaw_bin"; then
  echo "openclaw wrapper does not set the internal runtime tool PATH" >&2
  exit 1
fi

if ! grep -q 'OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY' "$openclaw_bin"; then
  echo "openclaw wrapper does not disable persisted plugin registry reads by default" >&2
  exit 1
fi

echo "openclaw bin surface: ok"
