const std = @import("std");
const boot = @import("boot");
const utils = @import("utils");
const graphics = @import("graphics");

const uefi = std.os.uefi;

pub fn main() uefi.Error!void {
    const allocator = uefi.pool_allocator;

    var loader = try boot.Loader.init(allocator);
    defer loader.deinit();

    try graphics.clear();

    const selected = try graphics.select(allocator, loader.applications);
    const exit = try loader.boot(selected);

    if (exit.code != .success) {
        try graphics.clear();

        try graphics.printf(allocator, "fail to boot: {any}\r\n", .{exit.code});
        try graphics.printf(allocator, "\r\nPress any key to reboot...", .{});

        try loader.wait();
    }
}
