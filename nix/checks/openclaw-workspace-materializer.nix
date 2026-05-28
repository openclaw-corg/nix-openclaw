{
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-workspace-materializer";
  version = "1";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  env = {
    OPENCLAW_WORKSPACE_MATERIALIZER = "${
      ../modules/home-manager/openclaw-materialize-workspace-files.sh
    }";
  };

  doCheck = true;
  checkPhase = "${../scripts/check-openclaw-workspace-materializer.sh}";

  installPhase = "${../scripts/empty-install.sh}";
}
