#!/usr/bin/env -S bash -e

# Cleaning the TTY.
clear

# Selecting a kernel to install. 
kernel_selector () {
    echo "List of kernels:"
    echo "1) Stable — Vanilla Linux kernel and modules, with a few patches applied."
    echo "2) Hardened — A security-focused Linux kernel."
    echo "3) Longterm — Long-term support (LTS) Linux kernel and modules."
    echo "4) Zen Kernel — Optimized for desktop usage."
    read -r -p "Insert the number of the corresponding kernel: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) kernel=linux
            ;;
        2 ) kernel=linux-hardened
            ;;
        3 ) kernel=linux-lts
            ;;
        4 ) kernel=linux-zen
            ;;
        * ) echo "You did not enter a valid selection."
            kernel_selector
    esac
}

# Selecting a way to handle internet connection. 
network_selector () {
    echo "Network utilities:"
    echo "1) IWD — iNet wireless daemon is a wireless daemon for Linux written by Intel (WiFi-only)."
    echo "2) NetworkManager — Program for providing detection and configuration for systems to automatically connect to networks (both WiFi and Ethernet)."
    echo "3) wpa_supplicant — It's a cross-platform supplicant with support for WEP, WPA and WPA2 (WiFi-only, a DHCP client will be automatically installed too.)"
    echo "4) I will do this on my own."
    read -r -p "Insert the number of the corresponding kernel: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) echo "Installing IWD."    
            pacstrap /mnt iwd
            echo "Enabling IWD."
            systemctl enable iwd --root=/mnt &>/dev/null
            ;;
        2 ) echo "Installing NetworkManager."
            pacstrap /mnt networkmanager
            echo "Enabling NetworkManager."
            systemctl enable NetworkManager --root=/mnt &>/dev/null
            ;;
        3 ) echo "Installing wpa_supplicant and dhcpcd."
            pacstrap /mnt wpa_supplicant dhcpcd
            echo "Enabling wpa_supplicant and dhcpcd."
            systemctl enable wpa_supplicant --root=/mnt &>/dev/null
            systemctl enable dhcpcd --root=/mnt &>/dev/null
            ;;
        4 )
            ;;
        * ) echo "You did not enter a valid selection."
            network_selector
    esac
}

# Checking the microcode to install.
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]
then
    microcode=amd-ucode
else
    microcode=intel-ucode
fi

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
    wipefs -af "$DISK" &>/dev/null
    sgdisk -Zo "$DISK" &>/dev/null
else
    echo "Quitting."
    exit
fi

# Creating a new partition scheme.
echo "Creating new partition scheme on $DISK."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart Cryptroot 513MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
Cryptroot="/dev/disk/by-partlabel/Cryptroot"

# Informing the Kernel of the changes.
echo "Informing the Kernel about the disk changes."
partprobe "$DISK"

# Formatting the ESP as FAT32.
echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP &>/dev/null

# Creating a LUKS Container for the root partition.
echo "Creating LUKS Container for the root partition"
cryptsetup luksFormat $Cryptroot
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

# Mounting the newly created subvolumes.
umount /mnt
echo "Mounting the newly created subvolumes."
mount -o ssd,noatime,space_cache,compress=zstd,subvol=@ $BTRFS /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,boot}
mount -o ssd,noatime,space_cache.compress=zstd,autodefrag,discard=async,subvol=@home $BTRFS /mnt/home
mount -o ssd,noatime,space_cache,compress=zstd,autodefrag,discard=async,subvol=@snapshots $BTRFS /mnt/.snapshots
mount -o ssd,noatime,space_cache,compress=zstd,autodefrag,discard=async,subvol=@var_log $BTRFS /mnt/var/log
chattr +C /mnt/var/log
mount $ESP /mnt/boot/

kernel_selector

# Pacstrap (setting up a base sytem onto the new root).
echo "Installing the base system (it may take a while)."
pacstrap /mnt base $kernel $microcode linux-firmware btrfs-progs grub grub-btrfs efibootmgr snapper sudo

# Generating /etc/fstab.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting hostname.
read -r -p "Please enter the hostname: " hostname
echo "$hostname" > /mnt/etc/hostname

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

# Configuring /etc/mkinitcpio.conf.
echo "Configuring /etc/mkinitcpio.conf for LUKS hook."
sed -i -e 's,modconf block filesystems keyboard,keyboard keymap modconf block encrypt filesystems,g' /mnt/etc/mkinitcpio.conf

# Setting up LUKS Keyfile, BTRFS Booting and encryption in GRUB and initramfs.
UUID=$(blkid $Cryptroot | cut -f2 -d'"')
sed -i "s,quiet,quiet cryptdevice=UUID=$UUID:cryptroot root=$BTRFS,g" /mnt/etc/default/grub

# Security kernel settings.
echo "kernel.kptr_restrict = 2" > /mnt/etc/sysctl.d/51-kptr-restrict.conf
echo "kernel.kexec_load_disabled = 1" > /mnt/etc/sysctl.d/51-kexec-restrict.conf
cat << EOF >> /mnt/etc/sysctl.d/10-security.conf
    fs.protected_hardlinks = 1
    fs.protected_symlinks = 1
    net.core.bpf_jit_harden = 2
    kernel.yama.ptrace_scope = 3
EOF

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    
    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null
    
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
    grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=GRUB &>/dev/null
    
    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null

EOF

# Setting root password.
echo "Setting root password."
arch-chroot /mnt /bin/passwd

# Enabling Snapper automatic snapshots.
echo "Enabling Snapper."
systemctl enable snapper-timeline.timer --root=/mnt &>/dev/null
systemctl enable snapper-cleanup.timer --root=/mnt &>/dev/null

echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
