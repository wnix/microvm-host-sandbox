{
  description = "MicroVM sandbox (host/hypervisor flake — never mounted into the guest as system-config)";

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
    guestConfig = {
      url = "github:wnix/microvm-guest-template";
      flake = true;
    };
  };

  outputs = { self, nixpkgs, microvm, guestConfig }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;
    userConfig = guestConfig.userConfig;
    nixosConfig = lib.nixosSystem {
      inherit system;
      specialArgs = { inherit userConfig; };
      modules = [
        microvm.nixosModules.microvm
        self.nixosModules.wiring
        guestConfig.nixosModules.profile
      ];
    };
    runner = nixosConfig.config.microvm.declaredRunner;
  in
  {
    nixosConfigurations.sandbox = nixosConfig;

    nixosModules.wiring = import ./modules/wiring.nix;

    packages.${system} = {
      default = runner;
      sandbox-vm = runner;
    };

    apps.${system} = {
      sandbox = {
        type = "app";
        program = toString (pkgs.writeShellScript "sandbox" ''
          set -euo pipefail

          DEFAULT_CLONE_URL="https://github.com/wnix/microvm-guest-template.git"
          GUEST_DIR="sandbox-guest-config"
          GUEST_OVERRIDE=""
          GUEST_9P=""

          while [ $# -gt 0 ]; do
            case "$1" in
              --guest-config)
                if [ -z "''${2:-}" ]; then
                  echo "missing path or flake ref after --guest-config" >&2
                  exit 1
                fi
                _gc="$2"
                shift 2
                case "$_gc" in
                  github:*)
                    _slug="''${_gc#github:}"
                    _slug="''${_slug%%#*}"
                    if [ ! -f "$GUEST_DIR/flake.nix" ]; then
                      echo "cloning guest flake github:''${_slug} -> ./$GUEST_DIR" >&2
                      rm -rf "$GUEST_DIR"
                      ${lib.getExe pkgs.git} clone --depth 1 "https://github.com/''${_slug}.git" "$GUEST_DIR"
                    fi
                    GUEST_9P="$(pwd)/$GUEST_DIR"
                    GUEST_OVERRIDE="path:$GUEST_9P"
                    ;;
                  git+https:*|git+ssh:*)
                    if [ ! -f "$GUEST_DIR/flake.nix" ]; then
                      echo "cloning guest flake ''${_gc} -> ./$GUEST_DIR" >&2
                      rm -rf "$GUEST_DIR"
                      ${lib.getExe pkgs.git} clone --depth 1 "$_gc" "$GUEST_DIR"
                    fi
                    GUEST_9P="$(pwd)/$GUEST_DIR"
                    GUEST_OVERRIDE="path:$GUEST_9P"
                    ;;
                  *)
                    if [ ! -d "$_gc" ]; then
                      echo "guest-config path does not exist: $_gc" >&2
                      exit 1
                    fi
                    GUEST_9P="$(cd "$_gc" && pwd)"
                    GUEST_OVERRIDE="path:$GUEST_9P"
                    ;;
                esac
                ;;
              *) break ;;
            esac
          done

          if [ -z "$GUEST_9P" ]; then
            if [ ! -f "$GUEST_DIR/flake.nix" ]; then
              echo "cloning default guest template -> ./$GUEST_DIR" >&2
              ${lib.getExe pkgs.git} clone --depth 1 "$DEFAULT_CLONE_URL" "$GUEST_DIR"
            fi
            GUEST_9P="$(pwd)/$GUEST_DIR"
            GUEST_OVERRIDE="path:$GUEST_9P"
          fi

          _hostroot=$(${lib.getExe pkgs.git} rev-parse --show-toplevel 2>/dev/null || true)
          if [ -z "$_hostroot" ]; then
            _hostroot="$(pwd)"
          fi

          export MICROVM_GUEST_CONFIG="$GUEST_9P"
          export MICROVM_HOST_FLAKE="$_hostroot"

          exec ${lib.getExe pkgs.nix} run --impure \
            --override-input guestConfig "$GUEST_OVERRIDE" \
            "path:${self.outPath}#sandbox-vm" -- "$@"
        '');
      };
    };

    templates.agent-sandbox = {
      path = ./.;
      description = "MicroVM sandbox host — QEMU, 9p nix-store overlay, flake-pinned guest-config";
    };
  };
}
