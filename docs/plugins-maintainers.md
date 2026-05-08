# OpenClaw Plugin Architecture (Maintainer Memo)

Purpose: extend OpenClaw capabilities without bloating core; ship tools + skills + config as reproducible units you can pin, test, and roll back. nix-openclaw shows the contract; OpenClaw core should treat the same interface as first-class, even off-Nix.

## What a Plugin Is (and is not)
- **Is:** bundle of binaries/CLIs, skills that teach the agent to use them, optional config/env requirements.
- **Not:** new transports/providers; model plumbing; secrets baked in; inline scripts or ad-hoc package-manager installs; a place for random config outside its scope.
- Why not skills-only: skills without binaries can hallucinate capability. Plugins ground skills in real tools and deliver versioned, reproducible functionality.

## Two Plugin Classes

Nix capability plugins are the tool/skill/env bundles described below. They do not use OpenClaw's JavaScript plugin loader. They are the right shape for CLIs such as `goplaces`, `gog`, `qmd`, `xuezh`, `camsnap`, and `summarize`.

OpenClaw plugins are runtime plugin directories with `openclaw.plugin.json` plus built JavaScript loaded by the gateway. They include bundled upstream plugins, official external plugins from OpenClaw's catalog or ClawHub, and third-party plugins. In Nix-managed deployments, these should be immutable plugin roots, not runtime npm installs hidden in host config.

Current nix-openclaw `customPlugins` implements both sides of the contract: package binaries on the gateway PATH, materialize skills, create state dirs, validate env files, render optional tool settings, and wire declared OpenClaw plugin roots into `plugins.load.paths` with an explicit default `plugins.entries.<id>.enabled` value.

PR #81 (`fix: copy plugin manifests into dist/extensions`) was related but not the missing external-plugin feature. It fixed bundled upstream plugin manifests missing from the packaged gateway `dist/extensions/*/openclaw.plugin.json` tree. Current packaging already copies those manifests and checks them in `openclaw-package-contents`.

Package authors can bridge the existing Nix contract to OpenClaw plugins:

- Extend `openclawPlugin` with an optional plugin declaration, for example `plugins = [ { id = "openclaw-weixin"; path = "${pkg}/lib/openclaw/plugins/openclaw-weixin"; enabled = true; } ];`.
- For each selected plugin artifact, append those paths to generated `plugins.load.paths`.
- Add a default `plugins.entries.<id>.enabled` value. `enabled` defaults to true, but plugin authors can set `enabled = false` for roots that should be discoverable while disabled until the host supplies config. User config can still override either default.
- Keep OpenClaw plugin config in `programs.openclaw.config` / `instances.<name>.config` so upstream schema validation remains the source of truth.
- Add a fixture shaped like `openclaw-weixin` so `customPlugins = [{ source = ...; }]` proves both package/skill wiring and OpenClaw plugin load wiring.

## Interface Contract (reference implementation: nix-openclaw)
Every plugin artifact exposes the same fields (flake output `openclawPlugin` today, but the shape is host-agnostic):

```nix
openclawPlugin = {
  name        = "summarize";                # unique; last-wins on collision
  skills      = [ ./skills/summarize ];      # dirs containing SKILL.md
  packages    = [ pkgs.summarize-cli ];      # binaries placed on the OpenClaw runtime PATH
  plugins     = [ ];                         # optional OpenClaw plugin roots: { id, path, enabled ? true }
  needs = {
    stateDirs   = [ ".config/summarize" ]; # created under $HOME
    requiredEnv = [ "SUMMARIZE_API_KEY" ];  # must point to files
  };
};
```

Host responsibilities (what the runtime guarantees):
- Resolve plugin source; read contract.
- Install `packages`; prepend to PATH for the gateway wrapper.
- Create `needs.stateDirs` under `$HOME`.
- Fail fast if any `requiredEnv` is unset or points to a missing/empty file.
- Copy/symlink each `skills` entry into `workspace/skills/<skill-dir-basename>/...`.
- If host config provides `config.settings`, render it to `config.json` in the first `stateDir`.
- Export `config.env` (plus required envs) into the gateway wrapper.
- Add declared OpenClaw plugin roots to `plugins.load.paths`, and set `plugins.entries.<id>.enabled` from the plugin contract as a default.
- Reject duplicate skill paths; duplicate plugin names: last entry wins.

### Host-side config shape
When enabling a plugin, the host can supply:

```nix
programs.openclaw.customPlugins = [
  {
    source = "github:owner/repo?rev=<commit>&narHash=<narHash>";
    config = {
      env = { KEY = "/run/agenix/key"; EXTRA = "/path/to/file"; };
      settings = { foo = "bar"; retries = 3; };
    };
  }
];
```

- `config.env`: values for `requiredEnv` (and any extra env to export).
- `config.settings`: JSON-rendered into `config.json` inside the first `stateDir`.
- Invariant: providing `settings` requires at least one `stateDir`.

Do not add raw npm package names to host config for the batteries-included path. Curated plugins packaged by this repo or `nix-openclaw-tools` should be exposed through package/check outputs so Garnix caches them.

OpenClaw native npm plugins use the same host list with an OpenClaw-style source:

```nix
programs.openclaw.customPlugins = [
  {
    source = "npm:@scope/openclaw-plugin@1.2.3";
    id = "openclaw-plugin";
    hash = lib.fakeHash; # replace with the sha256 Nix reports
  }
];
```

- `source`: currently supports registry npm specs with an explicit `npm:` prefix.
- `id`: required because the Home Manager module must enable the plugin at eval time without importing the built JavaScript package.
- `hash`: recursive output hash for the immutable plugin root; leave as `lib.fakeHash` to have Nix report the expected hash, then commit that value.
- Runtime plugin config belongs in `programs.openclaw.config.plugins.entries.<id>.config`, not in `customPlugins.config`.
- The module adds the built root to `plugins.load.paths` and writes a default `plugins.entries.<id>.enabled` value. OpenClaw owns runtime loading after that.

Curated npm plugins can be added to this repo or `nix-openclaw-tools` so Garnix caches them. Arbitrary user npm specs are still deterministic Nix artifacts, but this repo's cache cannot cover every user's private plugin choice. The user's local store or configured binary cache reuses the artifact until the source or hash changes. OpenClaw must not reinstall it on every gateway start.

## Dev workflow (fast iteration)
- Worktree: build and test plugins outside the core repo; point OpenClaw at a local path source during impure local dev (e.g., `source = "path:/Users/you/code/my-plugin"`). Committed config uses pinned refs.
- Rebuild loop: change plugin → `home-manager switch` (or host-equivalent) → gateway restarts with new PATH/skills/config; no manual copying.
- Name collisions: use the same plugin `name` to override a pinned version (last entry wins); keep unique names otherwise to avoid surprise overrides.
- Skills placement: skills land under `~/.openclaw*/workspace/skills/<skill-dir-basename>/...` so you can inspect quickly; delete the workspace to fully reset cached skills.
- Env guardrails: required env vars must point to files (non-empty) or the activation fails—supply temp files during dev to exercise the checks.
- Settings JSON: inspect the rendered `config.json` in the first `stateDir` to confirm schema and defaults before committing.

## Examples

### Minimal capability plugin (bundled `summarize`)
Enable (host side):

```nix
programs.openclaw.bundledPlugins.summarize.enable = true;
```

Plugin contract (inside the plugin repo):

```nix
openclawPlugin = {
  name = "summarize";
  skills = [ ./skills/summarize ];
  packages = [ self.packages.${system}.summarize-cli ];
  needs = { stateDirs = []; requiredEnv = []; };
};
```

### Plugin with required config/env (community `xuezh`)
Enable (host side):

```nix
programs.openclaw.customPlugins = [
  {
    source = "github:joshp123/xuezh?rev=<commit>&narHash=<narHash>";
    config = {
      env = {
        # Required envs (guarded as files):
        XUEZH_AZURE_SPEECH_KEY_FILE = "/run/agenix/xuezh-azure-speech-key";
        XUEZH_AZURE_SPEECH_REGION   = "/run/agenix/xuezh-azure-speech-region"; # file containing e.g. "westeurope"
      };
      settings = {
        audio = {
          backend_global        = "azure.speech";
          process_voice_backend = "azure.speech";
          convert_backend       = "ffmpeg";
          tts_backend           = "edge-tts";
          inline_max_bytes      = 200000;
        };
        azure = {
          speech = {
            key_file = "/run/agenix/xuezh-azure-speech-key";
            region   = "westeurope";
          };
        };
      };
    };
  }
];
```

Plugin contract (inside `xuezh`):

```nix
openclawPlugin = {
  name = "xuezh";
  skills = [ ./skills/xuezh ];
  packages = [ self.packages.${system}.default ];
  needs = {
    stateDirs   = [ ".config/xuezh" ];
    requiredEnv = [ "XUEZH_AZURE_SPEECH_KEY_FILE" "XUEZH_AZURE_SPEECH_REGION" ];
  };
};
```

Host behavior: creates `~/.config/xuezh/config.json` from `settings`; exports both envs; fails if the pointed files are missing/empty.

## Bundled Plugin Set (current)
- summarize, discrawl, wacrawl, peekaboo, poltergeist, sag, camsnap, gogcli, goplaces, sonoscli, imsg.
- Source of truth: `nix/modules/home-manager/openclaw/plugin-catalog.nix`.
- Each follows the same contract: packages + skills; env/state declared via `needs`; enabled via config toggle; sources pinned via the bundled plugin catalog.

## Authoring Rules
- Keep CLIs configurable via env; honor XDG paths; no inline scripts.
- Ship `AGENTS.md` in the plugin repo with knobs/paths (no secrets).
- `SKILL.md` should call the CLI by its PATH name (no absolute paths).
- If `config.settings` is expected, declare at least one `stateDir`.
- Add CI to build the plugin and validate `requiredEnv`/`stateDir` invariants.

## Why this approach
- Capability grounding: skills map to real tools, not hypothetical ones.
- Reproducibility: versioned bundle of tool + skill + config schema; easy rollback.
- Clean core: main OpenClaw stays transport/model-focused; plugins carry integrations.
- Operational sanity: one toggle wires tools, env, skills; failure is explicit and early.
- Portability: contract is host-agnostic; Nix just enforces determinism and zero drift.
