https://github.com/classy-giraffe/easy-arch/actions/workflows/ISO-Builder.yml/badge.svg

### Introduction
[easy-arch](https://github.com/classy-giraffe/easy-arch) is a **script** made in order to boostrap a basic **Arch Linux** environment with **snapshots** and **encryption** by using a fully automated process (UEFI only).

### How does it work?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Set the keyboard layout by using `loadkeys`.
5. Connect to the internet.
6. Run this `bash <(curl -sL git.io/JtRu2)`.

### Partitions layout 

| Partition Number | Label     | Size              | Mountpoint     | Filesystem             |
|------------------|-----------|-------------------|----------------|------------------------|
| 1                | ESP       | 512 MiB           | /boot/efi      | FAT32                  |
| 2                | Cryptroot | Rest of the disk  | /              | BTRFS Encrypted (LUKS) |

The **partitions layout** is pretty straightforward, it's inspired by [this section](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap) of the Arch Wiki. As you can see there's just a couple of partitions:
1. A **FAT32**, 512MiB sized, mounted at `/boot/efi` for the ESP.
2. A **LUKS encrypted container**, which takes the rest of the disk space, mounted at `/` for the rootfs.

### BTRFS subvolumes layout

| Subvolume Number | Subvolume Name | Mountpoint       |
|------------------|----------------|------------------|
| 1                | @              | /                |
| 2                | @boot          | /boot            |
| 3                | @home          | /home            |
| 4                | @snapshots     | /.snapshots      |
| 5                | @var_log       | /var/log         |

The **BTRFS subvolumes layout** follows the traditional and suggested layout used by **Snapper**, you can find it [here](https://wiki.archlinux.org/index.php/Snapper#Suggested_filesystem_layout). Here's a brief explanation of the **BTRFS layout** I chose:
1. `@` mounted as `/`.
2. `@boot` mounted as `/boot`.
3. `@home` mounted as `/home`.
4. `@snapshots` mounted as `/.snapshots`.
5. `@var_log` mounted as `/var/log`.
