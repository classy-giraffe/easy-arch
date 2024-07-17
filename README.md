![](https://img.shields.io/github/license/classy-giraffe/easy-arch?label=License)
![](https://img.shields.io/github/stars/classy-giraffe/easy-arch?label=Stars)
![](https://img.shields.io/github/forks/classy-giraffe/easy-arch?label=Forks)

[easy-arch](https://github.com/classy-giraffe/easy-arch) is a **bash script** that boostraps [Arch Linux](https://archlinux.org/) with sane opinionated defaults.

- **BTRFS snapshots**: you will have a resilient setup that automatically takes snapshots of your volumes based on a weekly schedule
- **LUKS2 encryption**: your data will live on a LUKS2 partition protected by a password
- **ZRAM**: the setup use ZRAM which aims to replace traditional swap partition/files by making the system snappier
- **systemd-oomd**: systemd-oomd will take care of OOM situations at userspace level rather than at kernel level, making the system less prone to kernel crashes 
- **VM additions**: the script automatically provides guest tools if it detects that a virtualized environment such as VMWare Workstation, VirtualBox, QEMU-KVM is being used
- **User account setup**: a default user account with sudo permissions can be configured in order to avoid hassle in the post installation phase
- **CI checks**: ShellChecker checks every PR periodically for bash syntax errors, bad coding practices, etc... 

## One-step Automated Install (shorter)

### `bash <(curl -sL bit.ly/easy-arch)`

## Alternative Methods (manual)

```bash 
wget -O easy-arch.sh https://raw.githubusercontent.com/classy-giraffe/easy-arch/main/easy-arch.sh
chmod +x easy-arch.sh
bash easy-arch.sh
```

## Partitions layout 

The **partitions layout** is simple and it consists solely of two partitions:
1. A **FAT32** partition (1GiB), mounted at `/boot/` as ESP.
2. A **LUKS2 encrypted container**, which takes the rest of the disk space, mounted at `/` as root.

| Partition Number | Label     | Size              | Mountpoint     | Filesystem              |
|------------------|-----------|-------------------|----------------|-------------------------|
| 1                | ESP       | 1 GiB              | /boot/         | FAT32                   |
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
