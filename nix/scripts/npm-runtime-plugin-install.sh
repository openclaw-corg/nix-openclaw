#!/bin/sh
set -e

spec="${OPENCLAW_RUNTIME_PLUGIN_NPM_SPEC:?OPENCLAW_RUNTIME_PLUGIN_NPM_SPEC is required}"
id="${OPENCLAW_RUNTIME_PLUGIN_ID:?OPENCLAW_RUNTIME_PLUGIN_ID is required}"

package_name="$(
  node -e '
const spec = process.env.OPENCLAW_RUNTIME_PLUGIN_NPM_SPEC || "";
const withoutProtocol = spec.startsWith("npm:") ? spec.slice(4) : spec;
const at = withoutProtocol.startsWith("@")
  ? withoutProtocol.indexOf("@", 1)
  : withoutProtocol.indexOf("@");
const name = at === -1 ? withoutProtocol : withoutProtocol.slice(0, at);
if (!name || name.startsWith("git+") || name.includes("://")) {
  process.exit(1);
}
process.stdout.write(name);
'
)" || {
  echo "Only registry npm package specs are supported for OpenClaw runtime plugins: $spec" >&2
  exit 1
}

export HOME="$TMPDIR/home"
export npm_config_cache="$TMPDIR/npm-cache"
export npm_config_ignore_scripts=true
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false

project="$TMPDIR/openclaw-runtime-plugin"
mkdir -p "$HOME" "$npm_config_cache" "$project"
cd "$project"

npm init -y >/dev/null
npm install --ignore-scripts --omit=dev --no-audit --no-fund --package-lock=false "$spec"

package_dir="node_modules/$package_name"
if [ ! -d "$package_dir" ]; then
  echo "npm install did not produce $package_dir for $spec" >&2
  exit 1
fi

if [ ! -f "$package_dir/openclaw.plugin.json" ] && [ ! -f "$package_dir/package.json" ]; then
  echo "npm package $spec does not look like an OpenClaw runtime plugin" >&2
  exit 1
fi

mkdir -p "$out"
cp -R "$package_dir/." "$out/"

if [ -d node_modules ]; then
  mkdir -p "$out/node_modules"
  cp -R node_modules/. "$out/node_modules/"
  rm -rf "$out/node_modules/$package_name"
fi

find "$out" -name .package-lock.json -type f -delete

if [ ! -f "$out/openclaw.plugin.json" ]; then
  node -e '
const fs = require("fs");
const path = require("path");
const pkg = JSON.parse(fs.readFileSync(path.join(process.env.out, "package.json"), "utf8"));
const entries = pkg.openclaw?.runtimeExtensions || pkg.openclaw?.extensions || [];
if (!Array.isArray(entries) || entries.length === 0) process.exit(1);
'
fi

printf '%s\n' "$spec" > "$out/.nix-openclaw-npm-spec"
printf '%s\n' "$id" > "$out/.nix-openclaw-plugin-id"
