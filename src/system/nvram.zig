const std = @import("std");

const system = @import("_.zig");

const uefi = std.os.uefi;

const guid: uefi.Guid align(8) = .{
    .time_low = 0x0c85bd9e,
    .time_mid = 0x8146,
    .time_high_and_version = 0x4870,
    .clock_seq_high_and_reserved = 0xb6,
    .clock_seq_low = 0x85,
    .node = .{ 0xbc, 0x18, 0x55, 0xe0, 0x8c, 0x09 },
};

pub fn read(service: system.Service, buffer: []u8, name: [:0]const u16) uefi.Error!?[]u8 {
    const value = try service.runtime.getVariable(name, &guid, buffer) orelse {
        return null;
    };

    return value.@"0";
}

pub fn write(service: system.Service, name: [:0]const u16, value: []const u8) uefi.Error!void {
    try service.runtime.setVariable(name, &guid, .{ .non_volatile = true, .bootservice_access = true, .runtime_access = true }, value);
}

pub fn creaft_buffer(allocator: std.mem.Allocator, service: system.Service, name: [:0]const u16) uefi.Error!?[]u8 {
    const info = try service.runtime.getVariableSize(name, &guid) orelse {
        return null;
    };

    const size = info.@"0";

    const buffer = allocator.alloc(u8, size) catch {
        return uefi.Error.OutOfResources;
    };

    return buffer;
}
