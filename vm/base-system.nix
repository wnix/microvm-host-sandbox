{ config, lib, pkgs, userConfig, ... }:
let
  p = userConfig.vm;
  keys = p.agentSshKeys or [ ];
  hasKeys = (builtins.length keys) > 0;
in
{
  system.stateVersion = "25.05";

  time.timeZone = "UTC";

  # Without SSH keys, a known dev password is set — put keys in config.nix for anything real.
  users.users.agent = {
    isNormalUser = true;
    home = "/home/agent";
    createHome = true;
    group = "users";
    extraGroups = [ "wheel" "kvm" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = keys;
  } // lib.optionalAttrs (!hasKeys) { initialPassword = "agent"; };

  # Passwordless sudo for the agent
  security.sudo.wheelNeedsPassword = false;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = if hasKeys then false else true;
    };
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    jq
    ripgrep
    fd
    tmux
    htop
    neovim
    nixos-rebuild
  ];

  # Nested KVM for nixos-rebuild build-vm / nixos-test inside the guest
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm nested=1
  '';

  nix = {
    package = pkgs.nix;
    nixPath = [ "nixpkgs=${pkgs.path}" ];
    channel.enable = false;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };
}
