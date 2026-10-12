const std = @import("std");
const utils = @import("utils");

const uefi = std.os.uefi;
const File = uefi.protocol.File;

pub fn base_name(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfAny(u8, path, "\\/") orelse {
        return path;
    };

    return path[idx + 1 ..];
}

pub fn is_dot(name: []const u16) bool {
    if (name.len == 0 or name.len > 3) {
        return false;
    }

    if (name.len == 1 and name[0] == '.') {
        return true;
    }

    if (name.len == 2 and name[0] == '.' and name[1] == '.') {
        return true;
    }

    return false;
}

pub fn is_efi(name: []const u16) bool {
    if (name.len < 4) {
        return false;
    }

    const ext = name[name.len - 4 ..];

    return ext[0] == '.' and
        (ext[1] == 'e' or ext[1] == 'E') and
        (ext[2] == 'f' or ext[2] == 'F') and
        (ext[3] == 'i' or ext[3] == 'I');
}

pub fn is_img(name: []const u16) bool {
    if (name.len < 4) {
        return false;
    }

    const ext = name[name.len - 4 ..];

    return ext[0] == '.' and
        (ext[1] == 'i' or ext[1] == 'I') and
        (ext[2] == 'm' or ext[2] == 'M') and
        (ext[3] == 'g' or ext[3] == 'G');
}

pub fn is_initrd(path: []const u8) bool {
    const name = base_name(path);

    return std.mem.startsWith(u8, name, "initramfs") or std.mem.startsWith(u8, name, "initrd");
}

pub fn is_kernel(allocator: std.mem.Allocator, dir: *File, path: []const u16) uefi.Error!bool {
    const file_path = allocator.allocSentinel(u16, path.len, 0) catch {
        return uefi.Error.OutOfResources;
    };

    @memcpy(file_path, path);

    const file = try dir.open(file_path, .read, .{});
    defer _ = file.close() catch {};

    var buffer: [520]u8 = undefined;

    const n = try file.read(&buffer);
    if (n < 0x206) {
        return false;
    }

    const magic = std.mem.readInt(u32, buffer[0x202..0x206], .little);
    if (magic == 0x53726448) {
        return true;
    }

    return false;
}
