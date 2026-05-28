{
  lib,
  pkgs,
  openclawLib,
  enabledInstances,
  plugins,
}:

let
  cfg = openclawLib.cfg;
  resolvePath = openclawLib.resolvePath;
  toolSets = openclawLib.toolSets;
  documentsEnabled = cfg.documents != null;
  instanceWorkspaceDirs = map (inst: resolvePath inst.workspaceDir) (lib.attrValues enabledInstances);

  renderSkill =
    skill:
    let
      frontmatterLines = [
        "---"
        "name: ${skill.name}"
        "description: ${skill.description or ""}"
      ]
      ++ lib.optionals (skill ? homepage && skill.homepage != null) [ "homepage: ${skill.homepage}" ]
      ++ lib.optionals (skill ? openclaw && skill.openclaw != null) [
        "openclaw:"
        "  ${builtins.toJSON skill.openclaw}"
      ]
      ++ [ "---" ];
      frontmatter = lib.concatStringsSep "\n" frontmatterLines;
      body = if skill ? body then skill.body else "";
    in
    "${frontmatter}\n\n${body}\n";

  duplicateSkillAssertion =
    let
      targetsForInstance =
        instName: inst:
        let
          userTargets = map (skill: skill.name) cfg.skills;
          pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
          pluginTargets = lib.flatten (map (p: map builtins.baseNameOf p.skills) pluginsForInstance);
        in
        map (name: "${instName}:${name}") (userTargets ++ pluginTargets);
      skillTargetsByInstance = lib.flatten (lib.mapAttrsToList targetsForInstance enabledInstances);
      counts = lib.foldl' (
        acc: path: acc // { "${path}" = (acc.${path} or 0) + 1; }
      ) { } skillTargetsByInstance;
      duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
      renderDuplicate =
        duplicate:
        let
          parts = lib.splitString ":" duplicate;
          instName = lib.elemAt parts 0;
          skillName = lib.concatStringsSep ":" (lib.drop 1 parts);
        in
        "programs.openclaw.instances.${instName}: ${skillName}";
    in
    if duplicates == [ ] then
      [ ]
    else
      [
        {
          assertion = false;
          message = "Duplicate Nix-managed skill names detected: ${lib.concatStringsSep ", " (map renderDuplicate duplicates)}";
        }
      ];

  skillLoadDirsByInstance =
    let
      dirsForInstance =
        instName: inst:
        let
          dirFor =
            skill:
            let
              mode = skill.mode or "symlink";
              source = if skill ? source && skill.source != null then resolvePath skill.source else null;
            in
            if mode == "inline" then
              pkgs.writeTextDir "${skill.name}/SKILL.md" (renderSkill skill)
            else if mode == "copy" || mode == "symlink" then
              builtins.path {
                name = "openclaw-skill-${skill.name}";
                path = source;
              }
            else
              throw "Unsupported OpenClaw skill mode: ${mode}";
          pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
        in
        map toString ((map dirFor cfg.skills) ++ (lib.flatten (map (p: p.skills) pluginsForInstance)));
    in
    lib.mapAttrs dirsForInstance enabledInstances;

  skillLoadDirsForInstance = instName: skillLoadDirsByInstance.${instName} or [ ];

  documentsRequiredFiles = [
    "AGENTS.md"
    "SOUL.md"
    "TOOLS.md"
  ];

  documentsOptionalFiles = [
    "IDENTITY.md"
    "USER.md"
    "LORE.md"
    "HEARTBEAT.md"
    "PROMPTING-EXAMPLES.md"
  ];

  documentsFileNames =
    if documentsEnabled then
      let
        extra = lib.filter (file: builtins.pathExists (cfg.documents + "/${file}")) documentsOptionalFiles;
      in
      documentsRequiredFiles ++ extra
    else
      [ ];

  documentsAssertions = lib.optionals documentsEnabled [
    {
      assertion = builtins.pathExists cfg.documents;
      message = "programs.openclaw.documents must point to an existing directory.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/AGENTS.md");
      message = "Missing AGENTS.md in programs.openclaw.documents.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/SOUL.md");
      message = "Missing SOUL.md in programs.openclaw.documents.";
    }
    {
      assertion = builtins.pathExists (cfg.documents + "/TOOLS.md");
      message = "Missing TOOLS.md in programs.openclaw.documents.";
    }
  ];

  toolsReport =
    if documentsEnabled then
      let
        renderPkgName = pkg: if pkg ? pname then pkg.pname else lib.getName pkg;
        renderPkgCommand =
          pkg:
          let
            pkgName = renderPkgName pkg;
            commandName = pkg.meta.mainProgram or pkgName;
          in
          if commandName == pkgName then commandName else "${commandName} (${pkgName})";
        toolPackages = lib.filter (p: p != null) (toolSets.tools or [ ]);
        renderPlugin =
          plugin:
          let
            pkgNames = map renderPkgCommand (lib.filter (p: p != null) plugin.packages);
            pkgSuffix = if pkgNames == [ ] then "" else " — " + (lib.concatStringsSep ", " pkgNames);
          in
          "- " + plugin.name + pkgSuffix + " (" + plugin.source + ")";
        renderPkgList =
          packages:
          let
            actualPackages = lib.filter (p: p != null) packages;
          in
          if actualPackages == [ ] then
            [ "- (none)" ]
          else
            map (pkg: "- " + renderPkgCommand pkg) actualPackages;
        pluginLinesFor =
          instName: inst:
          let
            pluginsForInstance = plugins.resolvedPluginsByInstance.${instName} or [ ];
            pluginLines =
              if pluginsForInstance == [ ] then [ "- (none)" ] else map renderPlugin pluginsForInstance;
            instanceConfig = lib.recursiveUpdate (cfg.config or { }) (inst.config or { });
            qmdEnabled = (((instanceConfig.memory or { }).backend or null) == "qmd");
            runtimePackages = lib.unique (
              (lib.optional (qmdEnabled && openclawLib.qmdPackage != null) openclawLib.qmdPackage)
              ++ (cfg.runtimePackages or [ ])
              ++ (inst.runtimePackages or [ ])
            );
          in
          [
            ""
            "### Instance: ${instName}"
          ]
          ++ [
            ""
            "Plugins:"
          ]
          ++ pluginLines
          ++ [
            ""
            "Runtime packages:"
          ]
          ++ renderPkgList runtimePackages;
        reportLines = [
          "<!-- BEGIN NIX-REPORT -->"
          ""
          "## Nix-managed tools"
          ""
          "### Built-in toolchain"
        ]
        ++ (
          if toolPackages == [ ] then [ "- (none)" ] else map (pkg: "- " + renderPkgCommand pkg) toolPackages
        )
        ++ [
          ""
          "## Nix-managed plugin report"
          ""
          "Plugins enabled per instance (last-wins on name collisions):"
        ]
        ++ lib.concatLists (lib.mapAttrsToList pluginLinesFor enabledInstances)
        ++ [
          ""
          "Tools: batteries-included toolchain + runtime packages + plugin-provided CLIs."
          ""
          "<!-- END NIX-REPORT -->"
        ];
        reportText = lib.concatStringsSep "\n" reportLines;
      in
      pkgs.writeText "openclaw-tools-report.md" reportText
    else
      null;

  toolsWithReport =
    if documentsEnabled then
      pkgs.runCommand "openclaw-tools-with-report.md" { } ''
        cat ${cfg.documents + "/TOOLS.md"} > $out
        echo "" >> $out
        cat ${toolsReport} >> $out
      ''
    else
      null;

  documentEntries =
    if documentsEnabled then
      let
        mkDocFiles =
          dir:
          let
            mkDoc = name: {
              source = if name == "TOOLS.md" then toolsWithReport else cfg.documents + "/${name}";
              target = dir + "/${name}";
            };
          in
          map mkDoc documentsFileNames;
      in
      lib.flatten (map mkDocFiles instanceWorkspaceDirs)
    else
      [ ];

  materializedEntries = documentEntries;
  materializedManifest =
    let
      renderEntry = entry: "${entry.source}\t${entry.target}";
    in
    pkgs.writeText "openclaw-workspace-files.tsv" (
      (lib.concatStringsSep "\n" (map renderEntry materializedEntries)) + "\n"
    );

in
{
  inherit
    documentsEnabled
    documentsAssertions
    materializedManifest
    materializedEntries
    duplicateSkillAssertion
    skillLoadDirsForInstance
    ;
}
