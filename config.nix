# User-facing sandbox knobs. Fork or branch the repo, edit this, then run
# `nix run .#sandbox` — no other files should be required for basic reshaping.
{
  # --- Resources (microvm / QEMU) ---
  vm.cpus = 4;
  vm.memoryMiB = 4096;
  # Writable /nix overlay backing volume (MiB) — nix-daemon new store paths
  vm.diskSizeGiB = 40;

  # --- SSH: paste your *host* public key (same key you will use: ssh -p <port> agent@127.0.0.1) ---
  # Example: (builtins.readFile /home/yourname/.ssh/id_ed25519.pub) — only if the path is non-secret.
  vm.agentSshKeys = [
  ];

  # --- Network: host TCP → guest TCP (requires QEMU + user networking; see vm/default.nix) ---
  vm.forwardedPorts = [
    { hostPort = 2222; guestPort = 22; }
    { hostPort = 8085; guestPort = 8080; }
  ];

  # --- Guest NixOS flake repo on the host: bind-mounted rw at /home/agent/system-config in the guest ---
  vm.guestConfigPath = "/home/basti/daten/Entwicklung/micro-vms/sandbox-guest-config";

  # --- Extra host directories inside the guest (optional) ---
  vm.hostMounts = [
    # { hostPath = "/home/user/projects"; guestPath = "/mnt/projects"; readOnly = false; }
  ];

  # Host nix store path (read-only share + overlay lower); keep default
  vm.hostNixStorePath = "/nix/store";

  # --- Hypervisor: microvm.nix only applies forwardPorts for "qemu" + "user" networking.
  # cloud-hypervisor is faster but then you must bridge/tap and SSH to the guest IP (no automatic port forward).
  vm.hypervisor = "qemu";
}
