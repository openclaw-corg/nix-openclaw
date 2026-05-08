{
  lib,
  stdenvNoCC,
  nodejs_22,
}:

{
  id,
  source,
  hash ? lib.fakeHash,
}:

let
  npmSpec =
    if lib.hasPrefix "npm:" source then
      lib.removePrefix "npm:" source
    else
      throw "OpenClaw runtime npm plugin source must start with `npm:`: ${source}";
  safeName = lib.replaceStrings [ "@" "/" ":" ] [ "" "-" "-" ] id;
in
stdenvNoCC.mkDerivation {
  pname = "openclaw-runtime-plugin-${safeName}";
  version = "1";

  nativeBuildInputs = [ nodejs_22 ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = hash;

  env = {
    OPENCLAW_RUNTIME_PLUGIN_ID = id;
    OPENCLAW_RUNTIME_PLUGIN_NPM_SPEC = npmSpec;
  };

  installPhase = "${../scripts/npm-runtime-plugin-install.sh}";

  meta = with lib; {
    description = "Nix-packaged OpenClaw runtime plugin ${id} from ${source}";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
  };
}
