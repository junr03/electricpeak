{ config, lib, pkgs, gallatin, utils, ... }:

let
  cfg = config.services.photoWorkflow;
  externalDevice = "/dev/disk/by-uuid/${cfg.external.filesystemUuid}";
  externalDeviceUnit = "${utils.escapeSystemdPath externalDevice}.device";
  externalMountUnit = "${utils.escapeSystemdPath cfg.external.mountPoint}.mount";
  internxtEmailSecret = config.services.onepassword-secrets.secretPaths.internxtEmail;
  internxtPasswordSecret = config.services.onepassword-secrets.secretPaths.internxtPassword;
  # This returns immediately; every workflow job asks the host to publish a
  # fresh snapshot when it starts and when it stops. A status-collection
  # failure must never prevent the backup job itself from running.
  refreshDashboardStatus = "-${pkgs.systemd}/bin/systemctl start --no-block rawbackup-status.service";
  progressCommand = "${pkgs.python3}/bin/python3 ${./progress.py}";
  fileTypes = "${./file-types.sh}";
  renamePicture = pkgs.callPackage "${gallatin}/rename-picture.nix" { };
  renderScript = path: from: to:
    builtins.replaceStrings from to (builtins.readFile path);

  importer = pkgs.writeShellApplication {
    name = "photo-workflow-importer";
    runtimeInputs = with pkgs; [ coreutils rsync util-linux ] ++ [ renamePicture ];
    text = renderScript
      ./importer.sh
      [ "@PYTHON@" "@PHOTO_WORKFLOW_SCRIPT@" "@FILE_TYPES@" ]
      [ "${pkgs.python3}/bin/python3" "${./import.py}" fileTypes ];
  };

  importRunner = pkgs.writeShellApplication {
    name = "photo-workflow-import-runner";
    runtimeInputs = with pkgs; [ coreutils findutils gawk gnugrep jq rsync util-linux ];
    text = renderScript
      ./import-runner.sh
      [ "@LOCAL_ROOT@" "@IMPORTER@" "@GREP@" "@PROGRESS@" "@FILE_TYPES@" ]
      [ cfg.localRoot "${importer}/bin/photo-workflow-importer" "${pkgs.gnugrep}/bin/grep" progressCommand fileTypes ];
  };

  externalSync = pkgs.writeShellApplication {
    name = "photo-workflow-external-sync";
    runtimeInputs = with pkgs; [ coreutils diffutils findutils gnused gnugrep rsync util-linux ];
    text = renderScript ./external-sync.sh [ "@PROGRESS@" "@FILE_TYPES@" ] [ progressCommand fileTypes ];
  };

  reconciler = pkgs.writeShellApplication {
    name = "photo-workflow-reconcile";
    runtimeInputs = with pkgs; [ coreutils findutils gawk gnugrep jq rclone rsync util-linux systemd ];
    text = renderScript ./reconcile.sh [ "@PROGRESS@" "@FILE_TYPES@" ] [ progressCommand fileTypes ];
  };

  internxtConfig = "/var/lib/photo-workflow/rclone.conf";
  internxtConfigurator = pkgs.writeShellApplication {
    name = "photo-workflow-configure-internxt";
    runtimeInputs = with pkgs; [ coreutils gnugrep rclone ];
    text = renderScript
      ./configure-internxt.sh
      [ "@INTERNXT_CONFIG@" "@INTERNXT_EMAIL_SECRET@" "@INTERNXT_PASSWORD_SECRET@" ]
      [ internxtConfig internxtEmailSecret internxtPasswordSecret ];
  };

  internxtBackup = pkgs.writeShellApplication {
    name = "photo-workflow-internxt-backup";
    runtimeInputs = with pkgs; [ coreutils rclone util-linux ];
    text = renderScript
      ./internxt-backup.sh
      [ "@LOCAL_ROOT@" "@INTERNXT_REMOTE_PATH@" "@INTERNXT_CONFIG@" "@PROGRESS@" "@FILE_TYPES@" ]
      [ cfg.localRoot cfg.internxt.remotePath internxtConfig progressCommand fileTypes ];
  };

  internxtCheck = pkgs.writeShellApplication {
    name = "photo-workflow-internxt-check";
    runtimeInputs = with pkgs; [ coreutils rclone util-linux ];
    text = renderScript
      ./internxt-check.sh
      [ "@LOCAL_ROOT@" "@INTERNXT_REMOTE_PATH@" "@INTERNXT_CONFIG@" "@PROGRESS@" "@FILE_TYPES@" ]
      [ cfg.localRoot cfg.internxt.remotePath internxtConfig progressCommand fileTypes ];
  };

  internxtSidecarBackup = pkgs.writeShellApplication {
    name = "photo-workflow-internxt-sidecar-backup";
    runtimeInputs = with pkgs; [ coreutils rclone util-linux ];
    text = renderScript
      ./internxt-sidecar-backup.sh
      [ "@LOCAL_ROOT@" "@INTERNXT_REMOTE_PATH@" "@INTERNXT_CONFIG@" "@PROGRESS@" "@FILE_TYPES@" ]
      [ cfg.localRoot cfg.internxt.remotePath internxtConfig progressCommand fileTypes ];
  };
in
{
  options.services.photoWorkflow = {
    enable = lib.mkEnableOption "automatic SD-card photo importing";

    localRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/data/photos";
      description = "Canonical local photo library root.";
    };

    external = {
      enable = lib.mkEnableOption "the removable external photo mirror";

      filesystemUuid = lib.mkOption {
        type = lib.types.str;
        default = "FF78-4719";
        description = "Filesystem UUID of the external photo mirror.";
      };

      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/run/photo-workflow/external";
        description = "Mount point for the external photo mirror while it is connected.";
      };

      destinationSubdirectory = lib.mkOption {
        type = lib.types.str;
        default = "photos";
        description = "Directory on the external device that contains the photo mirror; empty uses the filesystem root.";
      };

      rawSubdirectory = lib.mkOption {
        type = lib.types.str;
        default = "raw";
        description = "Directory under destinationSubdirectory that stores the local RAW library on the external device.";
      };

      fullCheckInterval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7 * 24 * 60 * 60;
        description = "Seconds between full checksum validations of the external mirror.";
      };
    };

    internxt = {
      enable = lib.mkEnableOption "Internxt photo backup";

      remotePath = lib.mkOption {
        type = lib.types.str;
        default = "photos";
        description = "Directory in the configured Internxt Drive remote.";
      };

      checkInterval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 7 * 24 * 60 * 60;
        description = "Seconds between full local-to-Internxt consistency checks.";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.localRoot}/.incoming 0750 root users - -"
      "d ${cfg.localRoot}/needs-review 0755 junr03 users - -"
      "d /var/lib/rawbackup/jobs 0755 root root 7d -"
    ] ++ lib.optional cfg.external.enable
      "d ${cfg.external.mountPoint} 0750 root root - -";

    services.udev.extraRules = ''
      # Card readers can emit either add or change after filesystem probing.
      # ATTRS walks from a partition to its removable parent disk; ATTR{../…}
      # does not reliably do that for udev rule matching.
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_DRIVE_FLASH_SD}=="1", ENV{ID_FS_UUID}!="${cfg.external.filesystemUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="photo-import@%k.service"
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", KERNEL=="mmcblk*p*", ENV{ID_FS_UUID}!="${cfg.external.filesystemUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="photo-import@%k.service"
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ATTRS{removable}=="1", ENV{ID_FS_UUID}!="${cfg.external.filesystemUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="photo-import@%k.service"
    '' + lib.optionalString cfg.external.enable ''
      # Mount the mirror when it is connected, then start the sync only after
      # systemd has mounted it. A successful sync queues the unmount service.
      ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_FS_UUID}=="${cfg.external.filesystemUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="${externalMountUnit} photo-external-sync.service"
    '';

    # BindsTo also makes systemd clean up the mount after an unexpected unplug.
    systemd.mounts = lib.optional cfg.external.enable {
      what = externalDevice;
      where = cfg.external.mountPoint;
      type = "auto";
      options = "nosuid,nodev";
      unitConfig = {
        BindsTo = [ externalDeviceUnit ];
        After = [ externalDeviceUnit ];
      };
    };

    systemd.services."photo-import@" = {
      description = "Import photos from SD card %i";
      after = [ "mnt-data.mount" ];
      wants = [ "mnt-data.mount" ];
      unitConfig.RequiresMountsFor = [ cfg.localRoot ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = refreshDashboardStatus;
        ExecStart = "${importRunner}/bin/photo-workflow-import-runner %i";
        ExecStopPost = refreshDashboardStatus;
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        RuntimeDirectory = "photo-workflow";
        RuntimeDirectoryMode = "0750";
        ReadWritePaths = [ cfg.localRoot "/var/lib/rawbackup/jobs" "/run/photo-workflow" "/run/lock" ];
        NoNewPrivileges = true;
        ExecStartPost =
          (lib.optional cfg.external.enable "${pkgs.systemd}/bin/systemctl start --no-block photo-external-sync.service")
          ++ (lib.optional cfg.internxt.enable "${pkgs.systemd}/bin/systemctl start --no-block photo-internxt-backup.service");
      };
    };

    systemd.services.photo-external-sync = lib.mkIf cfg.external.enable {
      description = "Union-sync the local photo library with the external mirror";
      # A sync can run for much longer than the deployment timeout.  Do not
      # restart it merely because its unit or runner changes during a switch:
      # the next device event, import, or hourly timer will use the new code.
      restartIfChanged = false;
      after = [ "mnt-data.mount" externalMountUnit ];
      wants = [ "mnt-data.mount" ];
      requires = [ externalMountUnit ];
      unitConfig = {
        RequiresMountsFor = [ cfg.localRoot ];
        ConditionPathExists = externalDevice;
      };
      environment = {
        PHOTO_WORKFLOW_LOCAL_ROOT = cfg.localRoot;
        PHOTO_WORKFLOW_MOUNT_POINT = cfg.external.mountPoint;
        PHOTO_WORKFLOW_DESTINATION_SUBDIRECTORY = cfg.external.destinationSubdirectory;
        PHOTO_WORKFLOW_EXTERNAL_RAW_SUBDIRECTORY = cfg.external.rawSubdirectory;
        PHOTO_WORKFLOW_FILESYSTEM_UUID = cfg.external.filesystemUuid;
        PHOTO_WORKFLOW_FULL_CHECK_INTERVAL = toString cfg.external.fullCheckInterval;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = refreshDashboardStatus;
        ExecStart = "${externalSync}/bin/photo-workflow-external-sync";
        ExecStopPost = refreshDashboardStatus;
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        StateDirectory = "photo-workflow";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "photo-workflow";
        RuntimeDirectoryMode = "0750";
        ReadWritePaths = [ cfg.localRoot "/run/photo-workflow" "/var/lib/photo-workflow" "/var/lib/rawbackup/jobs" "/run/lock" ];
        NoNewPrivileges = true;
        ExecStartPost =
          (lib.optional cfg.internxt.enable
            "${pkgs.systemd}/bin/systemctl start --no-block photo-internxt-sidecar-backup.service")
          ++ [ "${pkgs.systemd}/bin/systemctl start --no-block photo-external-unmount.service" ];
      };
    };

    # ExecStartPost is only reached after a successful external sync. Queueing
    # a separate unit lets the sync finish before its required mount is stopped;
    # failed syncs leave the SSD mounted so its contents remain available for
    # diagnosis and review.
    systemd.services.photo-external-unmount = lib.mkIf cfg.external.enable {
      description = "Unmount the external photo mirror after a successful sync";
      after = [ "photo-external-sync.service" ];
      unitConfig.ConditionPathIsMountPoint = cfg.external.mountPoint;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/umount ${cfg.external.mountPoint}";
        ExecStartPost = refreshDashboardStatus;
        User = "root";
        NoNewPrivileges = true;
      };
    };

    # This service is only activated by the dashboard's request path. It is
    # deliberately not attached to a boot target or timer: reconciliation can
    # copy a large photo-library union and must never delay a deployment.
    systemd.services.photo-workflow-reconcile = lib.mkIf (cfg.external.enable && cfg.internxt.enable) {
      description = "Reconcile photo files across local storage, SSD, and Internxt";
      after = [ "mnt-data.mount" "network-online.target" ];
      wants = [ "mnt-data.mount" "network-online.target" ];
      environment = {
        PHOTO_WORKFLOW_LOCAL_ROOT = cfg.localRoot;
        PHOTO_WORKFLOW_MOUNT_POINT = cfg.external.mountPoint;
        PHOTO_WORKFLOW_DESTINATION_SUBDIRECTORY = cfg.external.destinationSubdirectory;
        PHOTO_WORKFLOW_EXTERNAL_RAW_SUBDIRECTORY = cfg.external.rawSubdirectory;
        PHOTO_WORKFLOW_FILESYSTEM_UUID = cfg.external.filesystemUuid;
        PHOTO_WORKFLOW_EXTERNAL_MOUNT_UNIT = externalMountUnit;
        PHOTO_WORKFLOW_INTERNXT_CONFIG = internxtConfig;
        PHOTO_WORKFLOW_INTERNXT_REMOTE_PATH = cfg.internxt.remotePath;
        PHOTO_WORKFLOW_RECONCILE_STATE_DIR = "/var/lib/rawbackup/reconcile";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = refreshDashboardStatus;
        ExecStart = "${reconciler}/bin/photo-workflow-reconcile";
        ExecStopPost = refreshDashboardStatus;
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        RuntimeDirectory = "photo-workflow";
        RuntimeDirectoryMode = "0750";
        ReadWritePaths = [ cfg.localRoot cfg.external.mountPoint "/var/lib/rawbackup" "/run/photo-workflow" "/run/lock" ];
        NoNewPrivileges = true;
        TimeoutStartSec = "12h";
      };
    };

    systemd.timers.photo-external-sync = lib.mkIf cfg.external.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
    };

    systemd.services.photo-internxt-config = lib.mkIf cfg.internxt.enable {
      description = "Create the native rclone Internxt remote";
      wantedBy = [ "multi-user.target" ];
      after = [ "opnix-secrets.service" ];
      requires = [ "opnix-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${internxtConfigurator}/bin/photo-workflow-configure-internxt";
        User = "root";
        StateDirectory = "photo-workflow";
        StateDirectoryMode = "0700";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/photo-workflow" ];
        NoNewPrivileges = true;
      };
    };

    systemd.services.photo-internxt-backup = lib.mkIf cfg.internxt.enable {
      description = "Back up the photo library to Internxt Drive";
      after = [ "network-online.target" "photo-internxt-config.service" ];
      wants = [ "network-online.target" ];
      requires = [ "photo-internxt-config.service" ];
      environment.RCLONE_CONFIG = internxtConfig;
      unitConfig = {
        RequiresMountsFor = [ cfg.localRoot ];
        ConditionPathExists = internxtConfig;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = refreshDashboardStatus;
        ExecStart = "${internxtBackup}/bin/photo-workflow-internxt-backup";
        ExecStopPost = refreshDashboardStatus;
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.localRoot "/var/lib/rawbackup/jobs" "/run/lock" ];
        NoNewPrivileges = true;
        TimeoutStartSec = "12h";
      };
    };

    systemd.services.photo-internxt-sidecar-backup = lib.mkIf (cfg.external.enable && cfg.internxt.enable) {
      description = "Back up Photomator sidecars to Internxt Drive";
      after = [ "network-online.target" "photo-internxt-config.service" ];
      wants = [ "network-online.target" ];
      requires = [ "photo-internxt-config.service" ];
      environment.RCLONE_CONFIG = internxtConfig;
      unitConfig = {
        RequiresMountsFor = [ cfg.localRoot ];
        ConditionPathExists = internxtConfig;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = refreshDashboardStatus;
        ExecStart = "${internxtSidecarBackup}/bin/photo-workflow-internxt-sidecar-backup";
        ExecStopPost = refreshDashboardStatus;
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/rawbackup/jobs" "/run/lock" ];
        NoNewPrivileges = true;
        TimeoutStartSec = "12h";
      };
    };

    systemd.timers.photo-internxt-backup = lib.mkIf cfg.internxt.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 02:00:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };

    systemd.services.photo-internxt-check = lib.mkIf cfg.internxt.enable {
      description = "Verify the photo library against Internxt Drive";
      after = [ "network-online.target" "photo-internxt-config.service" ];
      wants = [ "network-online.target" ];
      requires = [ "photo-internxt-config.service" ];
      environment.RCLONE_CONFIG = internxtConfig;
      unitConfig = {
        RequiresMountsFor = [ cfg.localRoot ];
        ConditionPathExists = internxtConfig;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${internxtCheck}/bin/photo-workflow-internxt-check";
        User = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/rawbackup/jobs" "/run/lock" ];
        NoNewPrivileges = true;
        TimeoutStartSec = "12h";
      };
    };

    systemd.timers.photo-internxt-check = lib.mkIf cfg.internxt.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30min";
        OnUnitActiveSec = "${toString cfg.internxt.checkInterval}s";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
  };
}
