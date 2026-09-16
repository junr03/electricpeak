# Public NixOS entry point.
#
# Deployment-specific host, network, filesystem, service, and container
# configuration is kept in the private-config submodule. Public module
# evaluation retains a generic fallback, while the production flake requires
# the private configuration explicitly.

{
  config,
  gallatinRunners,
  self,
  lib,
  pkgs,
  requirePrivateSystemConfiguration ? false,
  ...
}:

let
  privateConfigCandidates = [
    "${toString ./.}/private-config"
    "/etc/nixos/private-config"
  ];
  privateConfigRoot = lib.findFirst builtins.pathExists null privateConfigCandidates;
  privateSystemConfiguration =
    if privateConfigRoot != null && builtins.pathExists "${privateConfigRoot}/configuration.nix" then
      "${privateConfigRoot}/configuration.nix"
    else
      null;
  hasPrivateSystemConfiguration = privateSystemConfiguration != null;
  usePrivateSystemConfiguration =
    requirePrivateSystemConfiguration && hasPrivateSystemConfiguration;
in
{
  imports = [
    ./modules/onepassword-secrets/default.nix
    ./modules/photo-workflow/default.nix
    gallatinRunners.nixosModules.github-actions-runner
    ./containers/source/utilities/rawbackup/status.nix
    ./containers/source/media/docker-compose.nix
    ./containers/source/networking/docker-compose.nix
    ./containers/source/observability/docker-compose.nix
    ./containers/source/torrenting/docker-compose.nix
    ./containers/source/utilities/docker-compose.nix
  ]
  # The public target must remain public even when this checkout also has the
  # private submodule. Only the production target may import it.
  ++ lib.optional usePrivateSystemConfiguration privateSystemConfiguration
  ++ lib.optional (!requirePrivateSystemConfiguration) ./hardware-configuration.nix
  ++ lib.optional usePrivateSystemConfiguration {
    # Keep the deployment runner alive after the SSH transport is restarted.
    users.users.github-actions.linger = true;

    # Keep known non-critical failures from blocking the deployment health
    # gate while they are repaired. The verifier still reports these units,
    # but SSH, OpNix, networking, certificates, and all other containers stay
    # strict requirements.
    environment.etc."electricpeak/quarantined-systemd-units".text =
      "# Keep the ACME timer enabled so it can retry renewal.\n"
      + lib.concatMapStrings (name: "acme-order-renew-${name}.service\n")
        (lib.attrNames config.security.acme.certs);

    # Keep management SSH available when a runtime secret refresh fails. The
    # authorized-key installer remains independently wanted by
    # multi-user.target, but it must not be a hard requirement for sshd.
    systemd.services.sshd = {
      requires = lib.mkForce [ ];

      # The private overlay orders sshd after its runtime key installers. Keep
      # those installers best-effort so a secret-manager or DNS outage cannot
      # delay management access.
      after = lib.mkForce [
        "network.target"
        "sshd-keygen.service"
      ];
    };
  };

  config = lib.mkMerge [
    {
      assertions = lib.optional requirePrivateSystemConfiguration {
        assertion = hasPrivateSystemConfiguration;
        message = ''
          The electricpeak system requires the private-config submodule. Initialize
          private-config before evaluating or deploying the electricpeak flake.
        '';
      };

      # Home Manager is wired for this account by the flake even when the
      # private system module is intentionally absent during public checks.
      users.users.junr03.home = "/home/junr03";
      users.users.github-actions.home = "/home/github-actions";

      nixpkgs.config.allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "1password-cli"
          "zerotierone"
        ];
    }
    (lib.mkIf (!requirePrivateSystemConfiguration) {
      # Generic public defaults. The production target imports the private
      # configuration separately.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      networking.hostName = "nixos";
      networking.firewall.enable = true;

      users.users = {
        junr03 = {
          isNormalUser = true;
          extraGroups = [
            "wheel"
            "networkmanager"
            "docker"
          ];
          packages = with pkgs; [ tree ];
        };

        github-actions = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };
      };

      home-manager.users.junr03 = {
        imports = [ ./users/junr03/default.nix ];
      };

      security.polkit.enable = true;

      environment.systemPackages = with pkgs; [
        self.packages.${pkgs.stdenv.hostPlatform.system}.codex
        compose2nix
        curl
        git
        jq
      ];

      virtualisation.docker.enable = true;
      virtualisation.oci-containers.backend = "docker";

      programs.nix-ld.enable = true;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      system.stateVersion = "24.11";
    })
  ];
}
