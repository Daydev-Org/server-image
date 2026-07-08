# server-image

A minimal, Debian-based **bootable server image** for commercial shipment,
built with [mkosi](https://github.com/systemd/mkosi). It keeps the running
service set small while bundling a full hands-on troubleshooting toolkit.

The build produces a GPT disk image (`daydev-server.raw`, compressed to
`daydev-server-<arch>.raw.zst`) that boots on both **UEFI** (systemd-boot) and
**legacy BIOS** (GRUB) x86-64 servers, with an optional **arm64** (UEFI-only)
build.

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

## Building in CI

`.github/workflows/build-image.yml` builds the image with the official
`setup-mkosi` action and:

- builds on every push to `main` and on pull requests (validation),
- uploads the compressed image + `.sha256` as a workflow **artifact**,
- on a **`v*` tag**, publishes a **GitHub Release** with the image assets.

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

The `.raw.zst` is a full disk image. Decompress and write it to the target
disk / boot volume, then let it expand:

```sh
zstd -d daydev-server-x86-64.raw.zst
sudo dd if=daydev-server-x86-64.raw of=/dev/sdX bs=4M status=progress conv=fsync
```

Or import the raw image into your hypervisor / cloud provider as a boot volume.
On first boot the machine gets a unique machine-id and freshly generated SSH
host keys, brings up networking via DHCP, and starts sshd.

## Repository layout

| Path | Purpose |
| --- | --- |
| `mkosi.conf` | main image definition (distro, packages, bootloaders) |
| `mkosi.conf.d/` | per-architecture drop-ins (kernel, BIOS GRUB) |
| `mkosi.postinst.chroot` | enables the minimal service set, strips per-machine state |
| `mkosi.extra/` | files copied verbatim into the image (network, sshd, units) |
| `.github/workflows/build-image.yml` | CI build + release pipeline |
