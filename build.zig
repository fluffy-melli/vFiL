const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
        .abi = .msvc,
    });

    const utils = b.addModule("utils", .{
        .root_source_file = b.path("src/utils/_.zig"),
        .optimize = optimize,
        .target = target,
    });

    const volume = b.addModule("volume", .{
        .root_source_file = b.path("src/volume/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
        },
    });

    const graphics = b.addModule("graphics", .{
        .root_source_file = b.path("src/graphics/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "volume", .module = volume },
        },
    });

    const boot = b.addModule("boot", .{
        .root_source_file = b.path("src/boot/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "volume", .module = volume },
        },
    });

    boot.addAnonymousImport("ext4_x64", .{
        .root_source_file = b.path("asset/ext4_x64.efi"),
    });

    const exe = b.addExecutable(.{
        .name = "BOOTX64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
            .strip = true,
            .imports = &.{
                .{ .name = "boot", .module = boot },
                .{ .name = "graphics", .module = graphics },
            },
        }),
    });

    b.installArtifact(exe);
}
