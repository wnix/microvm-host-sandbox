# Parameterised microvm stanza. Copy this file to the guest-config repo
# (or use templates/guest-config/) and keep in sync with the host: tags,
# port lists, and volume name must match what `nix run .#sandbox` / microvm-run uses.
{ lib, userConfig, guestPath }:
let
  p = userConfig.vm;
  diskMiB = p.diskSizeGiB * 1024;
  nixLower = p.hostNixStorePath;
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
        source = guestPath;
        mountPoint = "/home/agent/system-config";
        readOnly = false;
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
