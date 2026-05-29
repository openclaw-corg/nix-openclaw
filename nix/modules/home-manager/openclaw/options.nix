{
  config,
  lib,
  pkgs,
  ...
}:

let
  openclawLib = import ./lib.nix { inherit config lib pkgs; };
  pluginOptionType = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.str;
        description = "nix-openclaw plugin source. Use a plugin flake source (github:/path:). OpenClaw npm runtime plugins use programs.openclaw.runtimePlugins.";
      };
      config = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "nix-openclaw plugin configuration (env/files/etc). Runtime OpenClaw plugin config belongs under programs.openclaw.config.plugins.entries.<id>.config.";
      };
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Unsupported legacy field for npm: runtime plugin sources.";
      };
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Unsupported legacy field for npm: runtime plugin sources.";
      };
      hash = lib.mkOption {
        type = lib.types.str;
        default = lib.fakeHash;
        description = "Unsupported legacy field for npm: runtime plugin sources.";
      };
    };
  };
  instanceModule = import ./options-instance.nix { inherit lib openclawLib pluginOptionType; };
  pluginCatalog = import ./plugin-catalog.nix;
  mkSkillOption = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Skill name (used as the directory name).";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Short description for the skill frontmatter.";
      };
      homepage = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional homepage URL for the skill frontmatter.";
      };
      body = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Optional skill body (markdown).";
      };
      openclaw = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
        description = "Optional openclaw metadata for the skill frontmatter.";
      };
      mode = lib.mkOption {
        type = lib.types.enum [
          "symlink"
          "copy"
          "inline"
        ];
        default = "symlink";
        description = "Skill source mode. inline renders body; symlink/copy import source as a Nix store skill directory and expose it through skills.load.extraDirs.";
      };
      source = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Source directory for symlink/copy skill modes. The directory must contain SKILL.md.";
      };
    };
  };

in
{
  options.programs.openclaw = {
    enable = lib.mkEnableOption "OpenClaw (batteries-included)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openclaw;
      description = "OpenClaw batteries-included package.";
    };

    toolNames = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Override the built-in toolchain names (see nix/tools/extended.nix).";
    };

    excludeTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Tool names to remove from the built-in toolchain.";
    };

    appPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional OpenClaw app package (defaults to package if unset).";
    };

    installApp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install OpenClaw.app at the default location.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${openclawLib.homeDir}/.openclaw";
      description = "State directory for OpenClaw (logs, sessions, config).";
    };

    workspaceDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.programs.openclaw.stateDir}/workspace";
      description = "Workspace directory for Openclaw agent skills (defaults to stateDir/workspace).";
    };

    workspace = {
      pinAgentDefaults = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pin agents.defaults.workspace to each instance workspaceDir when unset (prevents falling back to template ~/.openclaw/workspace).";
      };
    };

    runtimePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages visible to the OpenClaw gateway and isolated Codex harness only. These are not added to the user's PATH.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra runtime environment for OpenClaw gateway wrappers. Values that point to files are read at runtime unless the variable name ends in _FILE.";
    };

    documents = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a documents directory containing AGENTS.md, SOUL.md, and TOOLS.md.";
    };

    skills = lib.mkOption {
      type = lib.types.listOf mkSkillOption;
      default = [ ];
      description = "Declarative skills added to each instance's OpenClaw skill load paths.";
    };

    customPlugins = lib.mkOption {
      type = lib.types.listOf pluginOptionType;
      default = [ ];
      description = "Custom/community nix-openclaw plugins (merged with bundled plugin toggles).";
    };

    runtimePlugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "slack"
        "discord"
      ];
      description = "Supported OpenClaw catalog runtime plugin ids to package immutably and load through OpenClaw's plugins.load.paths.";
    };

    bundledPlugins = lib.mapAttrs (name: plugin: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = plugin.defaultEnable or false;
        description = "Enable the ${name} plugin (bundled).";
      };
      config = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Bundled plugin configuration passed through to ${name} (env/settings).";
      };
    }) pluginCatalog;

    launchd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via launchd (macOS).";
    };

    launchd.label = lib.mkOption {
      type = lib.types.str;
      default = "com.steipete.openclaw.gateway";
      description = "launchd label for the default OpenClaw instance.";
    };

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run OpenClaw gateway via systemd user service (Linux).";
    };

    systemd.unitName = lib.mkOption {
      type = lib.types.str;
      default = "openclaw-gateway";
      description = "systemd user service unit name for the default OpenClaw instance.";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = "Named OpenClaw instances (prod/test).";
    };

    exposePluginPackages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add plugin packages to home.packages so CLIs are on PATH.";
    };

    qmd.prewarmModels.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Download/check QMD's default GGUF models during Home Manager activation. This uses about 2.25GB under the user's QMD cache.";
    };

    reloadScript = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Install openclaw-reload helper for no-sudo config refresh + gateway restart.";
      };
    };

    config = lib.mkOption {
      type = lib.types.submodule { options = openclawLib.generatedConfigOptions; };
      default = { };
      description = "OpenClaw config (schema-typed).";
    };
  };
}
