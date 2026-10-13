const std = @import("std");
const utils = @import("_.zig");

const uefi = std.os.uefi;
const File = uefi.protocol.File;

pub fn base_name(path: [:0]const u16) [:0]const u16 {
    var i = path.len;

    while (i > 0) : (i -= 1) {
        if (path[i - 1] == '\\' or path[i - 1] == '/') {
            return path[i..];
        }
    }

    return path;
}

pub fn is_dot(name: [:0]const u16) bool {
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

pub fn is_efi(name: [:0]const u16) bool {
    if (name.len < 4) {
        return false;
    }

    const ext = name[name.len - 4 ..];

    return ext[0] == '.' and
        (ext[1] == 'e' or ext[1] == 'E') and
        (ext[2] == 'f' or ext[2] == 'F') and
        (ext[3] == 'i' or ext[3] == 'I');
}

pub fn is_img(name: [:0]const u16) bool {
    if (name.len < 4) {
        return false;
    }

    const ext = name[name.len - 4 ..];

    return ext[0] == '.' and
        (ext[1] == 'i' or ext[1] == 'I') and
        (ext[2] == 'm' or ext[2] == 'M') and
        (ext[3] == 'g' or ext[3] == 'G');
}

pub fn is_initrd(path: [:0]const u16) bool {
    const name = base_name(path);

    const initrd = std.unicode.utf8ToUtf16LeStringLiteral("initrd");
    const initramfs = std.unicode.utf8ToUtf16LeStringLiteral("initramfs");

    return utils.unicode.utf16_starts_with_ignore_case(name, initrd) or utils.unicode.utf16_starts_with_ignore_case(name, initramfs);
}

pub fn is_kernel(dir: *File, path: [:0]const u16) uefi.Error!bool {
    const file = try dir.open(path, .read, .{});
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
