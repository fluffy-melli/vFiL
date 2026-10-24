> [!CAUTION]
> LVM is not supported yet.
>
> Booting an OS installed on LVM may fail or cause unexpected behavior.

## Installation

Download `MOK.cer`, `ext4_x64.efi`, and `BOOTX64.efi` from the [Releases](https://github.com/fluffy-melli/vFiL/releases) page, or use files you built yourself.

> [!IMPORTANT]
> To boot with Secure Boot enabled, you must first allow `MOK.cer` in your motherboard firmware (BIOS/UEFI) settings.
>
> The Linux kernel must also be trusted: either sign it with `MOK.cer`, or allow its Linux CA certificate in the firmware.

### Install to a USB drive

> [!WARNING]
> The commands below are examples that use `/dev/sda` and `/dev/sda1`.
>
> Run `lsblk` to identify your USB drive and adjust the device names accordingly. **These commands erase the existing partition table and filesystem on the selected drive.** Double-check the device before proceeding.

```bash
sudo umount /dev/sda1

sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart ESP fat32 1MiB 100%
sudo parted /dev/sda -- set 1 esp on

sudo mkfs.fat -F 32 /dev/sda1

sudo mount /dev/sda1 /mnt

sudo mkdir -p /mnt/EFI/BOOT
sudo mkdir -p /mnt/EFI/DRIVERS

sudo cp ./MOK.cer /mnt/EFI/BOOT/MOK.cer

sudo cp ./BOOTX64.efi /mnt/EFI/BOOT/BOOTX64.efi
# If you built it yourself:
# sudo cp ./zig-out/bin/BOOTX64.efi /mnt/EFI/BOOT/BOOTX64.efi

sudo cp ./ext4_x64.efi /mnt/EFI/DRIVERS/ext4_x64.efi
# If you built it yourself:
# sudo cp ./zig-out/bin/ext4_x64.efi /mnt/EFI/DRIVERS/ext4_x64.efi

sudo umount /mnt
```

### Install to the EFI System Partition (ESP)

> [!WARNING]
> The commands below are examples that use `/dev/nvme0n1` and partition 1 (`/dev/nvme0n1p1`).
>
> Run `lsblk` and find the EFI System Partition (ESP) mounted at `/boot/efi` in the `MOUNTPOINTS` column. Adjust the device and partition numbers accordingly.

```bash
sudo mkdir -p /boot/efi/EFI/vFiL
sudo mkdir -p /boot/efi/EFI/DRIVERS

sudo cp ./MOK.cer /boot/efi/EFI/vFiL/MOK.cer

sudo cp ./BOOTX64.efi /boot/efi/EFI/vFiL/BOOTX64.efi
# If you built it yourself:
# sudo cp ./zig-out/bin/BOOTX64.efi /boot/efi/EFI/vFiL/BOOTX64.efi

sudo cp ./ext4_x64.efi /boot/efi/EFI/DRIVERS/ext4_x64.efi
# If you built it yourself:
# sudo cp ./zig-out/bin/ext4_x64.efi /boot/efi/EFI/DRIVERS/ext4_x64.efi

sudo efibootmgr \
  --create \
  --disk /dev/nvme0n1 \
  --part 1 \
  --label "vFiL" \
  --loader '\EFI\vFiL\BOOTX64.efi'
```

## Build from Source

The default branch of vFiL is [master](https://github.com/fluffy-melli/vFiL).

```bash
sudo apt install sbsigntool

git clone https://github.com/fluffy-melli/vFiL
cd vFiL

# Generate a Machine Owner Key (MOK)
openssl req -new -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout MOK.key -out MOK.crt
openssl x509 -in MOK.crt -outform DER -out MOK.cer

zig build
```

## Third Party

> [!NOTE]
> This project bundles the following third-party binary.

- [`ext4_x64.efi`](https://github.com/fluffy-melli/vFiL/blob/main/third-party/ext4_x64.efi): ext4 filesystem driver (x64), from [rEFInd](https://www.rodsbooks.com/refind/)
