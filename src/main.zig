const std = @import("std");
const boot = @import("boot");
const graphics = @import("graphics");

const uefi = std.os.uefi;

pub fn main() uefi.Error!void {
    const allocator = uefi.pool_allocator;
    const system_table = uefi.system_table;

    var loader = try boot.Loader.init(allocator, system_table);
    defer loader.deinit();

    try loader.bootstrap();

    const selected = try graphics.select(loader.applications);
    try loader.boot(selected);
}
