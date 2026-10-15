const std = @import("std");
const boot = @import("boot");
const graphics = @import("graphics");

const uefi = std.os.uefi;

pub fn main() uefi.Error!void {
    const allocator = uefi.pool_allocator;

    var loader = try boot.Loader.init(allocator);
    defer loader.deinit();

    const booted = try loader.bootstrap();

    const selected = try graphics.select(loader.service, loader.applications, booted);
    try loader.boot(booted, selected);
}
