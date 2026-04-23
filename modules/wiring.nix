# Single source of truth for microvm 9p shares, volumes, and port forwards.
# Used by the host nixosConfiguration (declaredRunner) and by the guest flake
# (via inputs.microvmHost.nixosModules.wiring) so tags/mountPoints always match.
#
# On the hypervisor host, set MICROVM_GUEST_CONFIG and MICROVM_HOST_FLAKE (absolute paths).
# When evaluating inside the guest without those (e.g. nixos-rebuild without wrapper),
# placeholder source paths are used for shares; only tags + mountPoints affect guest mounts.
{ lib, userConfig, ... }:
let
  p = userConfig.vm;
  diskMiB = p.diskSizeGiB * 1024;
  nixLower = p.hostNixStorePath;
  guestPathEnv = builtins.getEnv "MICROVM_GUEST_CONFIG";
  hostFlakeEnv = builtins.getEnv "MICROVM_HOST_FLAKE";
  # `source` is only consumed by QEMU on the host; guest fileSystems use `tag` + mountPoint.
  guestShareSource =
    if guestPathEnv != "" then guestPathEnv else "/.microvm-placeholder-guest-cfg-source";
  hostFlakeShareSource =
    if hostFlakeEnv != "" then hostFlakeEnv else "/.microvm-placeholder-host-flake-source";
  forwardPorts = map
    (x: {
      from = "host";
      host.port = x.hostPort;
      guest.port = x.guestPort;
    })
    p.forwardedPorts;
in
{
  networking.hostName = "nix-sandbox";

  microvm = {
    inherit (p) hypervisor;
    vcpu = p.cpus;
    mem = p.memoryMiB;

    interfaces = lib.optionals (p.hypervisor == "qemu") [ {
      type = "user";
      id = "q";
      mac = "02:00:00:00:01:01";
    } ];

    shares = [
      {
        tag = "ro-store";
        proto = "9p";
        source = nixLower;
        mountPoint = "/nix/.ro-store";
        readOnly = true;
      }
      {
        tag = "guest-cfg";
        proto = "9p";
        source = guestShareSource;
        mountPoint = "/home/agent/system-config";
        readOnly = false;
      }
      {
        tag = "microvm-host";
        proto = "9p";
        source = hostFlakeShareSource;
        mountPoint = "/run/microvm-host";
        readOnly = true;
      }
    ] ++ lib.lists.imap0
      (i: m: {
        tag = "hmount-${toString i}";
        proto = "9p";
        source = m.hostPath;
        mountPoint = m.guestPath;
        readOnly = m.readOnly or true;
      })
      (p.hostMounts or [ ]);

    volumes = [ {
      image = "nix-rw-store.img";
      mountPoint = "/nix/.rw-store";
      size = diskMiB;
      autoCreate = true;
      fsType = "ext4";
    } ];

    writableStoreOverlay = "/nix/.rw-store";
    forwardPorts = forwardPorts;
    socket = "sandbox.sock";
  };

  networking.firewall.allowedTCPPorts = map (x: x.guestPort) p.forwardedPorts;
}
