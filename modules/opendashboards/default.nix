{ config, lib, pkgs, ... }:
let
  cfg = config.services.opendashboards;
  localInference = cfg.enable && cfg.inference.ollama.enable;
  units = [
    "docker-opendashboards" "docker-opendashboards-db" "docker-opendashboards-init"
    "docker-network-opendashboards-db" "docker-volume-opendashboards-postgres"
    "docker-network-opendashboards-inference"
  ];
in
{
  options.services.opendashboards = {
    enable = lib.mkEnableOption "independent OpenDashboards with an operator-owned inference endpoint";
    origin = lib.mkOption {
      type = lib.types.strMatching "https://[^/]+";
      default = "https://dashboards.example.invalid";
      description = "External HTTPS origin; set the production hostname in the private configuration.";
    };
    inference = {
      baseUrl = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "https?://[^[:space:]]+");
        default = if cfg.inference.ollama.enable then "http://opendashboards-ollama:11434/v1" else null;
        description = "OpenAI-compatible API base URL reachable from the container; configure in the private repository.";
      };
      model = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Actual model ID served by the inference endpoint.";
      };
      dashboardModel = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Optional dashboard model on the same endpoint; defaults to model.";
      };
      ollama = {
        enable = lib.mkEnableOption "a private Ollama container and model provisioning";
        contextLength = lib.mkOption {
          type = lib.types.ints.positive;
          default = 32768;
          description = "Ollama context window; account for model and KV cache memory on this host.";
        };
      };
    };
  };

  config = {
    assertions = lib.optionals cfg.enable [{
      assertion = cfg.inference.baseUrl != null && cfg.inference.model != null;
      message = "Enabled OpenDashboards requires services.opendashboards.inference.baseUrl and model.";
    }];
    # Public evaluation never tries to retrieve credentials or start the app.
    systemd.services = lib.mkMerge [
      (lib.genAttrs units (_: { enable = cfg.enable; }))
      (lib.genAttrs [ "docker-opendashboards-ollama" "docker-volume-opendashboards-models" ] (_: { enable = localInference; }))
      {
        docker-opendashboards = lib.mkIf localInference {
          after = [ "opendashboards-models.service" ];
          requires = [ "opendashboards-models.service" ];
        };
        docker-opendashboards-ollama.postStart = lib.mkIf localInference ''
          for attempt in $(${pkgs.coreutils}/bin/seq 1 90); do
            if ${pkgs.docker}/bin/docker exec opendashboards-ollama ollama list >/dev/null 2>&1; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          echo 'OpenDashboards Ollama did not become ready' >&2
          exit 1
        '';
        opendashboards-models = lib.mkIf localInference {
          description = "Provision configured OpenDashboards inference models";
          after = [ "docker-opendashboards-ollama.service" ];
          requires = [ "docker-opendashboards-ollama.service" ];
          partOf = [ "docker-opendashboards-ollama.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "60min";
          };
          script = lib.concatMapStringsSep "\n" (model:
            ''
              if ! ${pkgs.docker}/bin/docker exec opendashboards-ollama ollama show ${lib.escapeShellArg model} >/dev/null 2>&1; then
                ${pkgs.docker}/bin/docker exec opendashboards-ollama ollama pull ${lib.escapeShellArg model}
              fi
            ''
          ) (lib.unique ([ cfg.inference.model ] ++ lib.optional (cfg.inference.dashboardModel != null) cfg.inference.dashboardModel));
        };
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
        environment = {
          APP_ORIGIN = lib.mkForce cfg.origin;
          LLM_BASE_URL = cfg.inference.baseUrl;
          LLM_MODEL = cfg.inference.model;
          LLM_DASHBOARD_MODEL = if cfg.inference.dashboardModel == null then cfg.inference.model else cfg.inference.dashboardModel;
        };
        extraOptions = [
          "--init"
          "--read-only"
          "--tmpfs=/tmp:mode=1777"
          "--tmpfs=/app/.next/cache:uid=1000,gid=100"
        ];
      };
      opendashboards-init.extraOptions = [ "--read-only" ];
      opendashboards-ollama = lib.mkIf cfg.inference.ollama.enable {
        environment.OLLAMA_CONTEXT_LENGTH = lib.mkForce (toString cfg.inference.ollama.contextLength);
        extraOptions = [ "--read-only" "--tmpfs=/tmp:mode=1777" ];
      };
    };
  };
}
