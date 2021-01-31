#!/bin/bash

# Exit on STDERR.
set -e

# Setting up the correct time.
timedatectl set-ntp true

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
	exit
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
echo "Mounting the newly created subvolumes."
mount -o compress=zstd,subvol=@ $BTRFS /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,swap,boot}
mount -o compress=zstd,subvol=@home $BTRFS /mnt/home
mount -o compress=zstd,subvol=@snapshots $BTRFS /mnt/.snapshots
mount -o nodatacow,subvol=@var_log $BTRFS /mnt/var/log
mount -o nodatacow,subvol=@swap $BTRFS /mnt/swap
mount $ESP /mnt/boot

# Pacstrap (setting up a base sytem onto the new root).
echo "Installing the base sytem."
pacstrap /mnt base linux linux-firmware btrfs-progs neovim networkmanager

# Fstab generation.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.
echo "Please enter the hostname: "
read hostname
echo $hostname > /mnt/etc/hostname

# Setting hosts file.
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Setting up locales.
echo "Please insert the locale you use in this format (xx_XX.UTF-8): "
read locale
echo $locale > /mnt/etc/locale.gen
echo "LANG=\"$locale\"" > /mnt/etc/locale.conf