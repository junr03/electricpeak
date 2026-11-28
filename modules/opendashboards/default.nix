{ config, lib, ... }:
let
  cfg = config.services.opendashboards;
  units = [
    "docker-opendashboards"
    "docker-opendashboards-db"
    "docker-opendashboards-init"
    "docker-opendashboards-ollama"
    "docker-network-opendashboards-db"
    "docker-network-opendashboards-inference"
    "docker-volume-opendashboards-postgres"
    "docker-volume-opendashboards-models"
  ];
in
{
  options.services.opendashboards = {
    enable = lib.mkEnableOption "the containerized OpenDashboards stack";
    origin = lib.mkOption {
      type = lib.types.strMatching "https://[^/]+";
      default = "https://dashboards.example.invalid";
      description = "External HTTPS origin; set the production hostname in the private configuration.";
    };
  };

  config = {
    # Host integration only. Runtime settings and readiness live in Compose/images.
    systemd.services = lib.genAttrs units (_: {
      enable = cfg.enable;
    });
    systemd.tmpfiles.rules = lib.optionals cfg.enable [
      "d /var/lib/opendashboards 0700 1000 100 - -"
      "d /var/lib/opendashboards/state 0700 1000 100 - -"
    ];
    # compose2nix 0.3.2 omits read_only/tmpfs/init. Preserve those Compose flags
    # when the generated containers are deployed through NixOS.
    virtualisation.oci-containers.containers = lib.mkIf cfg.enable {
      opendashboards = {
        environment.APP_ORIGIN = lib.mkForce cfg.origin;
        extraOptions = [
          "--init"
          "--read-only"
          "--tmpfs=/tmp:mode=1777"
          "--tmpfs=/app/.next/cache:uid=1000,gid=100"
        ];
      };
      opendashboards-init.extraOptions = [ "--read-only" ];
      opendashboards-ollama.extraOptions = [
        "--read-only"
        "--tmpfs=/tmp:mode=1777"
      ];
    };
  };
}
