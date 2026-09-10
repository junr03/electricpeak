{ config, pkgs, ... }:

let
  localRoot = config.services.photoWorkflow.localRoot;
  externalDevice = "/dev/disk/by-uuid/${config.services.photoWorkflow.external.filesystemUuid}";
  externalSubdirectory = config.services.photoWorkflow.external.destinationSubdirectory;
  externalRawSubdirectory = config.services.photoWorkflow.external.rawSubdirectory;
  internxtConfig = "/var/lib/photo-workflow/rclone.conf";
  statusCollector =
    (import ../../../../rust/packages.nix { inherit pkgs; }).rawbackup-status-collector;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/rawbackup/reconcile 0770 root root - -"
    "d /var/lib/rawbackup/reconcile/requests 0770 root root - -"
    "d /var/lib/rawbackup/reconcile/reports 0750 root root - -"
  ];

  # The web container can only enqueue an empty reconciliation request. The
  # host-side service performs the privileged, no-delete file operation.
  systemd.paths.rawbackup-reconcile = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      DirectoryNotEmpty = "/var/lib/rawbackup/reconcile/requests";
      Unit = "photo-workflow-reconcile.service";
    };
  };

  systemd.services.rawbackup-status = {
    description = "Collect a safe status snapshot for the Raw Backup dashboard";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      RAWBACKUP_LOCAL_ROOT = localRoot;
      RAWBACKUP_EXTERNAL_DEVICE = externalDevice;
      RAWBACKUP_EXTERNAL_SUBDIRECTORY = externalSubdirectory;
      RAWBACKUP_EXTERNAL_RAW_SUBDIRECTORY = externalRawSubdirectory;
      RAWBACKUP_INTERNXT_CONFIG = internxtConfig;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${statusCollector}/bin/rawbackup-status-collector";
      User = "root";
      StateDirectory = "rawbackup";
      StateDirectoryMode = "0755";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/rawbackup" ];
      TimeoutStartSec = "10min";
    };
  };

  systemd.timers.rawbackup-status = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };
}
