#!/bin/bash

# Function to add fstab entry
add_fstab_entry() {
    local device=$1
    local mount_point=$2
    local fs_type=$3
    local options="defaults"
    local dump=0
    local pass=2

    # Check if the entry already exists in /etc/fstab
    if ! grep -q "$device" /etc/fstab; then
        echo "Adding $device to /etc/fstab"
        echo "$device $mount_point $fs_type $options $dump $pass" | sudo tee -a /etc/fstab
    else
        echo "$device is already in /etc/fstab"
    fi
}

# Resize partitions
lsblk
echo "Ensure the drive is sda4 or modify the script accordingly"
sudo growpart /dev/sda 4
sudo pvresize /dev/sda4

# Resize existing logical volumes
sudo lvresize -r -L +49G /dev/mapper/rootvg-homelv
sudo lvresize -r -L +12G /dev/mapper/rootvg-varlv
sudo lvresize -r -L +38G /dev/mapper/rootvg-rootlv

# Create and configure new logical volumes
declare -A lvs=(
    ["/data"]="20G"
    ["/var/log"]="10G"
    ["/var/lib/docker"]="100G"
    ["/var/openebs"]="232G"
    ["/var/log/audit"]="5G"
    ["/var/log/kube-audit"]="5G"
)

for mount_point in "${!lvs[@]}"; do
    lv_name=$(basename "$mount_point")
    lv_path="/dev/mapper/rootvg-${lv_name}lv"

    echo "Creating logical volume $lv_name..."
    sudo lvcreate -L "${lvs[$mount_point]}" -n "${lv_name}lv" rootvg
    sudo mkfs.xfs "$lv_path"

    echo "Creating mount point $mount_point..."
    sudo mkdir -p "$mount_point"
    sudo mount "$lv_path" "$mount_point"

    # Add to /etc/fstab
    add_fstab_entry "$lv_path" "$mount_point" "xfs"
done

# Verify the entries in /etc/fstab
echo "Current /etc/fstab:"
cat /etc/fstab

# Test the changes
echo "Testing mounts with mount -a"
sudo mount -a

echo "Script execution completed. Logical volumes are set up and persistent across reboots."
