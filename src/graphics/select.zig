const std = @import("std");
const utils = @import("utils");
const volume = @import("volume");

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

pub fn select(allocator: std.mem.Allocator, applications: std.ArrayList(volume.Entry)) uefi.Error!usize {
    if (applications.items.len == 0) {
        return uefi.Error.NotFound;
    }

    const system_table = uefi.system_table;

    const con_out = system_table.con_out orelse {
        return uefi.Error.Unsupported;
    };

    const con_in = system_table.con_in orelse {
        return uefi.Error.Unsupported;
    };

    const boot_services = system_table.boot_services orelse {
        return uefi.Error.Unsupported;
    };

    const geo = try con_out.queryMode(con_out.mode.mode);

    const title = "Select an operating system to boot:";
    var title_pad: usize = 0;

    if (geo.columns > title.len) {
        title_pad = (geo.columns - title.len) / 2;
    }

    const instruction = "Use Up/Down to select, Enter to boot.";
    var instruction_pad: usize = 0;

    if (geo.columns > instruction.len) {
        instruction_pad = (geo.columns - instruction.len) / 2;
    }

    var selected: usize = 0;

    try graphics.clear();

    try con_out.setAttribute(.{ .foreground = .white, .background = .black });
    try con_out.setCursorPosition(title_pad - 1, 0);
    try graphics.printf(allocator, " {s} ", .{title});

    try con_out.setAttribute(.{ .foreground = .yellow, .background = .black });
    try con_out.setCursorPosition(instruction_pad - 1, geo.rows - 1);
    try graphics.printf(allocator, " {s} ", .{instruction});

    while (true) {
        var row: usize = 2;
        for (applications.items, 0..) |*app, i| {
            if (!is_selectable(app)) {
                continue;
            }

            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            try con_out.setCursorPosition(geo.columns / 3 - 3, row);

            if (i == selected) {
                try con_out.setAttribute(.{ .foreground = .white, .background = .blue });
            } else {
                try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            }

            if (i == selected) {
                try graphics.printf(allocator, " > ", .{});
            } else {
                try graphics.print_spaces(3);
            }

            var used: usize = geo.columns / 3 * 2;
            switch (app.bootloader) {
                .Efi => |*efi| {
                    used += efi.utf8_path.len;
                    try graphics.printf(allocator, "{s}", .{efi.utf8_path});
                },
                .Image => unreachable,
                .Kernel => |*kernel| {
                    used += kernel.utf8_path.len;
                    try graphics.printf(allocator, "{s}", .{kernel.utf8_path});
                },
            }

            if (used < geo.columns) {
                try graphics.print_spaces(geo.columns - used);
            }

            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });

            row += 1;
        }

        const events = [_]uefi.Event{con_in.wait_for_key};
        _ = try boot_services.waitForEvent(&events);

        const key = try con_in.readKeyStroke();

        switch (key.scan_code) {
            0x01 => {
                selected = step(applications.items, selected, false);
            },
            0x02 => {
                selected = step(applications.items, selected, true);
            },
            else => {},
        }

        if (key.unicode_char == 0x000D) {
            try con_out.setAttribute(.{ .foreground = .white, .background = .black });
            try graphics.clear();

            return selected;
        }
    }
}
