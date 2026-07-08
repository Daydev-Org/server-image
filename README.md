# server-image

A minimal, Debian-based **bootable server image** for commercial shipment,
built with [mkosi](https://github.com/systemd/mkosi). It keeps the running
service set small while bundling a full hands-on troubleshooting toolkit.

The build produces a GPT disk image that boots on both **UEFI** (systemd-boot)
and **legacy BIOS** (GRUB) x86-64 servers, with an optional **arm64**
(UEFI-only) build, and ships it in a range of formats (see [Artifacts](#artifacts)).

## What's in the image

**Base system**

- Debian 13 (trixie), systemd as PID 1
- Networking via `systemd-networkd` (DHCP on any wired NIC) + `systemd-resolved`
- Time sync via `systemd-timesyncd`
- OpenSSH server (`ssh.service`)
- Fresh SSH host keys generated on first boot (never shared across units)

These five are the only services enabled by default.

**Troubleshooting / ops toolkit**

`htop` · `iotop` · `iftop` · `lsof` · `strace` · `tcpdump` · `iperf3` ·
`dig` (dnsutils) · `curl` · `wget` · `less` · `vim` · `nano` ·
`ss`/`ip` (iproute2) · `nc` (netcat-openbsd) · `traceroute` · `mtr` (mtr-tiny) ·
`rsync` · `tar` · `gzip` · `xz` · `zip` · `unzip` ·
`ssh`/`scp`/`sftp` (openssh) · `openssl`

`journalctl`, `systemctl`, and `dmesg` come from systemd / util-linux in the
base system.

## Artifacts

Every build converts the single disk image into all of the following (per
architecture), alongside a `SHA256SUMS` file:

| File | Format | Target |
| --- | --- | --- |
| `daydev-server-<arch>.img` | raw disk image | `dd` to disk / bare metal / generic hypervisors |
| `daydev-server-<arch>.qcow2` | QCOW2 (compressed) | QEMU / KVM / libvirt / OpenStack |
| `daydev-server-<arch>.vmdk` | VMDK (streamOptimized) | VMware Workstation / ESXi / VirtualBox |
| `daydev-server-<arch>.vhd` | VPC dynamic | Hyper-V Gen 1 / legacy Azure |
| `daydev-server-<arch>.vhdx` | VHDX | Hyper-V Gen 2 |
| `daydev-server-<arch>.ova` | OVF + VMDK appliance | VMware / VirtualBox "import appliance" |
| `daydev-server-x86-64-installer.iso` | hybrid BIOS+UEFI installer | boot from USB/optical, clone onto internal disk |

The `.img`, `.qcow2`, `.vmdk`, `.vhd`, `.vhdx`, and `.ova` all contain the same
bootable OS. The **installer ISO** is different: it boots a small RAM-disk
environment that writes the OS image onto a target disk. It lists the available
disks and asks for confirmation, or runs unattended when booted with a
`daydev.target=/dev/sdX` kernel argument. It is built for **x86-64 only**.

## Building in CI

`.github/workflows/build-image.yml` builds the image with the official
`setup-mkosi` action, converts it to every format above, and:

- builds on every push to `main` and on pull requests (validation),
- uploads all formats + `SHA256SUMS` as a workflow **artifact**,
- on a **`v*` tag**, publishes a **GitHub Release** with every asset.

Trigger a one-off (and pick the architecture) from the Actions tab via
**Run workflow** (`workflow_dispatch`).

### Optional repository secrets

| Secret | Purpose | Default if unset |
| --- | --- | --- |
| `ROOT_PASSWORD_HASH` | crypt(3) hash for the root password (e.g. `openssl passwd -6`) | password `daydev` (a build warning is emitted) |
| `SSH_AUTHORIZED_KEY` | public key line added to `/root/.ssh/authorized_keys` | none (password login only) |

> **Ship-ready checklist:** set `ROOT_PASSWORD_HASH` (or bake in
> `SSH_AUTHORIZED_KEY` and disable password auth), and review
> `mkosi.extra/etc/ssh/sshd_config.d/50-daydev.conf` to tighten `PermitRootLogin`
> / `PasswordAuthentication` once your own credentials are in place.

## Building locally

Requires mkosi >= 26 (`pipx install git+https://github.com/systemd/mkosi.git`).

```sh
# root password for the local build
echo 'daydev' > mkosi.rootpw && chmod 600 mkosi.rootpw

mkosi build          # writes mkosi.output/daydev-server.raw
mkosi vm             # boot the image in QEMU to try it out
```

## Deploying

**Bare metal / direct disk** — write the raw image to the target disk:

```sh
sudo dd if=daydev-server-x86-64.img of=/dev/sdX bs=4M status=progress conv=fsync
```

**Bare metal via installer** — write `daydev-server-x86-64-installer.iso` to a
USB stick (`dd`) or attach it as virtual media, boot the target, and follow the
prompt (or pass `daydev.target=/dev/sda` on the GRUB line for unattended installs).

**Hypervisor / cloud** — import the format your platform expects (`.qcow2`,
`.vmdk`, `.vhd`, `.vhdx`) as a boot volume, or "Import Appliance" the `.ova`.

On first boot the machine gets a unique machine-id and freshly generated SSH
host keys, brings up networking via DHCP, and starts sshd.

## Repository layout

| Path | Purpose |
| --- | --- |
| `mkosi.conf` | main image definition (distro, packages, bootloaders) |
| `mkosi.conf.d/` | per-architecture drop-ins (kernel, BIOS GRUB) |
| `mkosi.postinst.chroot` | enables the minimal service set, strips per-machine state |
| `mkosi.extra/` | files copied verbatim into the image (network, sshd, units) |
| `scripts/make-artifacts.sh` | raw → img/qcow2/vmdk/vhd/vhdx conversions |
| `scripts/make-ova.sh` | OVF descriptor + manifest → `.ova` |
| `scripts/make-installer-iso.sh` | RAM-disk installer → hybrid BIOS+UEFI `.iso` |
| `.github/workflows/build-image.yml` | CI build + convert + release pipeline |
