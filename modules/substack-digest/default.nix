{ config, lib, pkgs, ... }:
let
  cfg = config.services.substackDigest;
  source = builtins.path { path = ../../containers/source/utilities/substack-digest; name = "substack-digest"; };
  # A content-addressed tag prevents a stale local build after changing sources.
  imageTag = "electricpeak-substack-digest:${builtins.substring 0 16 (builtins.hashString "sha256" (toString source))}";
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
    # Compose defines the container; this module provides its local image and
    # timer. It is not a continuously running service or part of the boot target.
    systemd.services.docker-substack-digest = {
      enable = cfg.enable;
      wantedBy = lib.mkForce [ ];
      partOf = lib.mkForce [ ];
      requires = [ "substack-digest-build.service" ];
      after = [ "substack-digest-build.service" ];
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
    systemd.services.substack-digest-build = lib.mkIf cfg.enable {
      description = "Build the pinned OSS Substack digest container";
      requires = [ "docker.service" ];
      after = [ "docker.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.docker ];
      script = ''
        if ! docker image inspect ${lib.escapeShellArg imageTag} >/dev/null 2>&1; then
          docker build --tag ${lib.escapeShellArg imageTag} ${source}
        fi
        docker tag ${lib.escapeShellArg imageTag} electricpeak-substack-digest:local
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "30min";
      };
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
