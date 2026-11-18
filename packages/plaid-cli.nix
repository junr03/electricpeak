{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# Plaid's official CLI. It is distributed only as prebuilt binaries
# (https://plaid.com/docs/resources/cli/) and is not packaged in nixpkgs.
# Plaid labels it experimental and ships it under a proprietary license.
# The Linux amd64 binary is statically linked.
let
  version = "20261017-c0f64a03";
in
stdenvNoCC.mkDerivation {
  pname = "plaid-cli";
  inherit version;

  src = fetchurl {
    url = "https://releases.plaid.com/plaid-cli/releases/${version}/plaid-cli_${version}_linux_amd64.tar.gz";
    hash = "sha256-9+xOr6xwEqqCkkKk/UsM3wsXm5GpopnAw8w1BU57NjM=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 plaid $out/bin/plaid
    runHook postInstall
  '';

  meta = {
    description = "CLI for the Plaid API";
    homepage = "https://plaid.com/docs/resources/cli/";
    license = lib.licenses.unfree;
    mainProgram = "plaid";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
