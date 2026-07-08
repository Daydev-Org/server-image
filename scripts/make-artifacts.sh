#!/usr/bin/env bash
# Convert the mkosi raw disk image into the shipped VM disk formats.
#
#   .img   raw disk image (BIOS + UEFI bootable, identical bytes to the .raw)
#   .qcow2 QEMU/KVM/libvirt (compressed)
#   .vmdk  VMware / VirtualBox (streamOptimized, compressed, also used by the OVA)
#   .vhd   Hyper-V Gen1 / older Azure (dynamic VPC)
#   .vhdx  Hyper-V Gen2
#
# Usage: scripts/make-artifacts.sh <arch>
set -euo pipefail

ARCH="${1:?usage: make-artifacts.sh <arch>}"
OUTDIR="mkosi.output"
BASE="daydev-server-${ARCH}"

cd "$OUTDIR"
RAW="$(ls -- *.raw)"
echo ">> source image: $RAW"

# Virtual (unallocated) size in bytes — needed by the OVA descriptor.
VSIZE="$(qemu-img info --output=json "$RAW" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')"
echo ">> virtual size: $VSIZE bytes"

echo ">> [1/5] raw .img"
cp -f "$RAW" "${BASE}.img"

echo ">> [2/5] qcow2"
qemu-img convert -p -f raw -O qcow2 -c "$RAW" "${BASE}.qcow2"

echo ">> [3/5] vmdk (streamOptimized)"
qemu-img convert -p -f raw -O vmdk -o subformat=streamOptimized "$RAW" "${BASE}.vmdk"

echo ">> [4/5] vhd (dynamic)"
qemu-img convert -p -f raw -O vpc -o subformat=dynamic "$RAW" "${BASE}.vhd"

echo ">> [5/5] vhdx"
qemu-img convert -p -f raw -O vhdx "$RAW" "${BASE}.vhdx"

# Build the OVA from the streamOptimized VMDK produced above.
"${GITHUB_WORKSPACE:-..}/scripts/make-ova.sh" "$ARCH" "$VSIZE"

echo ">> conversions complete:"
ls -lh "${BASE}".{img,qcow2,vmdk,vhd,vhdx,ova} 2>/dev/null || true
