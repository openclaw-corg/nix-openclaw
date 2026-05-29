{ lib, pkgs }:

let
  packageSet = pkgs.openclawRuntimePlugins or { };
  supportedIds = lib.attrNames packageSet;
  supportReportPath = "nix/generated/openclaw-runtime-plugins/report.json";

  duplicateIds =
    ids:
    let
      counts = lib.foldl' (acc: id: acc // { "${id}" = (acc.${id} or 0) + 1; }) { } ids;
    in
    lib.attrNames (lib.filterAttrs (_id: count: count > 1) counts);

  forInstance =
    {
      name,
      ids,
      existingLoadPaths,
      existingAllowList,
      userPluginEntries,
      denyList,
      nixOpenClawPluginIds,
    }:
    let
      duplicates = duplicateIds ids;
      unknownIds = lib.filter (id: !(builtins.hasAttr id packageSet)) ids;
      packages = if unknownIds == [ ] then map (id: packageSet.${id}) ids else [ ];
      collisions = lib.filter (id: lib.elem id nixOpenClawPluginIds) ids;
      disabledIds = lib.filter (id: (((userPluginEntries.${id} or { }).enabled or null) == false)) ids;
      deniedIds = lib.filter (id: lib.elem id denyList) ids;

      entriesConfig = lib.optionalAttrs (ids != [ ] && unknownIds == [ ]) {
        plugins.entries = lib.listToAttrs (
          map (id: {
            name = id;
            value.enabled = true;
          }) ids
        );
      };

      allowConfig = lib.optionalAttrs (ids != [ ] && existingAllowList != null) {
        plugins.allow = lib.unique (existingAllowList ++ ids);
      };
    in
    {
      inherit packages;
      loadPaths = map toString packages;
      config = lib.recursiveUpdate entriesConfig allowConfig;
      assertions = [
        {
          assertion = duplicates == [ ];
          message = "programs.openclaw.instances.${name}.runtimePlugins contains duplicate ids: ${lib.concatStringsSep ", " duplicates}";
        }
        {
          assertion = unknownIds == [ ];
          message = ''
            programs.openclaw.instances.${name}.runtimePlugins contains unsupported ids: ${lib.concatStringsSep ", " unknownIds}.
            Supported ids in this build: ${lib.concatStringsSep ", " supportedIds}
            Source/install specs such as npm:... or clawhub:... are not accepted here.
            Maintainers can inspect skipped-catalog diagnostics in ${supportReportPath}.
          '';
        }
        {
          assertion = collisions == [ ];
          message = "programs.openclaw.instances.${name}.runtimePlugins collides with nix-openclaw plugin ids: ${lib.concatStringsSep ", " collisions}";
        }
        {
          assertion = ids == [ ] || existingLoadPaths == [ ];
          message = "programs.openclaw.instances.${name}.runtimePlugins cannot be mixed with raw programs.openclaw.config.plugins.load.paths.";
        }
        {
          assertion = disabledIds == [ ];
          message = "programs.openclaw.instances.${name}.runtimePlugins selected ids disabled in config.plugins.entries: ${lib.concatStringsSep ", " disabledIds}";
        }
        {
          assertion = deniedIds == [ ];
          message = "programs.openclaw.instances.${name}.runtimePlugins selected ids denied in config.plugins.deny: ${lib.concatStringsSep ", " deniedIds}";
        }
      ];
    };
in
{
  inherit forInstance;
}
