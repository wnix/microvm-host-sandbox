{ lib, pkgs, userConfig, ... }:
let
  guestPath =
    if (builtins.getEnv "MICROVM_GUEST_CONFIG") != "" then
      (builtins.getEnv "MICROVM_GUEST_CONFIG")
    else
      userConfig.vm.guestConfigPath;
  wiring = import ./microvm-wiring.nix { inherit lib userConfig guestPath; };
  # Inline so `nix build` / flakes work before `git add` of agent-bootstrap.sh
  agentBootstrap = pkgs.writeShellScript "agent-bootstrap" ''
    set -eu
    STATE="/nix/.rw-store/.agent-bootstrap-once"
    if [ -f "$STATE" ]; then
      exit 0
    fi

    fl="/home/agent/system-config/flake.nix"
    if [ ! -f "$fl" ]; then
      echo "nix-sandbox: no flake at /home/agent/system-config — set vm.guestConfigPath on the *host* to a real guest-config repo (with flake.nix)." >&2
      exit 0
    fi
    if [ ! -d /home/agent/system-config/.git ]; then
      echo "nix-sandbox: /home/agent/system-config is not a git work tree" >&2
      exit 0
    fi

    if [ ! -f /home/agent/.config/git/config ]; then
      install -d -m0700 -o agent -g users /home/agent/.config
      su -s ${pkgs.bash}/bin/bash agent -c "git config --global user.name agent && git config --global user.email agent@localhost" || true
    fi

    if command -v nix >/dev/null; then
      ( cd /home/agent/system-config && su -s ${pkgs.bash}/bin/bash agent -c "nix flake update" 2>/dev/null ) || true
    fi

    {
      echo "nix-sandbox — working tree: /home/agent/system-config"
      echo "  nixos-rebuild switch --flake /home/agent/system-config"
      echo "Rollback:  sudo nixos-rebuild switch --rollback"
      echo "SSH: use host port from config.nix (vm.forwardedPorts)"
    } >/etc/motd

    touch "$STATE"
    echo "agent-bootstrap: done" >&2
  '';
in
{
  imports = [
    wiring
    ./base-system.nix
    ./overlay-store.nix
  ];

  systemd.services.agent-bootstrap = {
    description = "One-time guest setup (git, welcome)";
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = agentBootstrap;
    };
  };
}
