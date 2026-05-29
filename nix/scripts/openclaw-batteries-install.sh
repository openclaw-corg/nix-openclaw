#!/bin/sh
set -eu

if [ -z "${OPENCLAW_GATEWAY_BIN:-}" ]; then
  echo "OPENCLAW_GATEWAY_BIN is not set" >&2
  exit 1
fi
if [ ! -x "$OPENCLAW_GATEWAY_BIN" ]; then
  echo "OPENCLAW_GATEWAY_BIN is not executable: $OPENCLAW_GATEWAY_BIN" >&2
  exit 1
fi
if [ -z "${OPENCLAW_PINNED_WRITE_PYTHON:-}" ]; then
  echo "OPENCLAW_PINNED_WRITE_PYTHON is not set" >&2
  exit 1
fi
if [ ! -x "$OPENCLAW_PINNED_WRITE_PYTHON" ]; then
  echo "OPENCLAW_PINNED_WRITE_PYTHON is not executable: $OPENCLAW_PINNED_WRITE_PYTHON" >&2
  exit 1
fi
if [ -z "${STDENV_SETUP:-}" ]; then
  echo "STDENV_SETUP is not set" >&2
  exit 1
fi
if [ ! -f "$STDENV_SETUP" ]; then
  echo "STDENV_SETUP not found: $STDENV_SETUP" >&2
  exit 1
fi

mkdir -p "$out/bin"

if [ -n "${OPENCLAW_TOOLS_PATH:-}" ]; then
  bash -e -c '. "$STDENV_SETUP"; makeWrapper "$OPENCLAW_GATEWAY_BIN" "$out/bin/openclaw" --set OPENCLAW_PINNED_WRITE_PYTHON "$OPENCLAW_PINNED_WRITE_PYTHON" --set-default OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY "1" --prefix PATH : "$OPENCLAW_TOOLS_PATH"'
else
  bash -e -c '. "$STDENV_SETUP"; makeWrapper "$OPENCLAW_GATEWAY_BIN" "$out/bin/openclaw" --set OPENCLAW_PINNED_WRITE_PYTHON "$OPENCLAW_PINNED_WRITE_PYTHON" --set-default OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY "1"'
fi

if [ -n "${OPENCLAW_APP_PACKAGE:-}" ]; then
  app_dir="${OPENCLAW_APP_PACKAGE}/Applications"
  if [ ! -d "$app_dir" ]; then
    echo "OpenClaw app package has no Applications directory: $OPENCLAW_APP_PACKAGE" >&2
    exit 1
  fi

  mkdir -p "$out/Applications"
  found_app=0
  for app in "$app_dir"/*.app; do
    [ -e "$app" ] || continue
    ln -s "$app" "$out/Applications/$(basename "$app")"
    found_app=1
  done

  if [ "$found_app" -ne 1 ]; then
    echo "OpenClaw app package has no .app under: $app_dir" >&2
    exit 1
  fi
fi
