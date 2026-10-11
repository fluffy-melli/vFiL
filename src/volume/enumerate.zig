const std = @import("std");
const utils = @import("utils");

const volume = @import("_.zig");

const uefi = std.os.uefi;
const File = uefi.protocol.File;
const FileInfo = File.Info.File;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;

pub const Volume = struct {
    allocator: std.mem.Allocator,

    applications: std.ArrayList([]u16),

    pub fn init(allocator: std.mem.Allocator) Volume {
        return Volume{
            .allocator = allocator,
            .applications = .empty,
        };
    }

    pub fn deinit(self: *Volume) void {
        for (self.applications.items) |app| {
            self.allocator.free(app);
        }

        self.applications.deinit(self.allocator);
    }

    pub fn scan(self: *Volume, handle: uefi.Handle) uefi.Error!void {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const fs = try boot_service.openProtocol(SimpleFileSystem, handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const root_dir = fs.openVolume() catch {
            return uefi.Error.DeviceError;
        };
        defer root_dir.close() catch {};

        const efi_dir = root_dir.open(std.unicode.utf8ToUtf16LeStringLiteral("EFI"), .read, .{}) catch {
            return;
        };
        defer efi_dir.close() catch {};

        try volume.directory.scan(self, std.unicode.utf8ToUtf16LeStringLiteral("\\EFI"), efi_dir, 0);
    }
};
