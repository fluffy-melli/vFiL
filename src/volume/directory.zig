const std = @import("std");
const utils = @import("utils");

const volume = @import("_.zig");

const uefi = std.os.uefi;
const File = uefi.protocol.File;
const FileInfo = File.Info.File;

pub fn scan(vol: *volume.Volume, prefix: []const u16, dir: *File, depth: usize) uefi.Error!void {
    var buffer: [2048]u8 align(@alignOf(FileInfo)) = undefined;

    dir.setPosition(0) catch {
        return uefi.Error.DeviceError;
    };

    while (true) {
        const len = try dir.read(&buffer);
        if (len == 0) {
            break;
        }

        const info: *const FileInfo = @ptrCast(&buffer);
        const filename = std.mem.span(info.getFileName());

        if (utils.extension.is_dot(filename)) {
            continue;
        }

        if (!info.attribute.directory) {
            const full_filename = try utils.unicode.utf16_join_path(vol.allocator, prefix, filename);
            errdefer vol.allocator.free(full_filename);

            vol.applications.append(vol.allocator, full_filename) catch {
                return uefi.Error.OutOfResources;
            };

            continue;
        }

        if (depth >= 5) {
            continue;
        }

        const full_prefix = try utils.unicode.utf16_join_path(vol.allocator, prefix, filename);
        defer vol.allocator.free(full_prefix);

        const sub_dir = try dir.open(filename, .read, .{});
        defer _ = sub_dir.close() catch {};

        try scan(vol, full_prefix, sub_dir, depth + 1);
    }
}
