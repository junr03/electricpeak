{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-zerotier.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opnix = {
      url = "github:brizzbuzz/opnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gallatin = {
      url = "github:junr03/gallatin?rev=e6ca46f2fe0c02a396142ffbfd1864f517453b85";
      flake = false;
    };
    gallatinRunners.url = "github:junr03/gallatin?dir=runners&rev=e6ca46f2fe0c02a396142ffbfd1864f517453b85";
    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      opnix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      rustPackages = import ./rust/packages.nix { inherit pkgs; };
      zerotierPkgs = import inputs."nixpkgs-zerotier" {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (lib.getName pkg) [
            "zerotierone"
          ];
      };
      makeNixosConfiguration = requirePrivateSystemConfiguration:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self zerotierPkgs requirePrivateSystemConfiguration;
            gallatin = inputs.gallatin;
            gallatinRunners = inputs.gallatinRunners;
          };
          modules = [
            ./configuration.nix
            opnix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users = {
                junr03 = ./users/junr03/default.nix;
                github-actions = ./users/github-actions/default.nix;
              };

              # Optionally, use home-manager.extraSpecialArgs to pass
              # arguments to home.nix
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        # Keep a public configuration for evaluation and documentation. It is
        # never a valid production deployment target.
        electricpeak-public = makeNixosConfiguration false;
      } // nixpkgs.lib.optionalAttrs (builtins.pathExists ./private-config/configuration.nix) {
        electricpeak = makeNixosConfiguration true;
      };

      packages.${system} = {
        codex = inputs.codex-cli-nix.packages.${system}.default;
        inherit (rustPackages) rawbackup-status-collector;
      };

      checks.${system} = {
        rawbackup-status-collector = rustPackages.rawbackup-status-collector;
        rawbackup-api-contract = pkgs.runCommand "rawbackup-api-contract" {
          nativeBuildInputs = [ pkgs.python3Packages.openapi-spec-validator ];
        } ''
          openapi-spec-validator ${./contracts/rawbackup/v1/openapi.yaml}
          touch $out
        '';
      };

      devShells.${system} = {
        rust = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            clippy
            rustc
            rustfmt
          ];
        };

        public = pkgs.mkShell {
          packages = with pkgs; [
            actionlint
            gitleaks
            python3
            shellcheck
          ];
        };
      };
    };
}
