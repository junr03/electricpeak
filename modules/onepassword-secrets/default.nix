{ config, lib, pkgs, ... }:

let
  secretDirectory = "/run/onepassword-secrets";
  tokenCredential = "/var/lib/opnix/service-account-token.cred";
  secretPaths = config.services.onepassword-secrets.secretPaths;
  certificateNames = lib.attrNames config.security.acme.certs;
  hasCertificates = certificateNames != [ ];
  acmeConsumerServices = lib.concatMap (name: [
    "acme-${name}"
    "acme-order-renew-${name}"
  ]) (lib.attrNames config.security.acme.certs);
  tailscaledDependency = lib.optional config.services.tailscale.enable "tailscaled.service";
  consumerServices = acmeConsumerServices ++ [
    "docker-contact-sync"
    "docker-envoy"
    "docker-foodlog-sync"
    "foodlog-sync-ghcr-login"
    "docker-gluetun"
    "docker-homarr"
    "docker-homeassistant"
    "docker-lazylibrarian"
    "docker-lazylibrarian-init"
    "docker-mousehole"
    "firewall"
    "github-actions-authorized-keys"
    "photo-internxt-config"
    "sshd-authorized-keys"
    "zerotier-network-join"
  ];
  bootstrap = pkgs.writeShellApplication {
    name = "onepassword-secrets-bootstrap";
    runtimeInputs = with pkgs; [ coreutils systemd ];
    text = builtins.readFile ./bootstrap.sh;
  };
  ghcrLogin = pkgs.writeShellApplication {
    name = "foodlog-sync-ghcr-login";
    runtimeInputs = with pkgs; [ coreutils docker ];
    text = ''
      install -d -m 0700 /root/.docker
      username="$(cat ${secretPaths.foodlogGhcrUsername})"
      token="$(cat ${secretPaths.foodlogGhcrToken})"
      printf '%s' "$token" | docker login ghcr.io --username "$username" --password-stdin >/dev/null
      unset username token
    '';
  };
  configEditor = pkgs.writeShellApplication {
    name = "onepassword-config-edit";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      usage() {
        cat >&2 <<'EOF'
      Usage: onepassword-config-edit CONFIG

      CONFIG is one of:
        deployment
        envoy
        homeassistant-automations
        homeassistant-templates
        homarr
        junr03-ssh
        github-actions-ssh
        zerotier-cidr
        zerotier-id
      EOF
        exit 2
      }

      [[ $# -eq 1 ]] || usage

      case "$1" in
        deployment)
          resource="deployment.nix"
          storage_kind="file"
          suffix=".nix"
          ;;
        envoy)
          resource="envoy-config.yaml"
          storage_kind="file"
          suffix=".yaml"
          ;;
        homeassistant-automations)
          resource="home-assistant-automations.yaml"
          storage_kind="file"
          suffix=".yaml"
          ;;
        homeassistant-templates)
          resource="home-assistant-templates.yaml"
          storage_kind="file"
          suffix=".yaml"
          ;;
        homarr)
          resource="homarr-environment.env"
          storage_kind="file"
          suffix=".env"
          ;;
        junr03-ssh)
          resource="junr03-authorized-keys.txt"
          storage_kind="file"
          suffix=".txt"
          ;;
        github-actions-ssh)
          resource="github-actions-authorized-keys.txt"
          storage_kind="file"
          suffix=".txt"
          ;;
        zerotier-cidr)
          resource="zerotier-network-cidr"
          storage_kind="field"
          suffix=".txt"
          ;;
        zerotier-id)
          resource="zerotier-network-id"
          storage_kind="field"
          suffix=".txt"
          ;;
        *)
          echo "Unknown configuration: $1" >&2
          usage
          ;;
      esac

      vault="electricpeak"
      item="nixos"
      reference="op://$vault/$item/$resource"
      temporary_directory="$(mktemp -d "''${TMPDIR:-/tmp}/onepassword-config.XXXXXX")"
      temporary_file="$temporary_directory/$resource"
      original_file="$temporary_directory/original$suffix"
      trap 'rm -rf -- "$temporary_directory"' EXIT

      op read "$reference" > "$temporary_file"
      chmod 0600 "$temporary_file"
      cp "$temporary_file" "$original_file"

      editor="''${VISUAL:-''${EDITOR:-vi}}"
      read -r -a editor_command <<< "$editor"
      if [[ ''${#editor_command[@]} -eq 0 ]]; then
        echo "VISUAL and EDITOR are empty; set one before retrying." >&2
        exit 1
      fi

      "''${editor_command[@]}" "$temporary_file"

      if cmp -s "$original_file" "$temporary_file"; then
        echo "No changes made to $resource."
        exit 0
      fi

      if [[ "$storage_kind" == file ]]; then
        attachment_resource="''${resource//./\\\.}"
        op item edit "$item" --vault "$vault" "''${attachment_resource}[file]=$temporary_file" >/dev/null
        echo "Updated 1Password attachment: $resource"
      else
        op item edit "$item" --vault "$vault" "$resource=@$temporary_file" >/dev/null
        echo "Updated concealed 1Password field: $resource"
      fi
      echo "Refresh runtime consumers with: sudo systemctl restart opnix-secrets.service"

      if [[ "$resource" == "deployment.nix" ]]; then
        echo "Materialize deployment.nix as /etc/nixos/deployment.nix before running NixOS evaluation."
      fi
    '';
  };
  verifySecrets = pkgs.writeShellScript "verify-onepassword-secrets"
    (builtins.replaceStrings
      [ "@SECRET_PATHS@" ]
      [ (lib.escapeShellArgs (builtins.attrValues secretPaths)) ]
      (builtins.readFile ./verify-secrets.sh));
  acmeCertificateHealthCheck = pkgs.writeShellScriptBin "acme-electricpeak-health-check" ''
    set -eu

    if [ "$#" -ne 0 ]; then
      echo "This command does not accept arguments." >&2
      exit 2
    fi

    ${lib.concatMapStringsSep "\n" (name: ''
      test -s ${lib.escapeShellArg "/var/lib/acme/${name}/fullchain.pem"}
      test -s ${lib.escapeShellArg "/var/lib/acme/${name}/key.pem"}
    '') certificateNames}
  '';
in
{
  services.onepassword-secrets = {
    enable = true;
    # The plaintext token exists only in this unit's private /run directory.
    # modules/onepassword-secrets/bootstrap.sh creates the encrypted source.
    tokenFile = "/run/opnix/token";
    outputDir = secretDirectory;

    systemdIntegration = {
      services = consumerServices;
      restartOnChange = true;
      errorHandling = {
        continueOnError = false;
        maxRetries = 3;
      };
    };

    secrets = {
      cloudflareDnsEnvironment = {
        reference = "op://electricpeak/nixos/cloudflare-dns-environment.env";
        kind = "file";
        services = acmeConsumerServices;
      };
      envoyConfig = {
        reference = "op://electricpeak/nixos/envoy-config.yaml";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "docker-envoy" ];
      };
      gluetunEnvironment = {
        reference = "op://electricpeak/nixos/gluetun-environment.txt";
        kind = "file";
        services = [ "docker-gluetun" ];
      };
      githubActionsAuthorizedKeys = {
        reference = "op://electricpeak/nixos/github-actions-authorized-keys.txt";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "github-actions-authorized-keys" ];
      };
      homeAssistantAutomations = {
        reference = "op://electricpeak/nixos/home-assistant-automations.yaml";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "docker-homeassistant" ];
      };
      homeAssistantTemplates = {
        reference = "op://electricpeak/nixos/home-assistant-templates.yaml";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "docker-homeassistant" ];
      };
      homarrSecretEncryptionKey = {
        reference = "op://electricpeak/nixos/homarr-secret-encryption-key";
        owner = "junr03";
        group = "docker";
        services = [ "docker-homarr" ];
      };
      homarrEnvironment = {
        reference = "op://electricpeak/nixos/homarr-environment.env";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "docker-homarr" ];
      };
      junr03AuthorizedKeys = {
        reference = "op://electricpeak/nixos/junr03-authorized-keys.txt";
        kind = "file";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "sshd-authorized-keys" ];
      };
      internxtEmail = {
        reference = "op://electricpeak/nixos/internxt-email";
        services = [ "photo-internxt-config" ];
      };
      internxtPassword = {
        reference = "op://electricpeak/nixos/internxt-password";
        services = [ "photo-internxt-config" ];
      };
      lazylibrarianQbittorrentUser = {
        reference = "op://electricpeak/nixos/lazylibrarian-qbittorrent-user";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [
          "docker-lazylibrarian"
          "docker-lazylibrarian-init"
        ];
      };
      lazylibrarianQbittorrentPass = {
        reference = "op://electricpeak/nixos/lazylibrarian-qbittorrent-pass";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [
          "docker-lazylibrarian"
          "docker-lazylibrarian-init"
        ];
      };
      lazylibrarianTorznabUrl = {
        reference = "op://electricpeak/nixos/lazylibrarian-torznab-url";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [
          "docker-lazylibrarian"
          "docker-lazylibrarian-init"
        ];
      };
      lazylibrarianTorznabApiKey = {
        reference = "op://electricpeak/nixos/lazylibrarian-torznab-api-key";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [
          "docker-lazylibrarian"
          "docker-lazylibrarian-init"
        ];
      };
      lazylibrarianGoodreadsRssUrl = {
        reference = "op://electricpeak/nixos/lazylibrarian-goodreads-rss-url";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [
          "docker-lazylibrarian"
          "docker-lazylibrarian-init"
        ];
      };
      zeroTierNetworkCidr = {
        reference = "op://electricpeak/nixos/zerotier-network-cidr";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "firewall" ];
      };
      zeroTierNetworkId = {
        reference = "op://electricpeak/nixos/zerotier-network-id";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "zerotier-network-join" ];
      };
      vdirsyncerGoogleClientId = {
        reference = "op://electricpeak/nixos/vdirsyncer-google-client-id";
        services = [ "docker-contact-sync" ];
      };
      vdirsyncerGoogleClientSecret = {
        reference = "op://electricpeak/nixos/vdirsyncer-google-client-secret";
        services = [ "docker-contact-sync" ];
      };
      vdirsyncerIcloudUsername = {
        reference = "op://electricpeak/nixos/vdirsyncer-icloud-username";
        services = [ "docker-contact-sync" ];
      };
      vdirsyncerIcloudAppPassword = {
        reference = "op://electricpeak/nixos/vdirsyncer-icloud-app-password";
        services = [ "docker-contact-sync" ];
      };
      foodlogGhcrUsername = {
        reference = "op://electricpeak/nixos/foodlog-ghcr-username";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "foodlog-sync-ghcr-login" ];
      };
      foodlogGhcrToken = {
        reference = "op://electricpeak/nixos/foodlog-ghcr-token";
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "foodlog-sync-ghcr-login" ];
      };
      foodlogGoogleDriveToken = {
        reference = "op://electricpeak/nixos/foodlog-google-drive-token.json";
        kind = "file";
        owner = "junr03";
        group = "users";
        mode = "0400";
        services = [ "docker-foodlog-sync" ];
      };
      foodlogGoogleDriveFolderId = {
        reference = "op://electricpeak/nixos/foodlog-google-drive-folder-id";
        owner = "junr03";
        group = "users";
        mode = "0400";
        services = [ "docker-foodlog-sync" ];
      };
      foodlogCronometerUsername = {
        reference = "op://electricpeak/nixos/foodlog-cronometer-username";
        owner = "junr03";
        group = "users";
        mode = "0400";
        services = [ "docker-foodlog-sync" ];
      };
      foodlogCronometerPassword = {
        reference = "op://electricpeak/nixos/foodlog-cronometer-password";
        owner = "junr03";
        group = "users";
        mode = "0400";
        services = [ "docker-foodlog-sync" ];
      };
    };
  };

  virtualisation.oci-containers.containers = {
    homarr.environmentFiles = [ secretPaths.homarrEnvironment ];
  };

  # Docker creates a missing bind-mount source as root. Pre-create the
  # foodlog state directory for the UID and GID configured in Compose so the
  # service can persist its SQLite ledger, raw imports, and session data.
  systemd.tmpfiles.rules = [
    "d /var/lib/electricpeak/appdata/foodlog-sync 0750 1000 100 - -"
  ];

  environment.systemPackages = [ bootstrap configEditor ghcrLogin pkgs._1password-cli ]
    ++ lib.optional hasCertificates acmeCertificateHealthCheck;

  # Let the deploy account validate protected ACME outputs through a fixed,
  # read-only root helper without granting it general systemd or filesystem
  # access.
  security.sudo.extraRules = lib.optional hasCertificates {
    users = [ "github-actions" ];
    commands = [
      {
        command = "/run/current-system/sw/bin/acme-electricpeak-health-check";
        options = [ "NOPASSWD" ];
      }
    ];
  };

  systemd.services = lib.mkMerge [
    {
      "docker-foodlog-sync" = {
        after = [ "foodlog-sync-ghcr-login.service" ];
        requires = [ "foodlog-sync-ghcr-login.service" ];
        unitConfig.RequiresMountsFor = [ "/var/lib/electricpeak/appdata/foodlog-sync" ];
      };
      "foodlog-sync-ghcr-login" = {
        after = [ "docker.service" "network-online.target" ];
        requires = [ "docker.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartMode = "direct";
          RestartSec = "30s";
          ExecStart = "${ghcrLogin}/bin/foodlog-sync-ghcr-login";
        };
      };
      "docker-lazylibrarian-init" = {
        unitConfig = {
          # Bound retries so a permanent secret or configuration error becomes
          # a visible failed unit instead of an endless restart loop.
          StartLimitIntervalSec = "15min";
          StartLimitBurst = 30;
          RequiresMountsFor = [ "/var/lib/electricpeak/appdata/lazylibrarian" ];
        };
        serviceConfig = {
          # This oneshot consumes files materialized by opnix-secrets and can
          # race the first secret refresh after a deployment. Retry transient
          # failures while preserving the failed state between attempts so
          # dependent services cannot run against incomplete configuration.
          Restart = lib.mkForce "on-failure";
          RestartMode = lib.mkForce "normal";
          RestartSec = lib.mkForce "30s";
        };
      };
      opnix-secrets = {
        preStart = builtins.readFile ./install-service-account-token.sh;
        serviceConfig = {
          RuntimeDirectory = "opnix";
          RuntimeDirectoryMode = "0750";
          LoadCredentialEncrypted = [
            "service-account-token:${tokenCredential}"
          ];
          # Network-online does not guarantee that the resolver used by
          # Tailscale is ready. Retry transient boot-time DNS failures soon
          # enough for consumers to recover without manual intervention. Keep
          # the service activating across retries so a transient provider
          # failure does not fail nixos-rebuild or dependent services.
          RestartMode = "direct";
          RestartSec = lib.mkForce "30s";
          ExecStartPost = verifySecrets;
        };
        after = lib.mkAfter tailscaledDependency;
        wants = lib.mkAfter tailscaledDependency;
      };
    }
    (lib.genAttrs consumerServices (_: {
      after = [ "opnix-secrets.service" ];
      requires = [ "opnix-secrets.service" ];
    }))
  ];
}
