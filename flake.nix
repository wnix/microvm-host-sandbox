{
  description = "MicroVM sandbox (host/hypervisor flake — never mounted into the guest)";

  nixConfig = {
    extra-substituters = [ "https://microvm.cachix.org" ];
    extra-trusted-public-keys = [ "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;
    userConfig = import ./config.nix;
    nixosConfig = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit userConfig; };
      modules = [
        microvm.nixosModules.microvm
        ./vm/default.nix
      ];
    };
    runner = nixosConfig.config.microvm.declaredRunner;
  in
  {
    nixosConfigurations.sandbox = nixosConfig;

    packages.${system} = {
      default = runner;
      sandbox-vm = runner;
    };

    apps.${system} = {
      sandbox = {
        type = "app";
        program = toString (pkgs.writeShellScript "sandbox" ''
          set -euo pipefail
          while [ $# -gt 0 ]; do
            case "$1" in
              --guest-config)
                if [ -z "''${2:-}" ]; then
                  echo "missing path after --guest-config" >&2
                  exit 1
                fi
                export MICROVM_GUEST_CONFIG="$2"
                shift 2
                ;;
              *) break ;;
            esac
          done
          if [ -z "''${MICROVM_GUEST_CONFIG:-}" ]; then
            _repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)
            if [ -n "$_repo" ] && [ -d "$_repo/sandbox-guest-config" ]; then
              export MICROVM_GUEST_CONFIG="$_repo/sandbox-guest-config"
            else
              echo "error: no guest config found. Run one of:" >&2
              echo "  git submodule update --init" >&2
              echo "  nix run .#sandbox -- --guest-config /absolute/path/to/guest-config" >&2
              exit 1
            fi
          fi
          exec ${lib.getExe pkgs.nix} run --impure "path:${self.outPath}#sandbox-vm" -- "$@"
        '');
      };
    };

    templates.agent-sandbox = {
      path = ./.;
      description = "MicroVM sandbox host — QEMU, 9p nix-store overlay, guest-config submodule";
    };
  };
}
