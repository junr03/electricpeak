{ lib, pkgs, ... }:
let
  image = "electricpeak-watchkeeper-smoke:7e31ce4aeafc";
  source = pkgs.fetchFromGitHub {
    owner = "junr03";
    repo = "project-watchkeeper";
    rev = "7e31ce4aeafca041f25b8262f6d76ba6fbd7966c";
    hash = "sha256-pDMQn86JrGwiXzZgdPHq6a11kpi5b/4jJ5kNjTXa0NI=";
  };
  initCredentials = pkgs.writeShellScript "watchkeeper-smoke-init-credentials" ''
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
in
{
  # The compose2nix generated module is updated by PR CI. Supplying the full
  # image scalar here keeps public evaluation valid before that generated
  # import contains the new service; generated env, volume, port and network
  # fields merge into this manual, opt-in OCI container definition afterward.
  virtualisation.oci-containers.containers.watchkeeper-smoke = {
    inherit image;
    pull = "never";
    autoStart = false;
    extraOptions = [
      "--read-only"
      "--stop-timeout=180"
      "--tmpfs=/tmp:size=64m,mode=1777"
      "--tmpfs=/run/watchkeeper/broker:rw,noexec,nosuid,size=1m,mode=0750,uid=1000,gid=2000"
    ];
  };

  systemd.services."docker-watchkeeper-smoke" = {
    enable = true;
    wantedBy = lib.mkForce [ ];
    partOf = lib.mkForce [ ];
    requires = [ "watchkeeper-smoke-build.service" "watchkeeper-smoke-credentials.service" ];
    after = [ "watchkeeper-smoke-build.service" "watchkeeper-smoke-credentials.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = lib.mkForce "no";
      TimeoutStopSec = lib.mkForce "210s";
    };
  };

  # The generated Compose module normally attaches this bridge to the shared
  # root target. Keep it opt-in with the app; starting the app will pull it in
  # through the generated container's network dependency.
  systemd.services."docker-network-watchkeeper-smoke" = {
    wantedBy = lib.mkForce [ ];
    partOf = lib.mkForce [ ];
  };

  systemd.services.watchkeeper-smoke-build = {
    description = "Build the pinned public Watchkeeper smoke-test image";
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    path = [ pkgs.docker ];
    script = ''
      if ! docker image inspect ${lib.escapeShellArg image} >/dev/null 2>&1; then
        docker build --network=none --file ${source}/Dockerfile --tag ${lib.escapeShellArg image} ${source}
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30min";
    };
  };

  systemd.services.watchkeeper-smoke-credentials = {
    description = "Create persistent local-only Watchkeeper smoke credentials";
    path = [ pkgs.coreutils ];
    script = "${initCredentials}";
    serviceConfig = {
      Type = "oneshot";
    };
  };

  environment.systemPackages = [ pkgs.curl pkgs.jq ];
  environment.etc."electricpeak/watchkeeper-smoke/seed-demo.sh" = {
    source = ./seed-demo.sh;
    mode = "0555";
  };
  environment.etc."electricpeak/watchkeeper-smoke/codex-two-thread-demo.json" = {
    source = "${source}/fixtures/codex-two-thread-demo.json";
    mode = "0444";
  };
}
