#!/usr/bin/env bash

# Cleaning the TTY.
clear

# Exit on STDERR.
set -e

# Selecting the target for the installation.
PS3="Select the disk where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
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
    wipefs -af $DISK &>/dev/null
    sgdisk -Zo $DISK &>/dev/null
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

# Informing the Kernel of the changes.
echo "Informing the Kernel about the disk changes."
partprobe $DISK

# Formatting the ESP as FAT32.
echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP &>/dev/null

# Creating a LUKS Container for the root partition.
echo "Creating LUKS Container for the root partition."
cryptsetup --type luks1 luksFormat $Cryptroot
echo "Opening the newly created LUKS Container."
cryptsetup open $Cryptroot cryptroot
BTRFS="/dev/mapper/cryptroot"

# Formatting the LUKS Container as BTRFS.
echo "Formatting the LUKS container as BTRFS."
mkfs.btrfs $BTRFS &>/dev/null
mount $BTRFS /mnt

# Creating BTRFS subvolumes.
echo "Creating BTRFS subvolumes."
btrfs su cr /mnt/@ &>/dev/null
btrfs su cr /mnt/@home &>/dev/null
btrfs su cr /mnt/@snapshots &>/dev/null
btrfs su cr /mnt/@var_log &>/dev/null
btrfs su cr /mnt/@swap &>/dev/null

# Mounting the newly created subvolumes.
umount /mnt
echo "Mounting the newly created subvolumes."
mount -o ssd,noatime,space_cache,compress=zstd,subvol=@ $BTRFS /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,swap,boot}
mount -o ssd,noatime,space_cache.compress=zstd,subvol=@home $BTRFS /mnt/home
mount -o ssd,noatime,space_cache,compress=zstd,subvol=@snapshots $BTRFS /mnt/.snapshots
mount -o ssd,noatime,space_cache,nodatacow,subvol=@var_log $BTRFS /mnt/var/log
mount -o nodatacow,subvol=@swap $BTRFS /mnt/swap
mount $ESP /mnt/boot

# Pacstrap (setting up a base sytem onto the new root).
echo "Installing the base system (it may take a while)."
pacstrap /mnt base linux linux-firmware btrfs-progs grub grub-btrfs efibootmgr snapper sudo networkmanager

# Generating /etc/fstab.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.
read -r -p "Please enter the hostname: " hostname
echo $hostname > /mnt/etc/hostname

# Setting up locales.
read -r -p "Please insert the locale you use (format: xx_XX): " locale
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

# Setting up keyboard layout.
read -r -p "Please insert the keyboard layout you use: " kblayout
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

# Setting hosts file.
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Configuring /etc/mkinitcpio.conf
echo "Configuring /etc/mkinitcpio for ZSTD compression and LUKS hook."
sed -i -e 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /mnt/etc/mkinitcpio.conf
sed -i -e 's,modconf block filesystems keyboard,keyboard keymap modconf block encrypt filesystems,g' /mnt/etc/mkinitcpio.conf

# Enabling LUKS in GRUB and setting the UUID of the LUKS container.
UUID=$(blkid $Cryptroot | cut -f2 -d'"')
sed -i 's/#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /mnt/etc/default/grub
sed -i -e "s,quiet,quiet cryptdevice=UUID=$UUID:cryptroot root=$BTRFS,g" /mnt/etc/default/grub

# Creating a swapfile.
read -r -p "Do you want a swapfile? [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
    read -r -p "How much big should the swap file be? Type the size, just a number (eg: 1 = 1GB..): " swap
    truncate -s 0 /mnt/swap/swapfile
    chattr +C /mnt/swap/swapfile
    btrfs property set /mnt/swap/swapfile compression none &>/dev/null
    dd if=/dev/zero of=/mnt/swap/swapfile bs=1G count=$swap &>/dev/null
    chmod 600 /mnt/swap/swapfile
    mkswap /mnt/swap/swapfile &>/dev/null
    swapon /mnt/swap/swapfile &>/dev/null
    echo "/swap/swapfile    none    swap    defaults    0   0" >> /mnt/etc/fstab
else
    # Removing swap subvolumes and fstab entry in case it's not needed.
    echo "Deleting BTRFS swap subvolume."
    mount $BTRFS -o subvolid=5 /home
    head -n -4 /home/@/etc/fstab > /home/@/etc/new_fstab && mv /home/@/etc/new_fstab /home/@/etc/fstab
    btrfs su de /home/@swap &>/dev/null
    umount -R /home
    echo "No swapfile has been added."
fi

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    
    # Setting up timezone.
    timedatectl set-timezone "$(curl http://ip-api.com/line?fields=timezone)"
    
    # Setting up clock.
    hwclock --systohc

    # Generating locales.
    echo "Generating locales."
    locale-gen &>/dev/null

    # Generating a new initramfs.
    echo "Creating a new initramfs."
    mkinitcpio -P &>/dev/null

    # Snapper configuration
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots &>/dev/null
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots

    # Installing GRUB.
    echo "Installing GRUB on /boot."
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB &>/dev/null

    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

# Setting root password.
echo "Setting root password."
arch-chroot /mnt /bin/passwd

# Enabling NetworkManager service.
echo "Enabling NetworkManager."
systemctl enable NetworkManager --root=/mnt &>/dev/null

# Enabling Snapper automatic snapshots.
echo "Enabling Snapper."
systemctl enable snapper-timeline.timer --root=/mnt &>/dev/null
systemctl enable snapper-cleanup.timer --root=/mnt &>/dev/null

echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
