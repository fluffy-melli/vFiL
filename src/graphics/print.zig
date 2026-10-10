const std = @import("std");
const utils = @import("utils");

const uefi = std.os.uefi;

pub fn printf(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) uefi.Error!void {
    const system_table = uefi.system_table;

    const con_out = system_table.con_out orelse {
        return uefi.Error.Unsupported;
    };

    const message = std.fmt.allocPrint(allocator, fmt, args) catch {
        return uefi.Error.OutOfResources;
    };
    defer allocator.free(message);

    const utf16 = try utils.unicode.utf8_to_utf16(allocator, message);
    defer allocator.free(utf16);

    const terminated = allocator.allocSentinel(u16, utf16.len, 0) catch {
        return uefi.Error.OutOfResources;
    };
    defer allocator.free(terminated);

    @memcpy(terminated, utf16);

    _ = try con_out.outputString(terminated.ptr);
}

pub fn print_spaces(count: usize) uefi.Error!void {
    const system_table = uefi.system_table;

    const con_out = system_table.con_out orelse {
        return uefi.Error.Unsupported;
    };

    const space = [_:0]u16{ ' ', 0 };

    var i: usize = 0;
    while (i < count) : (i += 1) {
        _ = con_out.outputString(&space) catch {};
    }
}
