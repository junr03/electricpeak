{ pkgs }:

let
  rawbackupRuntimePath = pkgs.lib.makeBinPath (with pkgs; [
    coreutils
    exiftool
    rclone
    util-linux
    systemd
  ]);
in
{
  rawbackup-status-collector = pkgs.rustPlatform.buildRustPackage {
    pname = "rawbackup-status-collector";
    version = "0.1.0";

    src = pkgs.lib.cleanSource ./.;
    cargoLock.lockFile = ./Cargo.lock;

    cargoBuildFlags = [ "-p" "rawbackup-status" ];
    cargoTestFlags = [ "-p" "rawbackup-status" ];
    strictDeps = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      install -Dm755 \
        "target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/rawbackup-status-collector" \
        "$out/bin/rawbackup-status-collector"
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram "$out/bin/rawbackup-status-collector" \
        --prefix PATH : ${rawbackupRuntimePath}
    '';

    meta = {
      description = "Build the Raw Backup dashboard status snapshot";
      mainProgram = "rawbackup-status-collector";
      platforms = pkgs.lib.platforms.linux;
    };
  };

  electricpeak-status-collector = pkgs.rustPlatform.buildRustPackage {
    pname = "electricpeak-status-collector";
    version = "0.1.0";

    src = pkgs.lib.cleanSource ./.;
    cargoLock.lockFile = ./Cargo.lock;

    cargoBuildFlags = [ "-p" "electricpeak-status" ];
    cargoTestFlags = [ "-p" "electricpeak-status" ];
    strictDeps = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 \
        "target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/electricpeak-status-collector" \
        "$out/bin/electricpeak-status-collector"
      runHook postInstall
    '';

    meta = {
      description = "Collect the public-safe home server status snapshot";
      mainProgram = "electricpeak-status-collector";
      platforms = pkgs.lib.platforms.linux;
    };
  };
}
