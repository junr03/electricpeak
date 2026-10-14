{ pkgs, ... }:

let
  gam7 = pkgs.stdenvNoCC.mkDerivation {
    pname = "gam7";
    version = "7.48.16";
    src = pkgs.fetchurl {
      url = "https://github.com/GAM-team/GAM/releases/download/v7.48.16/gam-7.48.16-linux-x86_64-glibc2.35.tar.xz";
      hash = "sha256-2+JOJI+O0xFgzSib6rozo8MXvUzGaAvOWLj+XOSi7fM=";
    };
    sourceRoot = "gam7";
    installPhase = ''
      mkdir -p "$out"
      cp -a . "$out/"
    '';
  };
in
{
  environment.etc."electricpeak/gam7".source = gam7;
  environment.etc."electricpeak/kindle-gmail-send.py" = {
    source = ../../containers/source/media/kindle-gmail-send.py;
    mode = "0555";
  };
}
