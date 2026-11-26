# Auto-generated using compose2nix v0.3.2.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."contact-sync" = {
    image = "bleala/vdirsyncer:2.6.1@sha256:cbe4a492453b597fdeef996a7e1555c8da9208307efb2ec1e4a059cda6123b3d";
    environment = {
      "AUTODISCOVER" = "false";
      "AUTOSYNC" = "true";
      "AUTOUPDATE" = "false";
      "CRON_TIME" = "*/15 * * * *";
      "PRE_SYNC_SCRIPT_FILE" = "/vdirsyncer/require-enabled.sh";
      "TZ" = "America/Los_Angeles";
    };
    volumes = [
      "/run/onepassword-secrets/vdirsyncerGoogleClientId:/vdirsyncer/secrets/google-client-id:ro"
      "/run/onepassword-secrets/vdirsyncerGoogleClientSecret:/vdirsyncer/secrets/google-client-secret:ro"
      "/run/onepassword-secrets/vdirsyncerIcloudAppPassword:/vdirsyncer/secrets/icloud-app-password:ro"
      "/run/onepassword-secrets/vdirsyncerIcloudUsername:/vdirsyncer/secrets/icloud-username:ro"
      "/var/lib/electricpeak/appdata/vdirsyncer:/vdirsyncer:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=contact-sync"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-contact-sync" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."foodlog-sync" = {
    image = "ghcr.io/junr03/foodlog-sync:latest";
    environment = {
      "CRONOMETER_ACCOUNT_TZ" = "America/Los_Angeles";
      "CRONOMETER_PASSWORD_FILE" = "/run/secrets/cronometer-password";
      "CRONOMETER_SESSION_PATH" = "/data/cronometer-session.json";
      "CRONOMETER_USERNAME_FILE" = "/run/secrets/cronometer-username";
      "FOODLOG_DATABASE_PATH" = "/data/ledger.sqlite3";
      "FOODLOG_ENABLE_WRITES" = "true";
      "FOODLOG_RAW_DIR" = "/data/raw";
      "GOOGLE_DRIVE_FOLDER_ID_FILE" = "/run/secrets/google-drive-folder-id";
      "GOOGLE_DRIVE_TOKEN_FILE" = "/run/secrets/google-drive-token.json";
    };
    volumes = [
      "/run/onepassword-secrets/foodlogCronometerPassword:/run/secrets/cronometer-password:ro"
      "/run/onepassword-secrets/foodlogCronometerUsername:/run/secrets/cronometer-username:ro"
      "/run/onepassword-secrets/foodlogGoogleDriveFolderId:/run/secrets/google-drive-folder-id:ro"
      "/run/onepassword-secrets/foodlogGoogleDriveToken:/run/secrets/google-drive-token.json:ro"
      "/var/lib/electricpeak/appdata/foodlog-sync:/data:rw"
    ];
    cmd = [ "--write" "--poll-interval" "900" ];
    user = "1000:100";
    log-driver = "journald";
    extraOptions = [
      "--network-alias=foodlog-sync"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-foodlog-sync" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."opendashboards" = {
    image = "ghcr.io/junr03/electricpeak-services/opendashboards@sha256:0a5d623b516c397687d2b3bc6a3ff11687060ce23036098f87d3345f9b2b7940";
    environment = {
      "APP_ORIGIN" = "https://dashboards.example.invalid";
      "OPENDASHBOARDS_PRIVATE_DESTINATIONS_FILE" = "/run/secrets/private-destinations.json";
    };
    volumes = [
      "/run/onepassword-secrets/opendashboardsPrivateDestinations:/run/secrets/private-destinations.json:ro"
      "/run/onepassword-secrets/thesysApiKey:/run/secrets/thesys-api-key:ro"
      "/var/lib/opendashboards/state:/data:ro"
    ];
    dependsOn = [
      "opendashboards-db"
      "opendashboards-init"
    ];
    user = "1000:100";
    log-driver = "journald";
    extraOptions = [
      "--cap-drop=ALL"
      "--network-alias=opendashboards"
      "--network=electricpeak"
      "--network=opendashboards-db"
      "--security-opt=no-new-privileges:true"
    ];
  };
  systemd.services."docker-opendashboards" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-opendashboards-db.service"
    ];
    requires = [
      "docker-network-opendashboards-db.service"
    ];
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."opendashboards-db" = {
    image = "postgres:17-alpine@sha256:f9cf3e1f0066f0eb0c48707d864f0ac5941e9ff454a072077d97a4d278d07d73";
    environment = {
      "POSTGRES_DB" = "opendashboards";
      "POSTGRES_PASSWORD_FILE" = "/run/secrets/database-password";
      "POSTGRES_USER" = "opendashboards";
    };
    volumes = [
      "/var/lib/opendashboards/state/database-password:/run/secrets/database-password:ro"
      "opendashboards-postgres:/var/lib/postgresql/data:rw"
    ];
    dependsOn = [
      "opendashboards-init"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=pg_isready -h 127.0.0.1 -U opendashboards -d opendashboards"
      "--health-interval=5s"
      "--health-retries=12"
      "--health-timeout=5s"
      "--network-alias=opendashboards-db"
      "--network=opendashboards-db"
      "--security-opt=no-new-privileges:true"
    ];
  };
  systemd.services."docker-opendashboards-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-opendashboards-db.service"
      "docker-volume-opendashboards-postgres.service"
    ];
    requires = [
      "docker-network-opendashboards-db.service"
      "docker-volume-opendashboards-postgres.service"
    ];
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."opendashboards-init" = {
    image = "ghcr.io/junr03/electricpeak-services/opendashboards@sha256:0a5d623b516c397687d2b3bc6a3ff11687060ce23036098f87d3345f9b2b7940";
    volumes = [
      "/var/lib/opendashboards/state:/data:rw"
    ];
    cmd = [ "init" ];
    user = "1000:100";
    log-driver = "journald";
    extraOptions = [
      "--cap-drop=ALL"
      "--network=none"
      "--security-opt=no-new-privileges:true"
    ];
  };
  systemd.services."docker-opendashboards-init" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "no";
    };
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."rawbackup" = {
    image = "ghcr.io/junr03/electricpeak-services/rawbackup@sha256:0e4d58e203a01ab80603730ae6d5174890269a8f0386ca1e58d9d7dfa244db38";
    volumes = [
      "/var/lib/rawbackup:/data:ro"
      "/var/lib/rawbackup/reconcile:/reconcile:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=rawbackup"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-rawbackup" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."status" = {
    image = "ghcr.io/junr03/electricpeak-services/status@sha256:af3727f99b8370fe47386c4f7657c868e1d3e3dca38ec3c5c6caf3ad8d5bb1cf";
    volumes = [
      "/var/lib/electricpeak-status:/srv/status-data:ro"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-drop=ALL"
      "--network-alias=status"
      "--network=electricpeak"
      "--security-opt=no-new-privileges:true"
    ];
  };
  systemd.services."docker-status" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."substack-digest" = {
    image = "ghcr.io/junr03/electricpeak-services/substack-digest@sha256:61936b3d68d7e41e2464248d0366d59fe4272d1d87085d94f26004d1e1d5f4c9";
    environment = {
      "RMAPI_CONFIG_DIR" = "/data/rmapi";
    };
    volumes = [
      "/run/onepassword-secrets/substackDigestCookies:/run/secrets/substack-cookies.json:ro"
      "/run/onepassword-secrets/substackDigestRemarkableToken:/run/secrets/remarkable-token:ro"
      "/var/lib/electricpeak/appdata/substack-digest:/config:ro"
      "/var/lib/substack-digest:/data:rw"
    ];
    labels = {
      "compose2nix.settings.autoStart" = "false";
    };
    user = "1000:100";
    log-driver = "journald";
    autoStart = false;
    extraOptions = [
      "--cap-drop=ALL"
      "--network-alias=substack-digest"
      "--network=electricpeak"
      "--security-opt=no-new-privileges:true"
      "--shm-size=268435456"
    ];
  };
  systemd.services."docker-substack-digest" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "no";
    };
  };

  # Networks
  systemd.services."docker-network-opendashboards-db" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f opendashboards-db";
    };
    script = ''
      docker network inspect opendashboards-db || docker network create opendashboards-db --internal
    '';
    partOf = [ "docker-compose-electricpeak-root.target" ];
    wantedBy = [ "docker-compose-electricpeak-root.target" ];
  };

  # Volumes
  systemd.services."docker-volume-opendashboards-postgres" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect opendashboards-postgres || docker volume create opendashboards-postgres
    '';
    partOf = [ "docker-compose-electricpeak-root.target" ];
    wantedBy = [ "docker-compose-electricpeak-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-electricpeak-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
