### Introduction
[easy-arch](https://github.com/classy-giraffe/easy-arch) is a **script** made in order to boostrap a basic **Arch Linux** environment with **snapshots** and **encryption** by using a fully automated process.

### How does it work?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Set the keyboard layout by using `loadkeys`.
5. Connect to the internet.
6. Run this `sh <(curl -sL u.nu/ws5e2)`.

### Partitions layout 

| Partition Number | Label     | Size              | Mountpoint | Filesystem             |
|------------------|-----------|-------------------|------------|------------------------|
| 1                | ESP       | 512 MiB           | /boot      | FAT32                  |
| 2                | Cryptroot | Rest of the disk  | /          | BTRFS Encrypted (LUKS) |

The **partitions layout** is pretty straightforward, it's inspired by [this section](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap) of the Arch Wiki. As you can see there's just a couple of partitions:
1. A **FAT32**, 512MiB sized, mounted at `/boot` for the ESP.
2. A **LUKS encrypted container**, which takes the rest of the disk mounted at `/` for the rootfs.

### BTRFS subvolumes layout

| Subvolume Number | Subvolume Name | Mountpoint       |
|------------------|----------------|------------------|
| 1                | @              | /                |
| 2                | @home          | /home            |
| 3                | @snapshots     | /.snapshots      |
| 4                | @var_log       | /var/log         |
| 5                | @swap          | /swap (optional) |

The **BTRFS subvolumes layout** follows the traditional and suggested layout used by **Snapper**, you can find it [here](https://wiki.archlinux.org/index.php/Snapper#Suggested_filesystem_layout). I only added a swap subvolume in case you need a swapfile, but it's totally optional. You'll be asked if you want it or not during the script execution. Here's a brief explanation of the **BTRFS layout** I chose:
1. `@` mounted as `/`.
2. `@home` mounted as `/home`.
3. `@snapshots` mounted as `/.snapshots`.
4. `@var_log` mounted as `/var/log`.
5. `@swap` mounted as `/swap` (_optional_).
