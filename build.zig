const std = @import("std");

fn sbsign(b: *std.Build, root: std.Build.LazyPath, filename: []const u8) std.Build.LazyPath {
    const command = b.addSystemCommand(&.{ "sbsign", "--key", "MOK.key", "--cert", "MOK.crt", "--output" });

    const output = command.addOutputFileArg(filename);

    command.addFileArg(root);

    return output;
}

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

    const system = b.addModule("system", .{
        .root_source_file = b.path("src/system/_.zig"),
        .optimize = optimize,
        .target = target,
    });

    const volume = b.addModule("volume", .{
        .root_source_file = b.path("src/volume/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "system", .module = system },
        },
    });

    const graphics = b.addModule("graphics", .{
        .root_source_file = b.path("src/graphics/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "volume", .module = volume },
            .{ .name = "system", .module = system },
        },
    });

    const boot = b.addModule("boot", .{
        .root_source_file = b.path("src/boot/_.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "utils", .module = utils },
            .{ .name = "volume", .module = volume },
            .{ .name = "system", .module = system },
        },
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

    exe.root_module.addAnonymousImport("sbat", .{
        .root_source_file = b.path("sbat.csv"),
    });

    const signed_ext4_driver = sbsign(b, b.path("third-party/ext4_x64.efi"), "ext4_x64.efi");
    const install_ext4_driver = b.addInstallFileWithDir(signed_ext4_driver, .bin, "ext4_x64.efi");
    b.getInstallStep().dependOn(&install_ext4_driver.step);

    const signed_bootx64 = sbsign(b, exe.getEmittedBin(), "BOOTX64.efi");
    const install_bootx64 = b.addInstallFileWithDir(signed_bootx64, .bin, "BOOTX64.efi");
    b.getInstallStep().dependOn(&install_bootx64.step);
}
