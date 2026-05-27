{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.26";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.26/OpenClaw-2026.5.26.zip";
    hash = "sha256-Kq6IGDw4hhwHLZSFtPnhoIFRBuE38SzgFOr6y/+yoTk=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
