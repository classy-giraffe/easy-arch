#!/bin/bash

# Exit on STDERR.
set -e

# Setting up the correct time.
timedatectl set-ntp true

# Selecting the target for the installation.
echo "Select the disk where Arch Linux is going to be installed."
select ENTRY in $(lsblk -dpn -oNAME);
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
pacstrap /mnt base linux linux-firmware btrfs-progs grub grub-btrfs efibootmgr snapper neovim networkmanager

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
echo "$locale UTF-8"  > /mnt/etc/locale.gen
echo "LANG=\"$locale\"" > /mnt/etc/locale.conf

# Setting up keyboard layout.
echo "Please insert the keyboard layout you use: "
read kblayout
echo "KEYMAP=\"$kblayout\"" > /mnt/etc/vconsole.conf

# Configuring /etc/mkinitcpio.conf
echo "Configuring /etc/mkinitcpio for ZSTD compression, BTRFS and LUKS hook."
sed -i -e 's,BINARIES=(),BINARIES=(/usr/bin/btrfs),g' /mnt/etc/mkinitcpio.conf
sed -i -e 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /mnt/etc/mkinitcpio.conf
sed -i -e 's,modconf block filesystems keyboard,keyboard keymap modconf block encrypt filesystems,g' /mnt/etc/mkinitcpio.conf

# Enabling LUKS in GRUB.
UUID=$(blkid $Cryptroot | cut -f2 -d'"')
sed -i 's/#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /mnt/etc/default/grub
sed -i -e "s,quiet,quiet cryptdevice=UUID=$UUID:cryptroot root=$BTRFS,g" /mnt/etc/default/grub

# Creating a swapfile.
echo "How much big should the swap file be? Type the size, just a number (eg: 1 = 1GB..) "
read swap
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile
btrfs property set /mnt/swap/swapfile compression none
dd if=/dev/zero of=/mnt/swap/swapfile bs=1G count=$swap status=progress
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile
echo "/swap/swapfile    none    swap    defaults    0   0" >> /mnt/etc/fstab

# Configuring the system.    
arch-chroot /mnt /bin/bash -xe <<"EOF"
    
    # Setting up clock.
    hwclock --systohc

    # Generating locales.
    locale-gen

    # Generating a new initramfs.
    mkinitcpio -P

    # Installing Grub.
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    # Creating grub config file.
    grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Setting root password.
print "Setting root password."
arch-chroot /mnt /bin/passwd

# Enabling auto-trimming.
echo "Enabling auto-trimming."
systemctl enable fstrim.timer --root=/mnt

# Enabling NetworkManager.
echo "Enabling NetworkManager."
systemctl enable NetworkManager --root=/mnt

# Unmounting partitions.
umount -R /mnt
echo "Done."
exit
