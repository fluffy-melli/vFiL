const std = @import("std");
const boot = @import("boot");
const graphics = @import("graphics");

const uefi = std.os.uefi;

pub fn main() uefi.Error!void {
    const allocator = uefi.pool_allocator;

    var loader = try boot.Loader.init(allocator);
    defer loader.deinit();

    try loader.bootstrap();

    const selected = try graphics.select(loader.service, loader.applications);
    try loader.boot(selected);
}
