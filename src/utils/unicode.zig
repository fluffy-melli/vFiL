const std = @import("std");

const uefi = std.os.uefi;

pub fn utf16_join_path(allocator: std.mem.Allocator, parent: [:0]const u16, name: [:0]const u16) uefi.Error![:0]u16 {
    const separator = parent.len == 0 or parent[parent.len - 1] != '\\';

    const path = allocator.allocSentinel(u16, parent.len + @intFromBool(separator) + name.len, 0) catch {
        return uefi.Error.OutOfResources;
    };

    @memcpy(path[0..parent.len], parent);
    var offset = parent.len;

    if (separator) {
        path[offset] = '\\';
        offset += 1;
    }

    @memcpy(path[offset..][0..name.len], name);

    return path;
}

pub fn utf16_eql(a: [:0]const u16, b: [:0]const u16) bool {
    return std.mem.eql(u16, a, b);
}

pub fn utf16_lower(c: u16) u16 {
    return if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
}

pub fn utf16_eql_ignore_case(a: [:0]const u16, b: [:0]const u16) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (utf16_lower(x) != utf16_lower(y)) return false;
    }
    return true;
}

pub fn utf16_starts_with_ignore_case(haystack: [:0]const u16, needle: [:0]const u16) bool {
    if (haystack.len < needle.len) {
        return false;
    }

    for (haystack[0..needle.len], needle) |x, y| {
        if (utf16_lower(x) != utf16_lower(y)) return false;
    }
    return true;
}
