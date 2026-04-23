# micro-vm-template (host / hypervisor)

Standalone Nix flake: builds and runs a **NixOS microvm** (via [microvm.nix](https://github.com/microvm-nix/microvm.nix)) for an isolated, reproducible sandbox. The **hypervisor** definition lives only in this repository and is **not** shared with the guest.

The **guest** edits its own NixOS config in a **separate** git repository, bind-mounted at `/home/agent/system-config` inside the VM.

## Why two repositories?

1. **Security:** The guest must not see the VM layout, port forwards, or host paths in this repo. Only the guest-config repo is shared into the guest.
2. **Lifecycle:** You commit to this repo on the host; the agent can `git commit` / `git push` the guest config from inside the VM.

## Quick start

1. **Create or reuse a guest-config repo** (or copy `templates/guest-config/` and `git init`):

   ```bash
   cp -r templates/guest-config/ ~/my-sandbox-guest
   cd ~/my-sandbox-guest && nix flake update && git init && git add -A && git commit -m init
   ```

2. **Point the host** at that directory: edit `config.nix` and set `vm.guestConfigPath` to the **absolute** path of the guest repo on the host. Optionally add your `ssh-ed25519` public key to `vm.agentSshKeys` (then SSH password logins are disabled).
3. **Run the VM** from *this* repository:

   ```bash
   nix run .#sandbox
   ```

4. **SSH** from the host (default forward in `config.nix`: host `2222` → guest `22`):

   ```bash
   ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -p 2222 agent@127.0.0.1
   ```

   If you have no SSH key in `vm.agentSshKeys`, the account password is `agent` (dev default only).

5. **Switch** to the in-guest flake (after the guest repo is a git checkout with `flake.nix`):

   ```bash
   sudo nixos-rebuild switch --flake /home/agent/system-config
   ```

6. **Rollback** inside the guest:

   ```bash
   sudo nixos-rebuild switch --rollback
   ```

### Override the guest path without editing `config.nix`

```bash
nix run .#sandbox -- --guest-config /path/to/guest-config
```

This re-evaluates the runner with `MICROVM_GUEST_CONFIG` (impure) so a different **host** directory is used as the 9p source for `/home/agent/system-config`.

## Layout (this repo)

- `config.nix` — sole **user** knob file: CPUs, memory, disk size, ports, `guestConfigPath`, extra `hostMounts`, hypervisor.
- `vm/microvm-wiring.nix` — `microvm` options (9p shares, overlay volume) shared conceptually with the **guest** repo; keep in sync.
- `vm/base-system.nix` — `agent` user, SSH, dev tools, Nix settings.
- `vm/overlay-store.nix` — extra nix `substituters` for the read-only store share.
- `vm/default.nix` — wires the above and one-shot `agent-bootstrap`.
- `templates/guest-config/` — starter **guest** flake; copy to a new repo, do **not** bind-mount this template directory for production.

## Architecture (data flow)

```
[ Host: your machine ]
  nix run .#sandbox  ->  QEMU (microvm-run)
       |                      |
       |  9p ro  /nix/store  ->  lower layer of /nix overlay
       |  9p rw  nix .rw      ->  ext4 image (new store paths, survives reboots)
       |  9p rw  guest repo   ->  /home/agent/system-config (git, flakes)
  NOT exposed to guest:  this repo's config.nix, vm/, host flake
```

- **Root filesystem** in the guest is tmpfs; **persistent** state is: the overlay upper on `/nix/.rw-store`, the bind-mounted guest config, and any `vm.hostMounts` you add.
- **Nix store overlay:** The host’s `/nix/store` is shared read-only and stacked with a writable ext4 image — the guest nix-daemon can build; the host store is never written by the guest.

## Configuration notes

| Topic | Notes |
|--------|--------|
| **Hypervisor** | Default is **Qemu** with user networking, because [microvm.nix only implements `forwardPorts` for `qemu` + `user` interfaces](https://microvm-nix.github.io/microvm.nix/). `cloud-hypervisor` is faster but you must bring your own network/port-forward story (e.g. tap + static IP, or a socat/SSH recipe). Set `vm.hypervisor` in `config.nix` accordingly. |
| **Nix** | `auto-optimise-store` is **not** enabled: microvm.nix disallows it together with a writable store overlay. |
| **KVM in guest** | The `agent` user is in the `kvm` group and modprobe lines enable **nested** KVM for `nixos-rebuild build-vm` / `nixos-test` (when the CPU/hypervisor allows it). |

## `systemd` on the (Linux) host

The generated runner is a normal package; you can install it as a user/system unit if you use the microvm host module elsewhere. This template does **not** require host NixOS: `nix run` is enough. See the microvm.nix book for `microvm@` service patterns on NixOS hosts.

## Verify isolation (guest cannot see the host template)

In the **guest** (SSH):

- `test ! -e /home/agent/supervisor-flake` (there is no mount of the host template path unless you add a malicious `vm.hostMounts`).
- You should only see: `ls /home/agent/system-config` (your **guest** repo), the usual Nix store and `/nix/.rw-store`, and your configured extra mounts.

## Known limitations

- Port forwards require the **Qemu** + **user** stack as above.
- Guest and host `config.nix` / `vm/microvm-wiring.nix` **must stay aligned** (share tags, volume name `nix-rw-store.img`, ports) or `nixos-rebuild switch` inside the VM can desynchronise the expected filesystems from the still-running `microvm-run` on the host. Change the **host** and rebuild the **runner** when you change `microvm` hardware options.

## License

This template layout is for reuse in your own projects; apply your preferred license.
