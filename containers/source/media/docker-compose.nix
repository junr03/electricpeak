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
  virtualisation.oci-containers.containers."audiobookshelf" = {
    image = "ghcr.io/advplyr/audiobookshelf:latest";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/mnt/data/library/audiobooks:/audiobooks:rw"
      "/var/lib/electricpeak/appdata/audiobookshelf/config:/config:rw"
      "/var/lib/electricpeak/appdata/audiobookshelf/metadata:/metadata:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=audiobookshelf"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-audiobookshelf" = {
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
  virtualisation.oci-containers.containers."calibre" = {
    image = "lscr.io/linuxserver/calibre";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
      "WEBUI_MODE" = "desktop";
    };
    volumes = [
      "/mnt/data/library/books:/library:rw"
      "/mnt/data/torrents:/downloads:rw"
      "/var/lib/electricpeak/appdata/calibre/autoadd:/autoadd:rw"
      "/var/lib/electricpeak/appdata/calibre/config:/config:rw"
      "/var/lib/electricpeak/appdata/calibre/dedrm/:/dedrm:rw"
      "/var/lib/electricpeak/appdata/calibre/plugins:/plugins:rw"
      "/var/lib/electricpeak/appdata/calibre/uploads:/uploads:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=calibre"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-calibre" = {
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
  virtualisation.oci-containers.containers."calibreweb" = {
    image = "lscr.io/linuxserver/calibre-web";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/mnt/data/library/books:/library:rw"
      "/var/lib/electricpeak/appdata/calibreweb:/config:rw"
    ];
    dependsOn = [
      "calibre"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=calibre-web"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-calibreweb" = {
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
  virtualisation.oci-containers.containers."homarr" = {
    image = "ghcr.io/homarr-labs/homarr:latest";
    environment = {
      "DOCKER_SOCKET_PATHS" = "/var/run/docker.sock";
      "SECRET_ENCRYPTION_KEY_FILE" = "/appdata/secret-encryption-key";
      "TZ" = "America/Los_Angeles";
    };
    volumes = [
      "/run/onepassword-secrets/homarrSecretEncryptionKey:/appdata/secret-encryption-key:ro"
      "/var/lib/electricpeak/appdata/homarr:/appdata:rw"
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=homarr"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-homarr" = {
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
  virtualisation.oci-containers.containers."jellyfin" = {
    image = "jellyfin/jellyfin";
    volumes = [
      "/mnt/data/library/movies:/movies:rw"
      "/mnt/data/library/tv:/tv:rw"
      "/var/lib/electricpeak/appdata/plex:/config:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--device=/dev/dri/renderD128:/dev/dri/renderD128:rwm"
      "--network-alias=jellyfin"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-jellyfin" = {
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
  virtualisation.oci-containers.containers."lazylibrarian" = {
    image = "lscr.io/linuxserver/lazylibrarian:latest";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/mnt/data:/data:rw"
      "/mnt/data/library/books:/books:rw"
      "/var/lib/electricpeak/appdata/calibre/autoadd:/calibre-autoadd:rw"
      "/var/lib/electricpeak/appdata/lazylibrarian:/config:rw"
    ];
    dependsOn = [
      "lazylibrarian-init"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=lazylibrarian"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-lazylibrarian" = {
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
  virtualisation.oci-containers.containers."lazylibrarian-init" = {
    image = "alpine:3.20";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
    };
    volumes = [
      "/etc/electricpeak/lazylibrarian-init.sh:/usr/local/bin/lazylibrarian-init:ro"
      "/run/onepassword-secrets/lazylibrarianGoodreadsRssUrl:/run/secrets/lazylibrarian-goodreads-rss-url:ro"
      "/run/onepassword-secrets/lazylibrarianQbittorrentPass:/run/secrets/lazylibrarian-qbittorrent-pass:ro"
      "/run/onepassword-secrets/lazylibrarianQbittorrentUser:/run/secrets/lazylibrarian-qbittorrent-user:ro"
      "/run/onepassword-secrets/lazylibrarianTorznabApiKey:/run/secrets/lazylibrarian-torznab-api-key:ro"
      "/run/onepassword-secrets/lazylibrarianTorznabUrl:/run/secrets/lazylibrarian-torznab-url:ro"
      "/var/lib/electricpeak/appdata/lazylibrarian:/config:rw"
    ];
    cmd = [ "/bin/sh" "/usr/local/bin/lazylibrarian-init" ];
    log-driver = "journald";
    extraOptions = [
      "--network=none"
    ];
  };
  systemd.services."docker-lazylibrarian-init" = {
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
  virtualisation.oci-containers.containers."radarr" = {
    image = "ghcr.io/hotio/radarr:latest";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/mnt/data:/data:rw"
      "/var/lib/electricpeak/appdata/radarr:/config:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=radarr"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-radarr" = {
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
  virtualisation.oci-containers.containers."sonarr" = {
    image = "ghcr.io/hotio/sonarr:release";
    environment = {
      "PGID" = "100";
      "PUID" = "1000";
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/mnt/data:/data:rw"
      "/var/lib/electricpeak/appdata/sonarr:/config:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sonarr"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-sonarr" = {
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
