const std = @import("std");
const utils = @import("utils");
const volume = @import("volume");
const system = @import("system");

const graphics = @import("_.zig");

const uefi = std.os.uefi;

fn is_selectable(app: *const volume.Entry) bool {
    return switch (app.bootloader) {
        .Image => false,
        else => true,
    };
}

fn step(items: []const volume.Entry, from: usize, forward: bool) usize {
    if (items.len == 0) {
        return from;
    }

    var i = from;
    for (0..items.len) |_| {
        if (forward) {
            i = (i + 1) % items.len;
        } else {
            i = (i + items.len - 1) % items.len;
        }

        if (is_selectable(&items[i])) {
            return i;
        }
    }

    return from;
}

pub fn select(allocator: std.mem.Allocator, service: system.Service, applications: std.ArrayList(volume.Entry), booted: usize) uefi.Error!usize {
    var moved = false;
    var re_draw = true;
    var selected: usize = 0;

    const timeout: u64 = 7;
    var last_elapsed: u64 = std.math.maxInt(u64);

    if (booted != std.math.maxInt(usize)) {
        selected = booted;
    }

    try graphics.clear(service);

    const start = try service.runtime.getTime();

    const value_pad: usize = service.geo.columns / 3;
    const arrow_msg = std.unicode.utf8ToUtf16LeStringLiteral(" > ");

    var title_pad: usize = 0;
    const title_msg = std.unicode.utf8ToUtf16LeStringLiteral(" Select an operating system to boot: ");

    if (service.geo.columns > title_msg.len) {
        title_pad = (service.geo.columns - title_msg.len) / 2;
    }

    try service.con_out.setAttribute(.{ .foreground = .white, .background = .black });
    try service.con_out.setCursorPosition(title_pad, 0);
    _ = try service.con_out.outputString(title_msg.ptr);

    var instruction_pad: usize = 0;
    const instruction_msg = std.unicode.utf8ToUtf16LeStringLiteral(" Use Up/Down to select, Enter to boot. ");

    if (service.geo.columns > instruction_msg.len) {
        instruction_pad = (service.geo.columns - instruction_msg.len) / 2;
    }

    try service.con_out.setAttribute(.{ .foreground = .yellow, .background = .black });
    try service.con_out.setCursorPosition(instruction_pad, service.geo.rows - 1);
    _ = try service.con_out.outputString(instruction_msg.ptr);

    while (true) {
        if (re_draw) {
            var row: usize = 2;
            for (applications.items, 0..) |*app, i| {
                if (!is_selectable(app)) {
                    continue;
                }

                try service.con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
                try service.con_out.setCursorPosition(value_pad - 3, row);

                if (i == selected) {
                    try service.con_out.setAttribute(.{ .foreground = .white, .background = .blue });
                } else {
                    try service.con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
                }

                if (i == selected) {
                    _ = try service.con_out.outputString(arrow_msg.ptr);
                } else {
                    for (0..3) |_| {
                        _ = try service.con_out.outputString(&.{ ' ', 0 });
                    }
                }

                var used: usize = value_pad * 2;
                switch (app.bootloader) {
                    .Efi => |*efi| {
                        used += efi.path.len;
                        _ = try service.con_out.outputString(efi.path.ptr);
                    },
                    .Image => unreachable,
                    .Kernel => |*kernel| {
                        used += kernel.path.len;
                        _ = try service.con_out.outputString(kernel.path.ptr);
                    },
                }

                for (0..service.geo.columns - used) |_| {
                    _ = try service.con_out.outputString(&.{ ' ', 0 });
                }

                try service.con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });

                row += 1;
            }

            re_draw = false;
        }

        if (!moved) {
            const now = try service.runtime.getTime();

            const elapsed_ns = now.@"0".toEpoch() -| start.@"0".toEpoch();
            const elapsed = elapsed_ns / std.time.ns_per_s;

            if (elapsed >= timeout) {
                try graphics.clear(service);
                return selected;
            }

            if (elapsed != last_elapsed) {
                var auto_start_pad: usize = 0;
                const auto_start_msg = std.fmt.allocPrint(allocator, " Booting in {d}s... ", .{timeout - elapsed}) catch {
                    return uefi.Error.OutOfResources;
                };
                defer allocator.free(auto_start_msg);

                const utf16_auto_start_msg = std.unicode.utf8ToUtf16LeAllocZ(allocator, auto_start_msg) catch {
                    return uefi.Error.OutOfResources;
                };
                defer allocator.free(utf16_auto_start_msg);

                if (service.geo.columns > utf16_auto_start_msg.len) {
                    auto_start_pad = (service.geo.columns - utf16_auto_start_msg.len) / 2;
                }

                try service.con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
                try service.con_out.setCursorPosition(auto_start_pad, service.geo.rows - 4);
                _ = try service.con_out.outputString(utf16_auto_start_msg.ptr);

                var auto_start_cancel_pad: usize = 0;
                const auto_start_cancel_msg = std.unicode.utf8ToUtf16LeStringLiteral(" press any key to cancel ");

                if (service.geo.columns > auto_start_cancel_msg.len) {
                    auto_start_cancel_pad = (service.geo.columns - auto_start_cancel_msg.len) / 2;
                }

                try service.con_out.setCursorPosition(auto_start_cancel_pad, service.geo.rows - 3);
                _ = try service.con_out.outputString(auto_start_cancel_msg.ptr);

                last_elapsed = elapsed;
            }
        }

        const key = service.con_in.readKeyStroke() catch |err| {
            switch (err) {
                error.NotReady => {
                    try service.boot.stall(10_000);
                    continue;
                },
                else => return err,
            }
        };

        if (!moved) {
            try service.con_out.setCursorPosition(0, service.geo.rows - 3);

            for (0..service.geo.columns - 1) |_| {
                _ = try service.con_out.outputString(&.{ ' ', 0 });
            }

            try service.con_out.setCursorPosition(0, service.geo.rows - 4);

            for (0..service.geo.columns - 1) |_| {
                _ = try service.con_out.outputString(&.{ ' ', 0 });
            }

            moved = true;
        }

        switch (key.scan_code) {
            0x01 => {
                re_draw = true;
                selected = step(applications.items, selected, false);
            },
            0x02 => {
                re_draw = true;
                selected = step(applications.items, selected, true);
            },
            else => {},
        }

        if (key.unicode_char == 0x000D) {
            try graphics.clear(service);
            return selected;
        }
    }
}
