{ config, lib, pkgs, ... }:
let
  cfg = config.services.opendashboards;
  units = [
    "docker-opendashboards" "docker-opendashboards-db" "docker-opendashboards-init"
    "docker-network-opendashboards-db" "docker-volume-opendashboards-postgres"
  ];
in
{
  options.services.opendashboards = {
    enable = lib.mkEnableOption "OpenDashboards (requires a provisioned Thesys API key and private-destinations JSON attachment)";
    origin = lib.mkOption {
      type = lib.types.strMatching "https://[^/]+";
      default = "https://dashboards.example.invalid";
      description = "External HTTPS origin; set the production hostname in the private configuration.";
    };
  };

  config = {
    # Public evaluation never tries to retrieve credentials or start the app.
    systemd.services = lib.mkMerge [
      (lib.genAttrs units (_: { enable = cfg.enable; }))
      {
        docker-opendashboards-init.serviceConfig = {
          Type = lib.mkForce "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = lib.mkForce "5min";
        };
        # compose2nix translates dependency ordering but omits service_healthy.
        # Dependents start only after this post-start readiness check completes.
        docker-opendashboards-db.postStart = lib.mkIf cfg.enable ''
          for attempt in $(${pkgs.coreutils}/bin/seq 1 90); do
            if [ "$(${pkgs.docker}/bin/docker inspect --format '{{.State.Health.Status}}' opendashboards-db)" = healthy ]; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          echo 'OpenDashboards database did not become healthy' >&2
          exit 1
        '';
      }
    ];
    systemd.tmpfiles.rules = lib.optionals cfg.enable [
      "d /var/lib/opendashboards 0700 1000 100 - -"
      "d /var/lib/opendashboards/state 0700 1000 100 - -"
    ];
    # compose2nix 0.3.2 omits read_only/tmpfs/init. Enforce the image's runtime
    # contract here as well as documenting it in the source Compose definition.
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
    };
  };
}
