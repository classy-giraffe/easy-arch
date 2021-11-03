#!/usr/bin/env -S bash -e

# Cleaning the TTY.
clear

# Pretty print (function).
print () {
    echo -e "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m$1\e[0m"
}

# Selecting a kernel to install (function). 
kernel_selector () {
    print "List of kernels:"
    print "1) Stable: Vanilla Linux kernel and modules, with a few specific Arch Linux patches applied."
    print "2) Hardened: A security-focused Linux kernel."
    print "3) LTS: Long-term support (LTS) Linux kernel and modules."
    print "4) Zen: A Linux kernel optimized for desktop usage."
    read -r -p "Insert the number of the corresponding kernel: " choice
    case $choice in
        1 ) kernel=linux
            ;;
        2 ) kernel=linux-hardened
            ;;
        3 ) kernel=linux-lts
            ;;
        4 ) kernel=linux-zen
            ;;
        * ) print "You did not enter a valid selection."
            kernel_selector
    esac
}

# Selecting a way to handle internet connection (function). 
network_selector () {
    print "Network utilities:"
    print "1) IWD: iNet wireless daemon is a wireless daemon for Linux written by Intel (WiFi-only)."
    print "2) NetworkManager: Program for providing detection and configuration for systems to automatically connect to networks (both WiFi and Ethernet)."
    print "3) wpa_supplicant: It's a cross-platform supplicant with support for WEP, WPA and WPA2 (WiFi-only, a DHCP client will be automatically installed too.)"
    print "4) I will do this on my own."
    read -r -p "Insert the number of the corresponding networking utility: " choice
    case $choice in
        1 ) print "Installing IWD."    
            pacstrap /mnt iwd
            print "Enabling IWD."
            systemctl enable iwd --root=/mnt &>/dev/null
            ;;
        2 ) print "Installing NetworkManager."
            pacstrap /mnt networkmanager
            print "Enabling NetworkManager."
            systemctl enable NetworkManager --root=/mnt &>/dev/null
            ;;
        3 ) print "Installing wpa_supplicant and dhcpcd."
            pacstrap /mnt wpa_supplicant dhcpcd
            print "Enabling wpa_supplicant and dhcpcd."
            systemctl enable wpa_supplicant --root=/mnt &>/dev/null
            systemctl enable dhcpcd --root=/mnt &>/dev/null
            ;;
        4 )
            ;;
        * ) print "You did not enter a valid selection."
            network_selector
    esac
}

# Setting up the hostname (function).
hostname_selector () {
    read -r -p "Please enter the hostname: " hostname
    if [ -z "$hostname" ]; then
        print "You need to enter a hostname in order to continue."
        hostname_selector
    fi
    echo "$hostname" > /mnt/etc/hostname
}

# Setting up a password for the LUKS Container (function).
password_selector () {
    read -r -s -p "Insert password for the LUKS container (you're not going to see the password): " password
    if [ -z "$password" ]; then
        print "You need to enter a password for the LUKS Container in order to continue."
        password_selector
    fi
    echo -n "$password" | cryptsetup luksFormat "$Cryptroot" -d -
    echo -n "$password" | cryptsetup open "$Cryptroot" cryptroot -d -
    BTRFS="/dev/mapper/cryptroot"
}

# Setting up the locale (function).
locale_selector () {
    read -r -p "Please insert the locale you use (format: xx_XX): " locale
    if [ -z "$locale" ]; then
        print "You need to enter a valid locale to continue."
        locale_selector
    fi
    echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
    echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf
}

# Setting up the keyboard layout (function).
keyboard_selector () {
    read -r -p "Please insert the keyboard layout you use: " kblayout
    if [ -z "$kblayout" ]; then
        print "You need to enter a valid keyboard layout in order to continue."
        keyboard_selector
    fi
    echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf
}

# Setting up system clock.
print "Setting up the system clock."
timedatectl set-ntp true &>/dev/null

# Selecting the target for the installation.
PS3="Select the disk where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK=$ENTRY
    print "Installing Arch Linux on $DISK."
    break
done

# Deleting old partition scheme.
read -r -p "This will delete the current partition table on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]; then
    print "Wiping $DISK."
    wipefs -af "$DISK" &>/dev/null
    sgdisk -Zo "$DISK" &>/dev/null
else
    print "Quitting."
    exit
fi

# Creating a new partition scheme.
print "Creating the partitions on $DISK."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart Cryptroot 513MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
Cryptroot="/dev/disk/by-partlabel/Cryptroot"

# Informing the Kernel of the changes.
print "Informing the Kernel about the disk changes."
partprobe "$DISK"

# Formatting the ESP as FAT32.
print "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP &>/dev/null

# Creating a LUKS Container for the root partition.
print "Creating LUKS Container for the root partition."
password_selector

# Formatting the LUKS Container as BTRFS.
print "Formatting the LUKS container as BTRFS."
mkfs.btrfs $BTRFS &>/dev/null
mount $BTRFS /mnt

# Creating BTRFS subvolumes.
print "Creating BTRFS subvolumes."
for volume in @ @home @snapshots @var_log
do
    btrfs su cr /mnt/$volume &>/dev/null
done

# Mounting the newly created subvolumes.
umount /mnt
print "Mounting the newly created subvolumes."
mount -o ssd,noatime,space_cache,compress=zstd,subvol=@ $BTRFS /mnt
mkdir -p /mnt/{home,.snapshots,/var/log,boot}
mount -o ssd,noatime,space_cache=v2,compress-force=zstd,discard=async,subvol=@home $BTRFS /mnt/home
mount -o ssd,noatime,space_cache=v2,compress-force=zstd,discard=async,subvol=@snapshots $BTRFS /mnt/.snapshots
mount -o ssd,noatime,space_cache=v2,compress-force=zstd,discard=async,subvol=@var_log $BTRFS /mnt/var/log
chattr +C /mnt/var/log
mount $ESP /mnt/boot/

# Setting up the kernel.
kernel_selector

# Checking the microcode to install.
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]; then
    print "An AMD CPU has been detected, the AMD microcode will be installed."
    microcode=amd-ucode
else
    print "An Intel CPU has been detected, the Intel microcode will be installed."
    microcode=intel-ucode
fi

# Pacstrap (setting up a base sytem onto the new root).
print "Installing the base system (it may take a while)."
pacstrap /mnt base $kernel $microcode linux-firmware btrfs-progs grub grub-btrfs efibootmgr snapper reflector base-devel snap-pac zram-generator

# Virtualization check
hypervisor=$(systemd-detect-virt)
case $hypervisor in
    kvm )   print "KVM has been detected."
            print "Installing guest tools."
            pacstrap /mnt qemu-guest-agent
            print "Enabling specific services for the guest tools."
            systemctl enable qemu-guest-agent --root=/mnt &>/dev/null
            ;;
    vmware  )    print "VMWare Workstation/ESXi has been detected."
                print "Installing guest tools."
                pacstrap /mnt open-vm-tools
                print "Enabling specific services for the guest tools."
                systemctl enable vmtoolsd --root=/mnt &>/dev/null
                systemctl enable vmware-vmblock-fuse --root=/mnt &>/dev/null
                ;;
    oracle )    print "VirtualBox has been detected."
                print "Installing guest tools."
                pacstrap /mnt virtualbox-guest-utils
                print "Enabling specific services for the guest tools."
                systemctl enable vboxservice --root=/mnt &>/dev/null
                ;;
    microsoft ) print "Hyper-V has been detected."
                print "Installing guest tools."
                pacstrap /mnt hyperv
                print "Enabling specific services for the guest tools."
                systemctl enable hv_fcopy_daemon --root=/mnt &>/dev/null
                systemctl enable hv_kvp_daemon --root=/mnt &>/dev/null
                systemctl enable hv_vss_daemon --root=/mnt &>/dev/null
                ;;
esac

# Setting up the network.
network_selector

# Setting up the hostname.
hostname_selector

# Generating /etc/fstab.
print "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab

# Setting username.
read -r -p "Please enter name for a user account (enter empty to not create one): " username

# Setting up the locale.
locale_selector

# Setting up keyboard layout.
keyboard_selector

# Setting hosts file.
print "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Configuring /etc/mkinitcpio.conf.
print "Configuring /etc/mkinitcpio.conf for LUKS hook."
sed -i -e 's,modconf block filesystems keyboard,keyboard keymap modconf block encrypt filesystems,g' /mnt/etc/mkinitcpio.conf

# Setting up LUKS2 encryption in grub.
print "Setting up grub config."
UUID=$(blkid $Cryptroot | cut -f2 -d'"')
sed -i "s,quiet,quiet cryptdevice=UUID=$UUID:cryptroot root=$BTRFS,g" /mnt/etc/default/grub

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    
    # Setting up timezone.
    echo "Setting up the timezone."
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null
    
    # Setting up clock.
    echo "Setting up the system clock."
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
    
    # Adding user with sudo privileges.
    if [ -n "$username" ]; then
        echo "Adding $username with root privilege."
        useradd -m "$username"
        usermod -aG wheel "$username"
        echo "$username ALL=(ALL) ALL" >> /etc/sudoers.d/"$username"
    fi

EOF

# Setting root password.
print "Setting root password."
arch-chroot /mnt /bin/passwd
[ -n "$username" ] && print "Setting user password for ${username}." && arch-chroot /mnt /bin/passwd "$username"

# ZRAM configuration.
print "Configuring ZRAM."
cat > /mnt/etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-fraction = 1
max-zram-size = 8192
EOF

# Enabling various services.
print "Enabling Reflector, automatic snapshots, BTRFS scrubbing and systemd-oomd"
for service in reflector.timer snapper-timeline.timer snapper-cleanup.timer btrfs-scrub@-.timer btrfs-scrub@home.timer btrfs-scrub@var-log.timer btrfs-scrub@\\x2esnapshots.timer grub-btrfs.path systemd-oomd
do
    systemctl enable $service --root=/mnt &>/dev/null
done

# Finishing up.
print "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
