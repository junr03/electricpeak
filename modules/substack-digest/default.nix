{ config, lib, ... }:
let
  cfg = config.services.substackDigest;

in
{
  options.services.substackDigest = {
    enable = lib.mkEnableOption "the daily Substack PDF delivery (requires provisioned 1Password secrets)";
    calendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00:00 America/Los_Angeles";
      description = "systemd calendar for the daily digest, including timezone.";
    };
  };

  config = {
    # Compose pins the published image; this module owns activation and timing.
    systemd.services.docker-substack-digest = {
      enable = cfg.enable;
      wantedBy = lib.mkForce [ ];
      partOf = lib.mkForce [ ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Restart = lib.mkForce "on-failure";
        RestartSec = lib.mkForce "15min";
        RuntimeMaxSec = "2h";
      };
    };
    # compose2nix 0.3.2 does not translate Compose read_only/tmpfs.
    virtualisation.oci-containers.containers = lib.mkIf cfg.enable {
      substack-digest.extraOptions = [ "--read-only" "--tmpfs=/tmp:size=512m,mode=1777" ];
    };
    systemd.tmpfiles.rules = lib.optionals cfg.enable [
      "d /var/lib/substack-digest 0700 1000 100 - -"
    ];
    systemd.timers.substack-digest = lib.mkIf cfg.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.calendar;
        Persistent = true;
        AccuracySec = "1min";
        Unit = "docker-substack-digest.service";
      };
    };
  };
}
