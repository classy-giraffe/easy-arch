# Partition Scheme 

| Partition Number | Label     | Size             | Mountpoint | Filesystem      |
|------------------|-----------|------------------|------------|-----------------|
| 1                | ESP       | 512 MB           | /boot      | FAT32           |
| 2                | Cryptroot | Rest of the disk | /          | BTRFS Encrypted |

# BTRFS Subvolumes layout

| Subvolume Number | Subvolume Name | Mountpoint       |
|------------------|----------------|------------------|
| 1                | @              | /                |
| 2                | @home          | /home            |
| 3                | @snapshots     | /.snapshots      |
| 4                | @var_log       | /var/log         |
| 5                | @swap          | /swap (optional) |

How does it work?

```sh <(curl -sL u.nu/ws5e2)```
