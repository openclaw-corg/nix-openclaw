{
  lib,
  pkgs,
  stdenv,
}:

let
  testLib = lib.extend (
    _final: _prev: {
      hm.dag = {
        entryAfter = after: data: {
          inherit after data;
          before = [ ];
        };
      };
    }
  );

  lockedPathFlake =
    name: path: narHash:
    let
      # If a fixture changes, update with: nix hash path --sri nix/tests/plugins/<name>
      storePath = builtins.path {
        inherit name path;
        sha256 = narHash;
      };
    in
    "path:${builtins.unsafeDiscardStringContext (toString storePath)}?narHash=${narHash}";

  alphaPluginSource =
    lockedPathFlake "openclaw-test-plugin-alpha" ../tests/plugins/alpha
      "sha256-FV4UN38sPy2Yp/HhqUxd0HW5l2PcIBBmUz4JzxTAOXY=";
  betaPluginSource =
    lockedPathFlake "openclaw-test-plugin-beta" ../tests/plugins/beta
      "sha256-lDKtQKHZHqOkOprjLZzBEu8cFJhAdyEzsays9hdVeqE=";
  runtimePluginSource =
    lockedPathFlake "openclaw-test-plugin-runtime" ../tests/plugins/runtime
      "sha256-Ytei4j076EQ5rcpoiMt4BhSGUMtlU5kohQ+CCfKwxEE=";

  stubModule =
    { lib, ... }:
    {
      options = {
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [ ];
        };

        home.homeDirectory = lib.mkOption {
          type = lib.types.str;
          default = "/tmp";
        };

        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };

        home.file = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        home.activation = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        launchd.agents = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        systemd.user.services = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };

        programs.git.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };

        lib = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };
    };

  moduleEval =
    openclawConfig:
    testLib.evalModules {
      modules = [
        stubModule
        ../modules/home-manager/openclaw.nix
        (
          { lib, ... }:
          {
            config = {
              home.homeDirectory = "/tmp";
              programs.git.enable = false;
              lib.file.mkOutOfStoreSymlink = path: path;
              programs.openclaw = {
                enable = true;
                launchd.enable = pkgs.stdenv.hostPlatform.isDarwin;
                systemd.enable = pkgs.stdenv.hostPlatform.isLinux;
              }
              // openclawConfig;
            };
          }
        )
      ];
      specialArgs = { inherit pkgs; };
    };

  failedAssertions =
    eval: lib.filter (assertion: !(assertion.assertion or false)) eval.config.assertions;

  requireNoAssertionFailures =
    name: eval:
    let
      failures = failedAssertions eval;
      messages = map (assertion: assertion.message or "(no message)") failures;
    in
    if failures == [ ] then "ok" else throw "${name}: ${lib.concatStringsSep "; " messages}";

  requireAssertionFailure =
    name: needle: eval:
    let
      failures = failedAssertions eval;
      matching = lib.filter (assertion: lib.hasInfix needle (assertion.message or "")) failures;
    in
    if matching != [ ] then "ok" else throw "${name}: expected assertion containing `${needle}`.";

  qmdPath =
    if pkgs.openclawPackages ? qmd then
      builtins.unsafeDiscardStringContext "${pkgs.openclawPackages.qmd}/bin"
    else
      null;
  packageHasQmd =
    pkg:
    let
      pathText = builtins.unsafeDiscardStringContext (
        (pkg.OPENCLAW_TOOLS_PATH or "") + ":" + (pkg.OPENCLAW_QMD_PATH or "")
      );
    in
    qmdPath != null && lib.hasInfix qmdPath pathText;

  defaultEval = moduleEval { };
  defaultConfig = builtins.fromJSON defaultEval.config.home.file.".openclaw/openclaw.json".text;
  hasLinuxUnit = builtins.hasAttr "openclaw-gateway" defaultEval.config.systemd.user.services;
  hasDarwinAgent = builtins.hasAttr "com.steipete.openclaw.gateway" defaultEval.config.launchd.agents;
  defaultCheck = builtins.deepSeq (requireNoAssertionFailures "default instance" defaultEval) (
    if pkgs.stdenv.hostPlatform.isLinux && !hasLinuxUnit then
      throw "Default OpenClaw instance missing systemd.unitName."
    else if pkgs.stdenv.hostPlatform.isDarwin && !hasDarwinAgent then
      throw "Default OpenClaw instance missing launchd.label."
    else if (((defaultConfig.gateway or { }).mode or null) != "local") then
      throw "Default OpenClaw instance missing gateway.mode."
    else if lib.any packageHasQmd defaultEval.config.home.packages then
      throw "Default OpenClaw instance unexpectedly includes QMD on its runtime PATH."
    else
      "ok"
  );

  customPluginEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
    ];
  };
  customPluginConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext customPluginEval.config.home.file.".openclaw/openclaw.json".text
  );
  customPluginSkillExtraDirs = ((customPluginConfig.skills or { }).load or { }).extraDirs or [ ];
  customPluginCheck = builtins.deepSeq (requireNoAssertionFailures "customPlugins" customPluginEval) (
    if !(lib.any (path: lib.hasSuffix "/skill" path) customPluginSkillExtraDirs) then
      throw "customPlugins did not wire plugin skills into skills.load.extraDirs."
    else
      "ok"
  );

  multiAgentPluginSkillEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
    ];
    config.agents.list = [
      {
        id = "writer";
        workspace = "/tmp/openclaw-writer-workspace";
      }
      {
        id = "research";
        workspace = "/tmp/openclaw-research-workspace";
      }
    ];
  };
  multiAgentPluginSkillConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext
      multiAgentPluginSkillEval.config.home.file.".openclaw/openclaw.json".text
  );
  multiAgentPluginSkillExtraDirs = (
    ((multiAgentPluginSkillConfig.skills or { }).load or { }).extraDirs or [ ]
  );
  multiAgentWorkspaces = map (agent: agent.workspace) (
    ((multiAgentPluginSkillConfig.agents or { }).list or [ ])
  );
  multiAgentPluginSkillCheck =
    builtins.deepSeq (requireNoAssertionFailures "multi-agent plugin skills" multiAgentPluginSkillEval)
      (
        if !(lib.elem "/tmp/openclaw-writer-workspace" multiAgentWorkspaces) then
          throw "Multi-agent config lost writer workspace."
        else if !(lib.elem "/tmp/openclaw-research-workspace" multiAgentWorkspaces) then
          throw "Multi-agent config lost research workspace."
        else if !(lib.any (path: lib.hasSuffix "/skill" path) multiAgentPluginSkillExtraDirs) then
          throw "Custom plugin skill was not shared through skills.load.extraDirs for separate agent workspaces."
        else
          "ok"
      );

  duplicateSkillEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
      { source = betaPluginSource; }
    ];
  };
  duplicateSkillCheck =
    requireAssertionFailure "duplicate plugin skills"
      "Duplicate Nix-managed skill names detected: programs.openclaw.instances.default: skill"
      duplicateSkillEval;

  userPluginSkillCollisionEval = moduleEval {
    customPlugins = [
      { source = alphaPluginSource; }
    ];
    skills = [
      {
        name = "skill";
        mode = "inline";
      }
    ];
  };
  userPluginSkillCollisionCheck =
    requireAssertionFailure "user/plugin skill collision"
      "Duplicate Nix-managed skill names detected: programs.openclaw.instances.default: skill"
      userPluginSkillCollisionEval;

  userSkillEval = moduleEval {
    config.skills.load.extraDirs = [ "/tmp/user-skill-root" ];
    skills = [
      {
        name = "inline-skill";
        mode = "inline";
        description = "Inline test skill";
        body = "Use this test skill.";
      }
    ];
  };
  userSkillConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext userSkillEval.config.home.file.".openclaw/openclaw.json".text
  );
  userSkillExtraDirs = ((userSkillConfig.skills or { }).load or { }).extraDirs or [ ];
  generatedUserSkillExtraDirs = lib.filter (path: path != "/tmp/user-skill-root") userSkillExtraDirs;
  userSkillCheck = builtins.deepSeq (requireNoAssertionFailures "user skills" userSkillEval) (
    if !(lib.elem "/tmp/user-skill-root" userSkillExtraDirs) then
      throw "User skills.load.extraDirs entry was not preserved."
    else if generatedUserSkillExtraDirs == [ ] then
      throw "Nix-managed raw skill was not added to skills.load.extraDirs."
    else if userSkillExtraDirs != generatedUserSkillExtraDirs ++ [ "/tmp/user-skill-root" ] then
      throw "User skills.load.extraDirs entries should remain after Nix-managed skill dirs."
    else
      "ok"
  );

  secretProviderEval = moduleEval {
    config.secrets.providers.test-file = {
      source = "file";
      path = "/tmp/openclaw-secrets.json";
      mode = "json";
    };
  };
  secretProviderConfig =
    builtins.fromJSON
      secretProviderEval.config.home.file.".openclaw/openclaw.json".text;
  secretProviderCheck =
    builtins.deepSeq (requireNoAssertionFailures "secrets.providers" secretProviderEval)
      (
        if
          ((((secretProviderConfig.secrets or { }).providers or { }).test-file or { }).source == "file")
        then
          "ok"
        else
          throw "secrets.providers file variant missing from generated config."
      );

  secretRefPassthroughEval = moduleEval {
    config = {
      secrets.providers = {
        aws_test = {
          source = "exec";
          command = "/usr/bin/aws";
          args = [
            "secretsmanager"
            "get-secret-value"
            "--secret-id"
            "openclaw/groq"
          ];
          jsonOnly = false;
        };
        filemain = {
          source = "file";
          path = "/run/agenix/openclaw-secrets.json";
          mode = "json";
        };
      };

      models.providers = {
        groq = {
          baseUrl = "https://api.groq.com/openai/v1";
          api = "openai-completions";
          apiKey = {
            source = "exec";
            provider = "aws_test";
            id = "value";
          };
          models = [
            {
              id = "llama-3.3-70b-versatile";
              name = "Llama 3.3 70B";
            }
          ];
        };
        filebacked = {
          baseUrl = "https://example.invalid/v1";
          api = "openai-completions";
          apiKey = {
            source = "file";
            provider = "filemain";
            id = "/providers/filebacked/apiKey";
          };
          models = [
            {
              id = "test-model";
              name = "Test model";
            }
          ];
        };
      };
    };
  };
  secretRefPassthroughConfig =
    builtins.fromJSON
      secretRefPassthroughEval.config.home.file.".openclaw/openclaw.json".text;
  secretRefGroqApiKey =
    ((secretRefPassthroughConfig.models or { }).providers or { }).groq.apiKey or { };
  secretRefFileApiKey =
    ((secretRefPassthroughConfig.models or { }).providers or { }).filebacked.apiKey or { };
  secretRefPassthroughCheck =
    builtins.deepSeq (requireNoAssertionFailures "SecretRef passthrough" secretRefPassthroughEval)
      (
        if secretRefGroqApiKey.source != "exec" then
          throw "models.providers.groq.apiKey exec SecretRef was not rendered unchanged."
        else if secretRefGroqApiKey.provider != "aws_test" then
          throw "models.providers.groq.apiKey exec SecretRef provider was not rendered unchanged."
        else if secretRefGroqApiKey.id != "value" then
          throw "models.providers.groq.apiKey exec SecretRef id was not rendered unchanged."
        else if secretRefFileApiKey.source != "file" then
          throw "models.providers.filebacked.apiKey file SecretRef was not rendered unchanged."
        else if secretRefFileApiKey.provider != "filemain" then
          throw "models.providers.filebacked.apiKey file SecretRef provider was not rendered unchanged."
        else if secretRefFileApiKey.id != "/providers/filebacked/apiKey" then
          throw "models.providers.filebacked.apiKey file SecretRef id was not rendered unchanged."
        else
          "ok"
      );

  qmdPrewarmEval = moduleEval {
    qmd.prewarmModels.enable = true;
  };
  qmdPrewarmActivation = builtins.toJSON qmdPrewarmEval.config.home.activation.openclawQmdPrewarm;
  qmdPrewarmCheck = builtins.deepSeq (requireNoAssertionFailures "qmd.prewarmModels" qmdPrewarmEval) (
    if
      lib.hasInfix "OPENCLAW_QMD_BIN=" qmdPrewarmActivation
      && lib.hasInfix "openclaw-qmd-prewarm.sh" qmdPrewarmActivation
    then
      "ok"
    else
      throw "qmd.prewarmModels did not wire QMD model-cache prewarm activation."
  );

  qmdMemoryEval = moduleEval {
    config.memory.backend = "qmd";
  };
  qmdMemoryCheck = builtins.deepSeq (requireNoAssertionFailures "memory.backend qmd" qmdMemoryEval) (
    if lib.any packageHasQmd qmdMemoryEval.config.home.packages then
      "ok"
    else
      throw "memory.backend = qmd did not add QMD to the internal OpenClaw runtime."
  );

  runtimeProfileEval = moduleEval {
    runtimePackages = [ pkgs.jq ];
    environment.OPENCLAW_TEST_SECRET = "/tmp/openclaw-secret";
  };
  runtimeProfileActivation = builtins.toJSON runtimeProfileEval.config.home.activation.openclawCodexRuntimeProfiles;
  runtimeProfileCheck =
    builtins.deepSeq (requireNoAssertionFailures "runtime profile" runtimeProfileEval)
      (
        if lib.hasInfix "openclaw-link-codex-runtime-profiles.sh" runtimeProfileActivation then
          "ok"
        else
          throw "runtimePackages did not wire the Codex runtime profile activation."
      );

  openclawPluginEval = moduleEval {
    customPlugins = [
      { source = runtimePluginSource; }
    ];
    config.plugins.load.paths = [
      "/tmp/user-openclaw-plugin"
    ];
  };
  openclawPluginConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext
      openclawPluginEval.config.home.file.".openclaw/openclaw.json".text
  );
  openclawPluginLoadPaths = ((openclawPluginConfig.plugins or { }).load or { }).paths or [ ];
  openclawPluginEntry = ((openclawPluginConfig.plugins or { }).entries or { }).runtime-test or { };
  openclawPluginDisabledEntry =
    ((openclawPluginConfig.plugins or { }).entries or { }).runtime-disabled or null;
  openclawPluginCheck =
    builtins.deepSeq (requireNoAssertionFailures "OpenClaw plugin load" openclawPluginEval)
      (
        if !(lib.any (path: lib.hasSuffix "/plugin" path) openclawPluginLoadPaths) then
          throw "OpenClaw plugin root was not added to plugins.load.paths."
        else if !(lib.any (path: lib.hasSuffix "/disabled-plugin" path) openclawPluginLoadPaths) then
          throw "OpenClaw plugin root with enabled=false was not added to plugins.load.paths."
        else if !(lib.elem "/tmp/user-openclaw-plugin" openclawPluginLoadPaths) then
          throw "User-defined plugins.load.paths entry was not preserved."
        else if (openclawPluginEntry.enabled or false) != true then
          throw "OpenClaw plugin entry default was not enabled."
        else if (openclawPluginDisabledEntry.enabled or null) != false then
          throw "OpenClaw plugin entry with enabled=false did not render a disabled default."
        else
          "ok"
      );

  openclawPluginOverrideEval = moduleEval {
    customPlugins = [
      { source = runtimePluginSource; }
    ];
    config.plugins.entries.runtime-test.enabled = false;
  };
  openclawPluginOverrideConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext
      openclawPluginOverrideEval.config.home.file.".openclaw/openclaw.json".text
  );
  openclawPluginOverrideEntry =
    ((openclawPluginOverrideConfig.plugins or { }).entries or { }).runtime-test or { };
  openclawPluginOverrideDisabledEntry =
    ((openclawPluginOverrideConfig.plugins or { }).entries or { }).runtime-disabled or { };
  openclawPluginOverrideCheck =
    builtins.deepSeq (requireNoAssertionFailures "OpenClaw plugin override" openclawPluginOverrideEval)
      (
        if (openclawPluginOverrideEntry.enabled or null) != false then
          throw "User config could not override OpenClaw plugin enabled default."
        else if (openclawPluginOverrideDisabledEntry.enabled or null) != false then
          throw "Plugin enabled=false default did not survive when not overridden."
        else
          "ok"
      );

  openclawPluginEnableOverrideEval = moduleEval {
    customPlugins = [
      { source = runtimePluginSource; }
    ];
    config.plugins.entries.runtime-disabled.enabled = true;
  };
  openclawPluginEnableOverrideConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext
      openclawPluginEnableOverrideEval.config.home.file.".openclaw/openclaw.json".text
  );
  openclawPluginEnableOverrideEntry =
    ((openclawPluginEnableOverrideConfig.plugins or { }).entries or { }).runtime-disabled or { };
  openclawPluginEnableOverrideCheck =
    builtins.deepSeq
      (requireNoAssertionFailures "OpenClaw plugin enable override" openclawPluginEnableOverrideEval)
      (
        if (openclawPluginEnableOverrideEntry.enabled or null) == true then
          "ok"
        else
          throw "User config could not override OpenClaw plugin enabled=false default."
      );

  npmRuntimePluginEval = moduleEval {
    customPlugins = [
      {
        source = "npm:@tencent-weixin/openclaw-weixin@2.4.2";
        id = "openclaw-weixin";
        hash = lib.fakeHash;
      }
    ];
  };
  npmRuntimePluginConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext
      npmRuntimePluginEval.config.home.file.".openclaw/openclaw.json".text
  );
  npmRuntimePluginLoadPaths = ((npmRuntimePluginConfig.plugins or { }).load or { }).paths or [ ];
  npmRuntimePluginEntry =
    ((npmRuntimePluginConfig.plugins or { }).entries or { }).openclaw-weixin or { };
  npmRuntimePluginCheck =
    builtins.deepSeq (requireNoAssertionFailures "npm OpenClaw runtime plugin" npmRuntimePluginEval)
      (
        if
          !(lib.any (
            path: lib.hasInfix "openclaw-runtime-plugin-openclaw-weixin" path
          ) npmRuntimePluginLoadPaths)
        then
          throw "npm OpenClaw runtime plugin root was not added to plugins.load.paths."
        else if (npmRuntimePluginEntry.enabled or false) != true then
          throw "npm OpenClaw runtime plugin entry default was not enabled."
        else
          "ok"
      );

  checkKey = builtins.deepSeq [
    defaultCheck
    customPluginCheck
    multiAgentPluginSkillCheck
    duplicateSkillCheck
    userPluginSkillCollisionCheck
    userSkillCheck
    secretProviderCheck
    secretRefPassthroughCheck
    qmdPrewarmCheck
    qmdMemoryCheck
    runtimeProfileCheck
    openclawPluginCheck
    openclawPluginOverrideCheck
    openclawPluginEnableOverrideCheck
    npmRuntimePluginCheck
  ] "ok";

in
stdenv.mkDerivation {
  pname = "openclaw-default-instance";
  version = "1";
  dontUnpack = true;
  env = {
    OPENCLAW_DEFAULT_INSTANCE = checkKey;
  };
  installPhase = "${../scripts/empty-install.sh}";
}
