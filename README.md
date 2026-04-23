# micro-vm-template (host / hypervisor)

Standalone Nix flake: builds and runs a **NixOS microvm** (via [microvm.nix](https://github.com/microvm-nix/microvm.nix)) for an isolated, reproducible sandbox. The **hypervisor** definition lives only in this repository and is **not** shared with the guest.

The **guest** edits its own NixOS config in a **separate** git repository, bind-mounted at `/home/agent/system-config` inside the VM.

## Why two repositories?

1. **Security:** The guest must not see the VM layout, port forwards, or host paths in this repo. Only the guest-config repo is shared into the guest.
2. **Lifecycle:** You commit to this repo on the host; the agent can `git commit` / `git push` the guest config from inside the VM.

## Setup — two paths to a running sandbox

### Path A — Nix flake template (recommended)

Use this when you want a blank-slate host and/or guest that you can push to your own git remote.

```bash
# 1. Bootstrap the host repo
mkdir my-sandbox-host && cd my-sandbox-host
nix flake init --template github:wnix/microvm-host-sandbox#agent-sandbox
git init && git add -A && git commit -m "init host"

# 2. Bootstrap the guest config repo (separate repo, separate remote)
mkdir ../my-sandbox-guest && cd ../my-sandbox-guest
nix flake init --template github:wnix/microvm-guest-template
git init && git add -A && git commit -m "init guest"

# 3. Push both to your own remotes, then wire them as a submodule:
cd ../my-sandbox-host
git submodule add git@github.com:my-org/my-sandbox-guest.git sandbox-guest-config
git add .gitmodules sandbox-guest-config
git commit -m "add guest config submodule"
```

### Path B — GitHub template (click-ops)

1. Press **"Use this template"** on [`wnix/microvm-host-sandbox`](https://github.com/wnix/microvm-host-sandbox) → creates `my-org/my-sandbox-host`
2. Press **"Use this template"** on [`wnix/microvm-guest-template`](https://github.com/wnix/microvm-guest-template) → creates `my-org/my-sandbox-guest`
3. Wire them:

   ```bash
   git clone git@github.com:my-org/my-sandbox-host.git
   cd my-sandbox-host
   git submodule add git@github.com:my-org/my-sandbox-guest.git sandbox-guest-config
   git add .gitmodules sandbox-guest-config && git commit -m "add guest config submodule"
   ```

### Clone an existing setup (with submodule)

```bash
git clone --recurse-submodules git@github.com:my-org/my-sandbox-host.git
```

If you forgot `--recurse-submodules`:

```bash
git submodule update --init
```

---

### Run and connect

```bash
# From the host repo root (launcher auto-detects ./sandbox-guest-config)
nix run .#sandbox
```

SSH in (default: host port 2222 → guest port 22):

```bash
ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -p 2222 agent@127.0.0.1
```

No SSH key in `vm.agentSshKeys`? The default dev password is `agent`.

Apply or update the guest NixOS config from inside the VM:

```bash
sudo nixos-rebuild switch --flake /home/agent/system-config
# rollback:
sudo nixos-rebuild switch --rollback
```

### Use a different guest config without editing anything

```bash
nix run .#sandbox -- --guest-config /absolute/path/to/any-guest-config
```

### The submodule as a deployment primitive

The power of the submodule model: an agent works inside the VM, makes NixOS commits to `/home/agent/system-config` (which is the host-side `sandbox-guest-config/` checkout), and pushes. On the host you pin the new state by bumping the submodule:

```bash
cd sandbox-guest-config && git pull   # fast-forward to agent's work
cd ..
git add sandbox-guest-config
git commit -m "pin guest config to latest agent checkpoint"
```

Anyone who clones the host repo with `--recurse-submodules` gets an exact, reproducible replay of the same guest state.

## Layout (this repo)

- `config.nix` — sole **user** knob file: CPUs, memory, disk size, ports, extra `hostMounts`, hypervisor. No absolute paths required — the launcher auto-detects the `sandbox-guest-config` submodule.
- `vm/microvm-wiring.nix` — `microvm` options (9p shares, overlay volume) shared conceptually with the **guest** repo; see [Keeping the two repos in sync](#keeping-the-two-repos-in-sync).
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

- You should only see: `ls /home/agent/system-config` (your **guest** repo), the usual Nix store and `/nix/.rw-store`, and your configured extra mounts.

## Keeping the two repos in sync

Both repos carry files that describe the **same virtual hardware**, but from different perspectives:

| File (host) | File (guest) | What it controls |
|---|---|---|
| `config.nix` | `config.nix` | CPU count, RAM, disk size, port forwards, hypervisor |
| `vm/microvm-wiring.nix` | `microvm-wiring.nix` | 9p share **tags**, volume name, mount-points, overlay path |

The **host** copy is what QEMU actually runs. The **guest** copy is what `nixos-rebuild switch` bakes into the guest's own NixOS closure (fstab entries, systemd mount units, kernel arguments, firewall rules). If they diverge, the VM can still boot — but `nixos-rebuild switch` inside the VM will apply a config that no longer matches the running hypervisor.

### What *must* stay identical on both sides

- **9p share tags** (`ro-store`, `guest-cfg`, `hmount-0`, …) — QEMU exports each share under a tag; the guest kernel mounts it by that tag. A mismatch means the mount silently hangs or fails.
- **Volume image name** (`nix-rw-store.img`) and **mount point** (`/nix/.rw-store`) — the writable overlay volume. Name mismatch → QEMU presents a disk the guest doesn't mount; point mismatch → the Nix overlay has no upper layer.
- **`writableStoreOverlay`** path in `microvm-wiring.nix` — must equal the volume's `mountPoint` on both sides.
- **Port numbers** in `vm.forwardedPorts` — the host side determines what QEMU maps; the guest side determines what the firewall opens. A missing guest-side entry means the port is forwarded by QEMU but blocked by `iptables` inside the VM (and vice versa: a guest-side `allowedTCPPorts` for a port not forwarded by the host is harmless but misleading).

### What can safely differ

- Comments, ordering, and any option that does **not** affect the kernel mount table or the QEMU command line.
- `vm.guestConfigPath` — only used by the host to locate the 9p source directory; the guest ignores it.
- `vm.agentSshKeys` / `vm.hostNixStorePath` — guest-only or host-only semantics; no cross-side contract.

### Change procedure

1. **Edit the host** (`config.nix` and/or `vm/microvm-wiring.nix`).
2. **Mirror the change** to the guest repo (`config.nix` and/or `microvm-wiring.nix`); commit both.
3. **Stop the running VM** (Ctrl-C or `systemctl stop microvm@sandbox` if using the host module).
4. **Rebuild and restart** from this repo:
   ```bash
   nix run .#sandbox
   ```
5. *(Optional)* Inside the guest, apply the new guest config:
   ```bash
   sudo nixos-rebuild switch --flake /home/agent/system-config
   ```

### Disk size warning

`vm.diskSizeGiB` controls the size of `nix-rw-store.img` **only at creation time** (`autoCreate = true`). An already-existing image is never resized automatically. If you increase the disk size, you must either:

- Delete `nix-rw-store.img` before the next boot (losing any packages built inside the VM), then let it be recreated, or
- Resize it offline with `e2fsck -f` + `resize2fs`.

## Known limitations

- Port forwards require the **Qemu** + **user** networking stack; see the Configuration notes table.

## License

This template layout is for reuse in your own projects; apply your preferred license.
