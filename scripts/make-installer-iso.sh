#!/usr/bin/env bash
# Build a bootable installer ISO (hybrid BIOS + UEFI) from the raw disk image.
#
# A GPT disk image cannot simply be renamed to an ISO, so this builds a tiny
# RAM-disk installer instead:
#
#   * the kernel and its modules are taken from the freshly built image;
#   * a busybox-based initramfs embeds the whole OS image (gzip-compressed) and
#     an /init that writes it to a target disk with dd, then reboots;
#   * grub-mkrescue wraps kernel + initramfs into an El-Torito ISO that boots on
#     both legacy BIOS and UEFI.
#
# On boot the ISO loads entirely into RAM, lists the disks, and — after a
# confirmation (or a `daydev.target=/dev/sdX` kernel argument for unattended
# installs) — clones the image onto the chosen disk.
#
# x86-64 only. Usage: scripts/make-installer-iso.sh <arch>   (needs sudo, Linux)
set -euo pipefail

ARCH="${1:?usage: make-installer-iso.sh <arch>}"
if [ "$ARCH" != "x86-64" ]; then
  echo "::notice::Installer ISO is only built for x86-64; skipping for $ARCH."
  exit 0
fi

OUTDIR="mkosi.output"
BASE="daydev-server-${ARCH}"
ISO="${BASE}-installer.iso"

cd "$OUTDIR"
RAW="$(ls -- *.raw)"
echo ">> source image: $RAW"

WORK="$(mktemp -d)"
MNT="$(mktemp -d)"
LOOP="$(sudo losetup -Pf --show "$RAW")"
cleanup() {
  sudo umount "$MNT" 2>/dev/null || true
  sudo losetup -d "$LOOP" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- locate the root partition and the kernel it carries -------------------
ROOTPART=""
for part in "${LOOP}"p*; do
  sudo mount -o ro "$part" "$MNT" 2>/dev/null || continue
  if [ -d "$MNT/usr/lib/modules" ]; then ROOTPART="$part"; break; fi
  sudo umount "$MNT"
done
[ -n "$ROOTPART" ] || { echo "!! could not find root partition in $RAW"; exit 1; }

KVER="$(sudo ls "$MNT/usr/lib/modules" | head -n1)"
echo ">> kernel version: $KVER  (root partition: $ROOTPART)"

KERNEL=""
for cand in "$MNT/boot/vmlinuz-$KVER" "$MNT/usr/lib/modules/$KVER/vmlinuz"; do
  [ -f "$cand" ] && { KERNEL="$cand"; break; }
done
[ -n "$KERNEL" ] || { echo "!! kernel image not found for $KVER"; exit 1; }

# --- assemble the installer initramfs --------------------------------------
IR="$WORK/initramfs"
mkdir -p "$IR"/{bin,dev,proc,sys,mnt,payload,lib/modules,etc}

# busybox provides sh, dd, gzip/zcat, mount, modprobe, lsblk, reboot, ...
cp "$(command -v busybox)" "$IR/bin/busybox"

# kernel modules (so the installer can see SATA/NVMe/virtio/USB disks)
sudo cp -a "$MNT/usr/lib/modules/$KVER" "$IR/lib/modules/"

# the OS image itself, gzip-compressed so the RAM footprint stays small
echo ">> embedding payload (gzip)…"
gzip -c "$RAW" > "$IR/payload/disk.img.gz"

cat > "$IR/init" <<'INIT'
#!/bin/busybox sh
export PATH=/bin
/bin/busybox --install -s /bin

mount -t proc     proc /proc
mount -t sysfs    sys  /sys
mount -t devtmpfs dev  /dev 2>/dev/null || mdev -s

echo ">> loading storage drivers…"
for m in ahci ata_piix libata sd_mod sr_mod nvme nvme_core \
         virtio_blk virtio_pci virtio_scsi vmw_pvscsi mptspi mptsas \
         hv_storvsc xhci_pci ehci_pci uhci_hcd usb_storage uas; do
    modprobe "$m" 2>/dev/null || true
done
sleep 3

# Optional unattended target from the kernel command line: daydev.target=/dev/sdX
TARGET=""
for arg in $(cat /proc/cmdline); do
    case "$arg" in daydev.target=*) TARGET="${arg#daydev.target=}";; esac
done

echo
echo "=================  DayDev Server Installer  ================="
echo "Detected block devices:"
lsblk -dno NAME,SIZE,MODEL 2>/dev/null || cat /proc/partitions
echo "============================================================"

if [ -z "$TARGET" ]; then
    printf "Enter target disk to ERASE and install onto (e.g. /dev/sda): "
    read TARGET
    printf "This will DESTROY all data on %s. Type YES to continue: " "$TARGET"
    read confirm
    [ "$confirm" = "YES" ] || { echo "Aborted."; exec sh; }
fi

if [ ! -b "$TARGET" ]; then
    echo "!! $TARGET is not a block device. Dropping to a shell."
    exec sh
fi

echo ">> writing image to $TARGET …"
zcat /payload/disk.img.gz | dd of="$TARGET" bs=4M
sync
blockdev --rereadpt "$TARGET" 2>/dev/null || true

echo
echo ">> Installation complete. Remove the installer media and reboot."
printf "Reboot now? [Y/n]: "
read ans
case "$ans" in n*|N*) exec sh;; *) reboot -f;; esac
INIT
chmod +x "$IR/init"

# pack the initramfs (uncompressed cpio; grub loads it, kernel unpacks to RAM)
echo ">> packing initramfs…"
( cd "$IR" && find . -print0 | cpio --null -o -H newc ) | gzip -1 > "$WORK/initrd.img"

# --- build the hybrid ISO with GRUB ----------------------------------------
ISODIR="$WORK/iso"
mkdir -p "$ISODIR/boot/grub"
cp "$KERNEL" "$ISODIR/boot/vmlinuz"
cp "$WORK/initrd.img" "$ISODIR/boot/initrd.img"

cat > "$ISODIR/boot/grub/grub.cfg" <<'GRUBCFG'
set timeout=10
set default=0
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial

menuentry "Install DayDev Server (to internal disk)" {
    linux  /boot/vmlinuz console=tty0 console=ttyS0,115200
    initrd /boot/initrd.img
}
menuentry "Install DayDev Server (serial console only)" {
    linux  /boot/vmlinuz console=ttyS0,115200
    initrd /boot/initrd.img
}
GRUBCFG

echo ">> running grub-mkrescue…"
grub-mkrescue \
    --modules="part_gpt part_msdos fat ext2 normal linux echo all_video test true search" \
    -o "$ISO" "$ISODIR"

echo ">> installer ISO ready: $ISO"
ls -lh "$ISO"
