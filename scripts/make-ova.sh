#!/usr/bin/env bash
# Package the streamOptimized VMDK into an OVA (Open Virtualization Appliance).
#
# An OVA is just a tar archive, in a specific order, of:
#   1. <name>.ovf   the descriptor (must come first)
#   2. <name>.vmdk  the streamOptimized disk
#   3. <name>.mf    the manifest with SHA256 sums
#
# The descriptor below describes a generic 2 vCPU / 2 GiB Linux VM with an
# LSI Logic SCSI controller and one disk; it imports into both VMware
# (Workstation/ESXi/vSphere) and VirtualBox.
#
# Usage: scripts/make-ova.sh <arch> <virtual-size-bytes>   (run from mkosi.output)
set -euo pipefail

ARCH="${1:?usage: make-ova.sh <arch> <vsize-bytes>}"
CAPACITY="${2:?missing virtual size in bytes}"
BASE="daydev-server-${ARCH}"
VMNAME="daydev-server-${ARCH}"

VMDK="${BASE}.vmdk"
OVF="${BASE}.ovf"
MF="${BASE}.mf"
OVA="${BASE}.ova"

[ -f "$VMDK" ] || { echo "!! $VMDK not found (run make-artifacts.sh first)"; exit 1; }
VMDK_SIZE="$(stat -c%s "$VMDK")"

echo ">> writing OVF descriptor ($OVF)"
cat > "$OVF" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope vmw:buildId="build-1"
    xmlns="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
    xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
    xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
    xmlns:vmw="http://www.vmware.com/schema/ovf"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="${VMDK}" ovf:id="file1" ovf:size="${VMDK_SIZE}"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="${CAPACITY}" ovf:capacityAllocationUnits="byte"
          ovf:diskId="vmdisk1" ovf:fileRef="file1"
          ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="VM Network">
      <Description>The VM Network network</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="${VMNAME}">
    <Info>A DayDev minimal Debian server</Info>
    <Name>${VMNAME}</Name>
    <OperatingSystemSection ovf:id="96" vmw:osType="debian12_64Guest">
      <Info>The kind of installed guest operating system</Info>
      <Description>Debian GNU/Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${VMNAME}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-14</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>2048 MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:ElementName>SCSI Controller 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>7</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>VM Network</rasd:Connection>
        <rasd:ElementName>Ethernet 1</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
EOF

echo ">> writing manifest ($MF)"
{
  printf 'SHA256(%s)= %s\n' "$OVF"  "$(sha256sum "$OVF"  | cut -d' ' -f1)"
  printf 'SHA256(%s)= %s\n' "$VMDK" "$(sha256sum "$VMDK" | cut -d' ' -f1)"
} > "$MF"

echo ">> packing $OVA"
# Order matters: descriptor first, then disk, then manifest.
tar -cf "$OVA" --format=ustar "$OVF" "$VMDK" "$MF"

# The .ovf/.mf are only intermediates for the tarball.
rm -f "$OVF" "$MF"
echo ">> OVA ready: $OVA"
