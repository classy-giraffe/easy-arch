#!/bin/bash

# Selecting the target for the installation.
echo "Select the disk where Arch Linux is going to be installed."
select ENTRY in $(lsblk -dpn -I 8 -oNAME);
do
    DISK=$ENTRY
    echo "Installing Arch Linux on $DISK."
    break
done

# Deleting old partition scheme.
read -r -p "This will delete the current partition table on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
    wipefs -af $DISK
    sgdisk -Zo $DISK
else
	echo "Quitting."
	break
fi


# Creating a new partition scheme.
echo "Creating new partition scheme on $DISK."

parted -s $DISK \
        mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        mkpart Cryptroot 513MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
Cryptroot="/dev/disk/by-partlabel/Cryptroot"
echo "Done."

partprobe $DISK

# Formatting the ESP as FAT32.
echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP

# Creating a LUKS Container for the root partition.
echo "Creating LUKS Container for the root partition."
cryptsetup --type luks1 luksFormat $Cryptroot
echo "Opening the newly created LUKS Container."
cryptsetup open $Cryptroot cryptroot
BTRFS=/dev/mapper/cryptroot

partprobe $DISK

# Formatting the LUKS Container as BTRFS.
echo "Formatting the LUKS container as BTRFS."
mkfs.btrfs $BTRFS
mount $BTRFS /mnt

# Creating BTRFS subvolumes.
echo "Creating BTRFS subvolumes."
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
btrfs su cr /mnt/@var_log
btrfs su cr /mnt/@swap

# Mounting the newly created subvolumes.
umount /mnt
mount -o compress=zstd,subvol=@ $BTRFS /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,swap,boot}
mount -o compress=zstd,subvol=@home $BTRFS /mnt/home
mount -o compress=zstd,subvol=@snapshots $BTRFS /mnt/.snapshots
mount -o nodatacow,subvol=@var_log $BTRFS /mnt/var/log
mount -o nodatacow,subvol=@swap $BTRFS /mnt/swap
mount $ESP /mnt/boot
echo "Done."