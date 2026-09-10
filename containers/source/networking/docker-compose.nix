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
  virtualisation.oci-containers.containers."adguardhome" = {
    image = "adguard/adguardhome:latest";
    environment = {
      "TZ" = "America/Los_Angeles";
      "UMASK" = "002";
    };
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/var/lib/electricpeak/appdata/adguardhome/config:/opt/adguardhome/conf:rw"
      "/var/lib/electricpeak/appdata/adguardhome/work:/opt/adguardhome/work:rw"
    ];
    ports = [
      "5080:80/tcp"
      "5443:443/tcp"
      "5443:443/udp"
      "853:853/tcp"
      "853:853/udp"
      "53:53/tcp"
      "53:53/udp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=adguardhome"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-adguardhome" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-electricpeak.service"
    ];
    requires = [
      "docker-network-electricpeak.service"
    ];
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."envoy" = {
    image = "envoyproxy/envoy:v1.35.3";
    environment = {
      "ENVOY_UID" = "0";
    };
    volumes = [
      "/run/onepassword-secrets/envoyConfig:/etc/envoy/envoy.yaml:ro"
      "/var/lib/acme/example.invalid:/etc/ssl/electricpeak:ro"
    ];
    ports = [
      "443:8081/tcp"
      "8001:8001/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=envoy"
      "--network=electricpeak"
    ];
  };
  systemd.services."docker-envoy" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-electricpeak.service"
    ];
    requires = [
      "docker-network-electricpeak.service"
    ];
    partOf = [
      "docker-compose-electricpeak-root.target"
    ];
    wantedBy = [
      "docker-compose-electricpeak-root.target"
    ];
  };
  virtualisation.oci-containers.containers."homeassistant" = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    volumes = [
      "/etc/localtime:/etc/localtime:ro"
      "/run/dbus:/run/dbus:ro"
      "/run/onepassword-secrets/homeAssistantAutomations:/config/automations/example.yaml:ro"
      "/run/onepassword-secrets/homeAssistantTemplates:/config/packages/templates.yaml:ro"
      "/var/lib/electricpeak/appdata/homeassistant/config:/config:rw"
    ];
    ports = [
      "8123:8123/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network=host"
      "--privileged"
    ];
  };
  systemd.services."docker-homeassistant" = {
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
  virtualisation.oci-containers.containers."matter-server" = {
    image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
    environment = {
      "LOG_LEVEL" = "debug";
    };
    volumes = [
      "/run/dbus:/run/dbus:ro"
      "/var/lib/electricpeak/appdata/matter-server/data:/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network=host"
      "--security-opt=apparmor:unconfined"
    ];
  };
  systemd.services."docker-matter-server" = {
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

  # Networks
  systemd.services."docker-network-electricpeak" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f electricpeak";
    };
    script = ''
      docker network inspect electricpeak || docker network create electricpeak --driver=bridge --subnet=2001:db8:1::/64 --ipv6
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
