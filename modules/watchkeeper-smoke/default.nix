{ lib, pkgs, ... }:
let
  upstreamRevision = "d9fdc6be15455e0cb471dcbde5beb189640ba60f";
  appImage = "ghcr.io/junr03/project-watchkeeper@sha256:5008834cc10afaf6f795baf7892414627b9fa61739545dee20d3fecc69a5c6cd";
  reviewerImage = "ghcr.io/junr03/project-watchkeeper-reviewer@sha256:d0bbb1246f5539b2c143cc186f43ce53178cc914bced8c01a9a342b7fd27c377";
  upstreamCompose = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/junr03/project-watchkeeper/${upstreamRevision}/compose.yaml";
    hash = "sha256-T60j5xdQx3Uy8V2115sylsCuQ372igfb1G6VPjN7bzc=";
  };
  demoFixture = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/junr03/project-watchkeeper/${upstreamRevision}/fixtures/codex-two-thread-demo.json";
    hash = "sha256-tG1U4aUXLAXUy4hLdoGekLulza9l6WLBPseRDXnYv+M=";
  };
  composeDirectory = "/etc/electricpeak/watchkeeper-smoke";
  composeCommand = "${pkgs.docker-compose}/bin/docker-compose --project-name watchkeeper-smoke --project-directory ${composeDirectory} --file ${composeDirectory}/compose.yaml --file ${composeDirectory}/compose.smoke.yaml";
  initializeCredentials = pkgs.writeShellScript "watchkeeper-smoke-init-credentials" ''
    set -euo pipefail
    umask 077
    data=/var/lib/watchkeeper-smoke
    install -d -o root -g root -m 0700 "$data"
    install -d -o 1000 -g 2000 -m 0700 "$data/state"
    install -d -o root -g root -m 0700 "$data/secrets"

    ensure_secret() {
      target="$data/secrets/$1"
      if [ -e "$target" ] || [ -L "$target" ]; then
        test -f "$target" && ! test -L "$target" && test -s "$target"
        chown 1000:2000 "$target"
        chmod 0400 "$target"
      else
        temporary="$target.new.$$"
        trap 'rm -f "$temporary"' EXIT
        ${pkgs.openssl}/bin/openssl rand -hex 32 > "$temporary"
        chown 1000:2000 "$temporary"
        chmod 0400 "$temporary"
        mv "$temporary" "$target"
        trap - EXIT
      fi
    }

    ensure_secret intake-token
    ensure_secret reviewer-token
    ensure_secret ui-username
    ensure_secret ui-password
  '';
  startSmoke = pkgs.writeShellScript "watchkeeper-smoke-start" ''
    set -euo pipefail
    compose() { ${composeCommand} "$@"; }
    if ! compose up --no-build --pull missing --no-deps --wait --wait-timeout 180 app; then
      compose down --timeout 180 || true
      exit 1
    fi
  '';
  stopSmoke = pkgs.writeShellScript "watchkeeper-smoke-stop" ''
    set -euo pipefail
    ${composeCommand} down --timeout 180
  '';
in
{
  # Fetch only the upstream Compose contract and synthetic fixture. Published
  # image digests avoid a host source build or an unpinned registry reference.
  environment.etc."electricpeak/watchkeeper-smoke/compose.yaml" = {
    source = upstreamCompose;
    mode = "0444";
  };
  environment.etc."electricpeak/watchkeeper-smoke/compose.smoke.yaml" = {
    source = ../../containers/source/utilities/watchkeeper-smoke/compose.smoke.yaml;
    mode = "0444";
  };
  environment.etc."electricpeak/watchkeeper-smoke/codex-two-thread-demo.json" = {
    source = demoFixture;
    mode = "0444";
  };
  environment.etc."electricpeak/watchkeeper-smoke/seed-demo.sh" = {
    source = ./seed-demo.sh;
    mode = "0555";
  };

  environment.systemPackages = [ pkgs.curl pkgs.jq ];

  systemd.services.watchkeeper-smoke-credentials = {
    description = "Create persistent local-only Watchkeeper smoke credentials";
    path = [ pkgs.coreutils ];
    script = "${initializeCredentials}";
    serviceConfig.Type = "oneshot";
  };

  systemd.services.watchkeeper-smoke = {
    description = "Run the Watchkeeper local smoke test using pinned upstream Compose";
    wantedBy = lib.mkForce [ ];
    partOf = lib.mkForce [ ];
    requires = [ "docker.service" "watchkeeper-smoke-credentials.service" ];
    after = [ "docker.service" "watchkeeper-smoke-credentials.service" ];
    environment = {
      WATCHKEEPER_IMAGE = appImage;
      WATCHKEEPER_REVIEWER_IMAGE = reviewerImage;
    };
    path = [ pkgs.docker-compose ];
    script = "${startSmoke}";
    preStop = "${stopSmoke}";
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "15min";
      TimeoutStopSec = "210s";
    };
  };
}
