{
  config,
  pkgs,
  ...
}:
let
  containers_config = "${config.home.homeDirectory}/containers_storage/appdata";
  home_assistant_config = "${containers_config}/homeassistant/config";
  ldata-ha = pkgs.fetchFromGitHub {
    owner = "junr03";
    repo = "ldata-ha";
    rev = "8296f89";
    hash = "sha256-UQnWEfoadJgDHFGMeRsQp9oiMd6WnM8l/MKVS7D4mjg=";
  };
  mirrorFile = pkgs.writeShellApplication {
    name = "mirror-container-file";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ./scripts/mirror-file.sh;
  };
  mirrorTree = pkgs.writeShellApplication {
    name = "mirror-container-tree";
    runtimeInputs = with pkgs; [ coreutils findutils ];
    text = builtins.readFile ./scripts/mirror-tree.sh;
  };
  mirrorVdirsyncerConfig = pkgs.writeShellApplication {
    name = "mirror-vdirsyncer-config";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ./scripts/mirror-vdirsyncer-config.sh;
  };
  mirrorFileCommand = source: destination: mode: createParent:
    "${mirrorFile}/bin/mirror-container-file ${pkgs.lib.escapeShellArgs [ source destination mode createParent ]}";
in
{
  "${home_assistant_config}/configuration_link.yaml" = {
    source = ../../containers/config/home_assistant/configuration.yaml;
    onChange = mirrorFileCommand
      "${home_assistant_config}/configuration_link.yaml"
      "${home_assistant_config}/configuration.yaml"
      "644"
      "false";
    force = true;
  };

  # Pin the proposed LDATA fix to an immutable commit while it is under review.
  # Keep the Home Manager source link outside the directory mounted by the
  # container: absolute /nix/store symlinks cannot be resolved in the container.
  "${home_assistant_config}/custom_components/ldata_link" = {
    source = "${ldata-ha}/custom_components/ldata";
    recursive = true;
    onChange = "${mirrorTree}/bin/mirror-container-tree ${pkgs.lib.escapeShellArgs [
      "${home_assistant_config}/custom_components/ldata_link"
      "${home_assistant_config}/custom_components/ldata"
    ]}";
    force = true;
  };

  "${home_assistant_config}/packages/sensors_link.yaml" = {
    source = ../../containers/config/home_assistant/packages/sensors.yaml;
    onChange = mirrorFileCommand
      "${home_assistant_config}/packages/sensors_link.yaml"
      "${home_assistant_config}/packages/sensors.yaml"
      "644"
      "true";
    force = true;
  };

  "${containers_config}/vdirsyncer/config_link" = {
    source = ../../containers/config/vdirsyncer/config;
    onChange = "${mirrorVdirsyncerConfig}/bin/mirror-vdirsyncer-config ${pkgs.lib.escapeShellArgs [
      "${containers_config}/vdirsyncer/config_link"
      "${containers_config}/vdirsyncer"
    ]}";
    force = true;
  };

  "${containers_config}/vdirsyncer/require-enabled_link.sh" = {
    source = ../../containers/config/vdirsyncer/require-enabled.sh;
    onChange = mirrorFileCommand
      "${containers_config}/vdirsyncer/require-enabled_link.sh"
      "${containers_config}/vdirsyncer/require-enabled.sh"
      "755"
      "false";
    force = true;
  };
}
