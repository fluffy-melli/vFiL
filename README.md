> [!CAUTION]
> This bootloader does not support LVM yet.
>
> Booting an OS installed on LVM may fail or cause unexpected behavior.

> [!CAUTION]
> This bootloader does not support Secure Boot yet.
>
> Disable Secure Boot in your firmware settings before using it. otherwise, the firmware may refuse to load the bootloader.

## Installation

Prepare `BOOTX64.efi` from the [Releases](https://github.com/fluffy-melli/vFiL/releases) page, or an `.efi` file you built yourself.

### Install to a USB drive

> [!WARNING]
> The commands below are examples that use `/dev/sda` and `/dev/sda1`.
>
> Check which device is yours (e.g., with `lsblk`) and adjust the commands accordingly.

```bash
sudo umount /dev/sda1

sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 100%
sudo parted /dev/sda -- set 1 esp on

sudo mkfs.fat -F 32 /dev/sda1

sudo mount /dev/sda1 /mnt

sudo mkdir -p /mnt/EFI/BOOT

sudo cp ./BOOTX64.efi /mnt/EFI/BOOT/BOOTX64.efi
# sudo cp ./zig-out/bin/BOOTX64.efi /mnt/EFI/BOOT/BOOTX64.efi

sudo umount /mnt
```

### Install to the EFI System Partition (ESP)

> [!WARNING]
> The commands below are examples that use `/dev/nvme0n1` and `partition 1 (/dev/nvme0n1p1)`.
>
> Check which device and partition are yours (e.g., with `lsblk -o NAME,FSTYPE,PARTUUID,SIZE,MOUNTPOINTS`) and adjust the commands accordingly.

```bash
sudo mkdir -p /boot/efi/EFI/vFiL

sudo cp ./BOOTX64.efi /boot/efi/EFI/vFiL/BOOTX64.efi
# sudo cp ./zig-out/bin/BOOTX64.efi /boot/efi/EFI/vFiL/BOOTX64.efi

sudo efibootmgr \
  --create \
  --disk /dev/nvme0n1 \
  --part 1 \
  --label "vFiL" \
  --loader '\EFI\vFiL\BOOTX64.efi'
```

## Build From Source

The default branch of vFiL targets [master](https://github.com/fluffy-melli/vFiL).

```bash
git clone https://github.com/fluffy-melli/vFiL
cd vFiL
zig build
```

## Third Party

> [!NOTE]
> This project bundles the following third-party binary.

- [`ext4_x64.efi`](https://github.com/fluffy-melli/vFiL/blob/main/asset/ext4_x64.efi): ext4 filesystem driver (x64), from [rEFInd](https://www.rodsbooks.com/refind/)
