const std = @import("std");
const utils = @import("utils");

const uefi = std.os.uefi;

pub const Type = enum {
    Unknown,
    Windows,
    Ubuntu,
    Debian,

    pub fn name(self: Type) []const u8 {
        return switch (self) {
            .Windows => "Windows",
            .Ubuntu => "Ubuntu",
            .Debian => "Debian",
            else => "Unknown",
        };
    }
};

pub const Table = struct {
    type: Type,
    path: []const u16,
    handle: uefi.Handle,
};

pub const Detecter = struct {
    allocator: std.mem.Allocator,

    table: [3]Table,

    pub fn init(allocator: std.mem.Allocator) uefi.Error!Detecter {
        const table: [3]Table = .{
            .{
                .type = .Windows,
                .path = try utils.unicode.utf8_to_utf16(allocator, "\\EFI\\Microsoft\\Boot\\bootmgfw.efi"),
                .handle = undefined,
            },
            .{
                .type = .Ubuntu,
                .path = try utils.unicode.utf8_to_utf16(allocator, "\\EFI\\ubuntu\\shimx64.efi"),
                .handle = undefined,
            },
            .{
                .type = .Debian,
                .path = try utils.unicode.utf8_to_utf16(allocator, "\\EFI\\debian\\shimx64.efi"),
                .handle = undefined,
            },
        };

        return Detecter{
            .allocator = allocator,
            .table = table,
        };
    }

    pub fn deinit(self: *Detecter) void {
        for (self.table) |table| {
            self.allocator.free(table.path);
        }
    }

    pub fn do(self: *const Detecter, path: []const u16) Type {
        for (self.table) |table| {
            if (utils.unicode.utf16_eql_ignore_case(table.path, path)) {
                return table.type;
            }
        }

        return .Unknown;
    }
};
