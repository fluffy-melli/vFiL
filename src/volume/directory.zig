const std = @import("std");
const utils = @import("utils");
const system = @import("system");

const volume = @import("_.zig");

const uefi = std.os.uefi;
const File = uefi.protocol.File;
const FileInfo = File.Info.File;
const DevicePathProtocol = uefi.protocol.DevicePath;

pub fn scan(allocator: std.mem.Allocator, service: system.Service, handle: uefi.Handle, entrys: *std.ArrayList(volume.Entry), prefix: [:0]const u16, dir: *File, max_depth: usize, depth: usize, check_kernel: bool) uefi.Error!void {
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
            const fullname = try utils.unicode.utf16_join_path(allocator, prefix, filename);
            defer allocator.free(fullname);

            var entry = volume.Entry.init(allocator, service, handle, dir, fullname, check_kernel) catch {
                continue;
            };
            errdefer entry.deinit();

            entrys.append(allocator, entry) catch {
                return uefi.Error.OutOfResources;
            };

            continue;
        }

        if (depth >= max_depth) {
            continue;
        }

        const full_prefix = try utils.unicode.utf16_join_path(allocator, prefix, filename);
        defer allocator.free(full_prefix);

        const sub_dir = try dir.open(filename, .read, .{});
        defer _ = sub_dir.close() catch {};

        try scan(allocator, service, handle, entrys, full_prefix, sub_dir, max_depth, depth + 1, check_kernel);
    }
}
