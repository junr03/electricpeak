{
  config,
  pkgs,
  lib,
  ...
}:
let
  user = "junr03";
  userFiles = import ./files.nix { inherit config pkgs; };
in
{

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "${user}";
  home.homeDirectory = "/home/${user}";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";

  home.file = userFiles;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {
    git = {
      enable = true;
      userName = "José Ulises Niño Rivera";
      userEmail = "junr03@users.noreply.github.com";
    };

    ssh = {
      enable = true;
      matchBlocks = {
        "github.com" = {
          user = "git";
          hostname = "github.com";
          identityFile = "~/.ssh/github";
        };
      };
    };
  };

  services.ssh-agent.enable = true;
}
