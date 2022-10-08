![](https://img.shields.io/github/license/classy-giraffe/easy-arch?label=License)
![](https://img.shields.io/github/stars/classy-giraffe/easy-arch?label=Stars)
![](https://img.shields.io/github/forks/classy-giraffe/easy-arch?label=Forks)

[easy-arch](https://github.com/classy-giraffe/easy-arch) is a **bash script** that boostraps [Arch Linux](https://archlinux.org/) with sane defaults.

- **BTRFS snapshots**: you will have a resilient set up that will automatically takes snapshots of your volumes based on a weekly schedule
- **LUKS2 encryption**: your data will live on a LUKS2 partition protected by a password
- **ZRAM**: we use ZRAM which is a modern technology that allows us to use ram as a disk and swaps on it which is way faster than traditional swap
- **systemd-oomd**: systemd-oomd makes sure that OOM killing happens in the userspace rather than resorting to the traditional OOM killing which happens at kernel level
- **VM additions**: we aim to provide guest tools if we detect that you're installing Arch Linux on a virtualized environment such as VMWare Workstation, VirtualBox, QEMU-KVM etc...
- **User setup**: you'll be walked through the process of setting up a default user account with sudo permissions

## One-step Automated Install (shorter)

### `bash <(curl -sL bit.ly/easy-arch)`

## Alternative Methods (manual)

```bash 
wget -O easy-arch.sh https://raw.githubusercontent.com/classy-giraffe/easy-arch/main/easy-arch.sh
chmod +x easy-arch.sh
bash easy-arch.sh
```

## Partitions layout 

The **partitions layout** is simple and it consists of only two partitions:
1. A **FAT32** partition (512MiB), mounted at `/boot/` as ESP.
2. A **LUKS2 encrypted container**, which takes the rest of the disk space, mounted at `/` as root.

| Partition Number | Label     | Size              | Mountpoint     | Filesystem              |
|------------------|-----------|-------------------|----------------|-------------------------|
| 1                | ESP       | 512 MiB           | /boot/         | FAT32                   |
| 2                | Cryptroot | Rest of the disk  | /              | BTRFS Encrypted (LUKS2) |

## BTRFS subvolumes layout

The **BTRFS subvolumes layout** follows the traditional and suggested layout used by **Snapper**, you can find it [here](https://wiki.archlinux.org/index.php/Snapper#Suggested_filesystem_layout).

| Subvolume Number | Subvolume Name | Mountpoint                    |
|------------------|----------------|-------------------------------|
| 1                | @              | /                             |
| 2                | @home          | /home                         |
| 3                | @root          | /root                         |
| 4                | @srv           | /srv                          |
| 5                | @snapshots     | /.snapshots                   |
| 6                | @var_log       | /var/log                      |
| 7                | @var_pkgs      | /var/cache/pacman/pkg         |
