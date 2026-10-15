{ config, lib, pkgs, electricpeakServices, ... }:

let
  collector =
    (electricpeakServices.lib.mkStatusPackages { inherit pkgs; }).electricpeak-status-collector;
  # Only tools for services that are actually enabled; a missing one is
  # reported as "not installed" rather than failing the collector.
  tools =
    [ config.virtualisation.docker.package ]
    ++ lib.optional config.services.tailscale.enable config.services.tailscale.package
    ++ lib.optional config.services.zerotierone.enable config.services.zerotierone.package;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/electricpeak-status 0755 root root - -"
  ];

  # Root is required to read the ZeroTier auth token and the Docker socket.
  # The page container only receives the resulting JSON, read-only.
  systemd.services.electricpeak-status = {
    description = "Collect the public-safe server status snapshot";
    after = [ "docker.service" ];
    path = tools;
    environment.ELECTRICPEAK_STATUS_OUTPUT = "/var/lib/electricpeak-status/status.json";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${collector}/bin/electricpeak-status-collector";
      User = "root";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "/var/lib/electricpeak-status" ];
      TimeoutStartSec = "1min";
    };
  };

  systemd.timers.electricpeak-status = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };
}
