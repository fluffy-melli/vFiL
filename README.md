### Installation

Prepare `BOOTX64.efi` from the [Releases](https://github.com/fluffy-melli/vFiL/releases) page, or an `.efi` file you built yourself.

> [!CAUTION]
> This bootloader does not support LVM yet.
>
> Attempting to boot an OS installed on LVM may cause issues.

> [!WARNING]
> These are Linux commands for writing a GPT + FAT32 layout to a USB drive.
>
> The commands below are examples that use `/dev/sda` and `/dev/sda1`. Check which device is yours (e.g., with `lsblk`) and adjust the commands accordingly.

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

---

### Build From Source

> [!WARNING]
> This project is built against `zig 0.16.0`.
>
> Building with `zig 0.17.0` may cause issues.

The default branch of vFiL targets [master](https://github.com/fluffy-melli/vFiL).

```bash
git clone https://github.com/fluffy-melli/vFiL
cd vFiL
zig build
```

---

### Third Party

> [!NOTE]
> This project bundles the following third-party binary.

- [`ext4_x64.efi`](https://github.com/fluffy-melli/vFiL/blob/main/asset/ext4_x64.efi): ext4 filesystem driver (x64), from [rEFInd](https://www.rodsbooks.com/refind/)
