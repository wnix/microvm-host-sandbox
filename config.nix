# User-facing sandbox knobs. Edit this file, then `nix run .#sandbox`.
# No other files need touching for basic reshaping.
{
  # --- Resources (microvm / QEMU) ---
  vm.cpus = 4;
  vm.memoryMiB = 4096;
  # Writable /nix/.rw-store overlay volume — keeps built packages across reboots
  vm.diskSizeGiB = 40;

  # --- SSH: paste your host public key (ssh -p <hostPort> agent@127.0.0.1) ---
  # Example: vm.agentSshKeys = [ "ssh-ed25519 AAAA..." ];
  # Without a key, the account password defaults to "agent" (dev only).
  vm.agentSshKeys = [
  ];

  # --- Network: host TCP → guest TCP (QEMU user-networking) ---
  vm.forwardedPorts = [
    { hostPort = 2222; guestPort = 22; }
    { hostPort = 8085; guestPort = 8080; }
  ];

  # --- Guest config path (optional override) ---
  # By default the launcher detects ./sandbox-guest-config (git submodule).
  # Uncomment to hard-code a different path, or use:
  #   nix run .#sandbox -- --guest-config /absolute/path
  # vm.guestConfigPath = "/absolute/path/to/your/guest-config";

  # --- Extra host directories mounted into the guest (optional) ---
  vm.hostMounts = [
    # { hostPath = "/home/user/projects"; guestPath = "/mnt/projects"; readOnly = false; }
  ];

  # Host nix store (read-only 9p share + overlay lower layer); keep default
  vm.hostNixStorePath = "/nix/store";

  # --- Hypervisor ---
  # "qemu" supports forwardPorts out of the box; "cloud-hypervisor" is faster
  # but requires tap networking and manual SSH routing.
  vm.hypervisor = "qemu";
}
