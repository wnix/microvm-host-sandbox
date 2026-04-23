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
          default=${lib.escapeShellArg userConfig.vm.guestConfigPath}
          while [ $# -gt 0 ]; do
            case "$1" in
              --guest-config)
                if [ -z "''${2:-}" ]; then
                  echo "missing path after --guest-config" >&2
                  exit 1
                fi
                export MICROVM_GUEST_CONFIG="''$2"
                shift 2
                ;;
              *) break ;;
            esac
          done
          if [ -z "''${MICROVM_GUEST_CONFIG:-}" ]; then
            export MICROVM_GUEST_CONFIG="$default"
          fi
          exec ${lib.getExe pkgs.nix} run --impure "path:${self.outPath}#sandbox-vm" -- "$@"
        '');
      };
    };
  };
}
