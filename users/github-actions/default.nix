{ config, pkgs, lib, ... }:

{

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "github-actions";
  home.homeDirectory = "/home/github-actions";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "25.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs = {
    git = {
      enable = true;
      settings.user = {
        name = "GitHub Actions";
        email = "github-actions@example.invalid";
      };
    };

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          ForwardAgent = false;
          AddKeysToAgent = "no";
          Compression = false;
          ServerAliveInterval = 0;
          ServerAliveCountMax = 3;
          HashKnownHosts = false;
          UserKnownHostsFile = "~/.ssh/known_hosts";
          ControlMaster = "no";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "no";
        };
        "github.com" = {
          User = "git";
          HostName = "github.com";
          IdentityFile = "~/.ssh/github";
        };
      };
    };
  };
  services.ssh-agent.enable = true;

  # Ensure .ssh directory exists
  home.activation.ensureSshDir = lib.hm.dag.entryAfter [ "writeBoundary" ]
    (builtins.readFile ./scripts/ensure-ssh-dir.sh);

}
