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
  virtualisation.oci-containers.containers."rawbackup" = {
    image = "python:3.13-alpine";
    volumes = [
      "/etc/nixos/containers/source/utilities/rawbackup/app:/app:ro"
      "/var/lib/rawbackup:/data:ro"
      "/var/lib/rawbackup/reconcile:/reconcile:rw"
    ];
    cmd = [ "python" "/app/server.py" ];
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
  virtualisation.oci-containers.containers."substack-digest" = {
    image = "electricpeak-substack-digest:local";
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
  virtualisation.oci-containers.containers."watchkeeper" = {
    image = "ghcr.io/junr03/project-watchkeeper@sha256:5008834cc10afaf6f795baf7892414627b9fa61739545dee20d3fecc69a5c6cd";
    environment = {
      "WATCHKEEPER_ALLOWED_ORIGINS" = "http://127.0.0.1:8765";
      "WATCHKEEPER_BIND_HOST" = "0.0.0.0";
      "WATCHKEEPER_DATABASE" = "/var/lib/watchkeeper/watchkeeper.sqlite3";
      "WATCHKEEPER_EMAIL_DIR" = "/var/lib/watchkeeper/email";
      "WATCHKEEPER_INTAKE_TOKEN_FILE" = "/run/secrets/intake-token";
      "WATCHKEEPER_MAIL_SENDER" = "watchkeeper-smoke@example.invalid";
      "WATCHKEEPER_MAIL_TRANSPORT" = "file";
      "WATCHKEEPER_PORT" = "8765";
      "WATCHKEEPER_PRIVACY_JOURNAL" = "/var/lib/watchkeeper/privacy.jsonl";
      "WATCHKEEPER_PROXY_MODE" = "ignore";
      "WATCHKEEPER_PUBLIC_BASE_URL" = "http://127.0.0.1:8765";
      "WATCHKEEPER_RECIPIENT" = "smoke-recipient@example.invalid";
      "WATCHKEEPER_REVIEWER_TOKEN_FILE" = "/run/secrets/reviewer-token";
      "WATCHKEEPER_UI_PASSWORD_FILE" = "/run/secrets/ui-password";
      "WATCHKEEPER_UI_USERNAME_FILE" = "/run/secrets/ui-username";
    };
    volumes = [
      "/var/lib/electricpeak/appdata/watchkeeper/secrets/intake-token:/run/secrets/intake-token:ro"
      "/var/lib/electricpeak/appdata/watchkeeper/secrets/reviewer-token:/run/secrets/reviewer-token:ro"
      "/var/lib/electricpeak/appdata/watchkeeper/secrets/ui-password:/run/secrets/ui-password:ro"
      "/var/lib/electricpeak/appdata/watchkeeper/secrets/ui-username:/run/secrets/ui-username:ro"
      "/var/lib/electricpeak/appdata/watchkeeper/state:/var/lib/watchkeeper:rw"
    ];
    ports = [
      "127.0.0.1:8765:8765/tcp"
    ];
    labels = {
      "compose2nix.settings.autoStart" = "false";
      "compose2nix.systemd.service.ExecStop" = "/run/current-system/sw/bin/docker stop --time 180 watchkeeper";
      "compose2nix.systemd.service.TimeoutStopSec" = "210";
    };
    user = "1000:2000";
    log-driver = "journald";
    autoStart = false;
    extraOptions = [
      "--cap-drop=ALL"
      "--health-cmd=python -c 'import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8765/readyz\", timeout=2)'"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-start-period=10s"
      "--health-timeout=3s"
      "--network-alias=watchkeeper"
      "--network=electricpeak"
      "--security-opt=no-new-privileges:true"
    ];
  };
  systemd.services."docker-watchkeeper" = {
    serviceConfig = {
      ExecStop = lib.mkOverride 90 "/run/current-system/sw/bin/docker stop --time 180 watchkeeper";
      Restart = lib.mkOverride 90 "no";
      TimeoutStopSec = lib.mkOverride 90 210;
    };
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
