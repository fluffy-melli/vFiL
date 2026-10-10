const std = @import("std");

const uefi = std.os.uefi;

pub fn utf8_to_utf16(allocator: std.mem.Allocator, utf8: []const u8) uefi.Error![]u16 {
    return std.unicode.utf8ToUtf16LeAlloc(allocator, utf8) catch {
        return uefi.Error.InvalidParameter;
    };
}

pub fn utf16_to_utf8(allocator: std.mem.Allocator, utf16: []const u16) uefi.Error![]u8 {
    return std.unicode.utf16LeToUtf8Alloc(allocator, utf16) catch {
        return uefi.Error.InvalidParameter;
    };
}

pub fn utf16_join_path(allocator: std.mem.Allocator, parent: []const u16, name: []const u16) uefi.Error![]u16 {
    const separator = parent.len == 0 or parent[parent.len - 1] != '\\';

    const path = allocator.alloc(u16, parent.len + @intFromBool(separator) + name.len) catch {
        return uefi.Error.OutOfResources;
    };

    @memcpy(path[0..parent.len], parent);
    var offset = parent.len;

    if (separator) {
        path[offset] = '\\';
        offset += 1;
    }

    @memcpy(path[offset..], name);

    return path;
}

pub fn utf16_eql(a: []const u16, b: []const u16) bool {
    return std.mem.eql(u16, a, b);
}

pub fn utf16_lower(c: u16) u16 {
    return if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
}

pub fn utf16_eql_ignore_case(a: []const u16, b: []const u16) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (utf16_lower(x) != utf16_lower(y)) return false;
    }
    return true;
}
