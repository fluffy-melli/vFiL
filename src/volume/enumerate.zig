const std = @import("std");
const utils = @import("utils");

const volume = @import("_.zig");

const uefi = std.os.uefi;
const File = uefi.protocol.File;
const LoadedImage = uefi.protocol.LoadedImage;
const ImageExitData = uefi.tables.BootServices.ImageExitData;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;
const DevicePathProtocol = uefi.protocol.DevicePath;

pub const Type = enum {
    Efi,
    Image,
    Kernel,
};

pub const Efi = struct {
    allocator: std.mem.Allocator,

    dir: *File,
    path: []const u16,
    utf8_path: []const u8,
    device_path: *const DevicePathProtocol,

    part_uuid: []const u8,

    pub fn init(allocator: std.mem.Allocator, handle: uefi.Handle, dir: *File, path: []const u16) uefi.Error!Efi {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const device_path = try boot_service.openProtocol(DevicePathProtocol, handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const utf8_path = try utils.unicode.utf16_to_utf8(allocator, path);
        const part_uuid = try utils.partition.get_part_uuid(allocator, device_path);

        return .{
            .allocator = allocator,
            .dir = dir,
            .path = path,
            .utf8_path = utf8_path,
            .device_path = device_path,
            .part_uuid = part_uuid,
        };
    }

    pub fn deinit(self: *Efi) void {
        self.allocator.free(self.path);
        self.allocator.free(self.utf8_path);

        self.allocator.free(self.part_uuid);
    }

    pub fn boot(self: *Efi) uefi.Error!ImageExitData {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const file_device_path = self.device_path.createFileDevicePath(self.allocator, self.path) catch {
            return uefi.Error.OutOfResources;
        };

        const image_handle = try boot_service.loadImage(false, uefi.handle, .{ .device_path = file_device_path });

        return try boot_service.startImage(image_handle);
    }
};

pub const Image = struct {
    allocator: std.mem.Allocator,

    dir: *File,
    path: []const u16,
    utf8_path: []const u8,
    device_path: *const DevicePathProtocol,

    part_uuid: []const u8,

    pub fn init(allocator: std.mem.Allocator, handle: uefi.Handle, dir: *File, path: []const u16) uefi.Error!Image {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const device_path = try boot_service.openProtocol(DevicePathProtocol, handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const utf8_path = try utils.unicode.utf16_to_utf8(allocator, path);
        const part_uuid = try utils.partition.get_part_uuid(allocator, device_path);

        return .{
            .allocator = allocator,
            .dir = dir,
            .path = path,
            .utf8_path = utf8_path,
            .device_path = device_path,
            .part_uuid = part_uuid,
        };
    }

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.path);
        self.allocator.free(self.utf8_path);

        self.allocator.free(self.part_uuid);
    }
};

pub const Kernel = struct {
    allocator: std.mem.Allocator,

    dir: *File,
    path: []const u16,
    utf8_path: []const u8,
    device_path: *const DevicePathProtocol,

    part_uuid: []const u8,

    pub fn init(allocator: std.mem.Allocator, handle: uefi.Handle, dir: *File, path: []const u16) uefi.Error!Kernel {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const device_path = try boot_service.openProtocol(DevicePathProtocol, handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const utf8_path = try utils.unicode.utf16_to_utf8(allocator, path);
        const part_uuid = try utils.partition.get_part_uuid(allocator, device_path);

        return .{
            .allocator = allocator,
            .dir = dir,
            .path = path,
            .utf8_path = utf8_path,
            .device_path = device_path,
            .part_uuid = part_uuid,
        };
    }

    pub fn deinit(self: *Kernel) void {
        self.allocator.free(self.path);
        self.allocator.free(self.utf8_path);

        self.allocator.free(self.part_uuid);
    }

    pub fn boot(self: *Kernel, cmdline: []const u8) uefi.Error!ImageExitData {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const file_device_path = self.device_path.createFileDevicePath(self.allocator, self.path) catch {
            return uefi.Error.OutOfResources;
        };

        const image_handle = try boot_service.loadImage(false, uefi.handle, .{ .device_path = file_device_path });

        const loaded_image = try boot_service.openProtocol(LoadedImage, image_handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.Unsupported;
        };

        const utf16_cmdline = try utils.unicode.utf8_to_utf16(self.allocator, cmdline);

        loaded_image.load_options = @ptrCast(@constCast(utf16_cmdline.ptr));
        loaded_image.load_options_size = @intCast((utf16_cmdline.len + 1) * @sizeOf(u16));

        return try boot_service.startImage(image_handle);
    }
};

pub const Entry = struct {
    type: Type,
    bootloader: union(Type) {
        Efi: Efi,
        Image: Image,
        Kernel: Kernel,
    },

    pub fn init(allocator: std.mem.Allocator, handle: uefi.Handle, dir: *File, path: []const u16, check_kernel: bool) uefi.Error!Entry {
        const file_path = allocator.dupe(u16, path) catch {
            return uefi.Error.OutOfResources;
        };

        const is_efi = utils.extension.is_efi(file_path);
        if (is_efi) {
            return .{
                .type = .Efi,
                .bootloader = .{
                    .Efi = try Efi.init(allocator, handle, dir, file_path),
                },
            };
        }

        const is_image = utils.extension.is_img(file_path);
        if (is_image) {
            return .{
                .type = .Image,
                .bootloader = .{
                    .Image = try Image.init(allocator, handle, dir, file_path),
                },
            };
        }

        if (!check_kernel) {
            return uefi.Error.InvalidParameter;
        }

        const is_kernel = try utils.extension.is_kernel(allocator, dir, file_path);
        if (is_kernel) {
            return .{
                .type = .Kernel,
                .bootloader = .{
                    .Kernel = try Kernel.init(allocator, handle, dir, file_path),
                },
            };
        }

        return uefi.Error.InvalidParameter;
    }

    pub fn deinit(self: *Entry) void {
        switch (self.bootloader) {
            .Efi => |*efi| {
                efi.deinit();
            },
            .Image => |*image| {
                image.deinit();
            },
            .Kernel => |*kernel| {
                kernel.deinit();
            },
        }
    }

    pub fn boot(self: *Entry, cmdline: ?[]const u8) uefi.Error!ImageExitData {
        switch (self.bootloader) {
            .Efi => |*efi| {
                return try efi.boot();
            },
            .Image => {
                return uefi.Error.InvalidParameter;
            },
            .Kernel => |*kernel| {
                const command = cmdline orelse {
                    return uefi.Error.InvalidParameter;
                };

                return try kernel.boot(command);
            },
        }
    }
};

pub const Volume = struct {
    allocator: std.mem.Allocator,

    handle: uefi.Handle,
    applications: std.ArrayList(Entry),

    pub fn init(allocator: std.mem.Allocator, handle: uefi.Handle) Volume {
        return Volume{
            .allocator = allocator,
            .handle = handle,
            .applications = .empty,
        };
    }

    pub fn deinit(self: *Volume) void {
        for (self.applications.items) |*app| {
            app.deinit();
        }

        self.applications.deinit(self.allocator);
    }

    pub fn scan(self: *Volume) uefi.Error!void {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const fs = try boot_service.openProtocol(SimpleFileSystem, self.handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const root_dir = fs.openVolume() catch {
            return uefi.Error.DeviceError;
        };
        defer root_dir.close() catch {};

        if (root_dir.open(std.unicode.utf8ToUtf16LeStringLiteral("\\EFI"), .read, .{}) catch null) |efi_dir| {
            defer efi_dir.close() catch {};

            try volume.directory.scan(self.allocator, self.handle, &self.applications, std.unicode.utf8ToUtf16LeStringLiteral("\\EFI"), efi_dir, 3, 0, false);
        }

        if (root_dir.open(std.unicode.utf8ToUtf16LeStringLiteral("\\boot"), .read, .{}) catch null) |boot_dir| {
            defer boot_dir.close() catch {};

            try volume.directory.scan(self.allocator, self.handle, &self.applications, std.unicode.utf8ToUtf16LeStringLiteral("\\boot"), boot_dir, 1, 0, true);
        }

        volume.directory.scan(self.allocator, self.handle, &self.applications, &.{}, root_dir, 1, 0, false) catch {};
    }
};
