const std = @import("std");
const utils = @import("utils");
const volume = @import("volume");

const graphics = @import("_.zig");

const uefi = std.os.uefi;

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
        var app_len: usize = applications.items.len - 1;

        for (applications.items, 0..) |app, i| {
            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            try con_out.setCursorPosition(36 - 3, row);

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

            var used: usize = 36 * 2;
            switch (app.bootloader) {
                .Efi => |*efi| {
                    used += efi.utf8_path.len + efi.part_uuid.len + 3;
                    try graphics.printf(allocator, "{s} ({s})", .{ efi.utf8_path, efi.part_uuid });
                },
                .Image => {
                    app_len -= 1;
                    continue;
                },
                .Kernel => |*kernel| {
                    used += kernel.utf8_path.len + kernel.part_uuid.len + 3;
                    try graphics.printf(allocator, "{s} ({s})", .{ kernel.utf8_path, kernel.part_uuid });
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

        if (key.scan_code == 0x01) {
            if (selected == 0) {
                selected = app_len;
                continue;
            }

            selected -= 1;
        }

        if (key.scan_code == 0x02) {
            if (selected >= app_len) {
                selected = 0;
                continue;
            }

            selected += 1;
        }

        if (key.unicode_char == 0x000D) {
            try con_out.setAttribute(.{ .foreground = .white, .background = .black });
            try graphics.clear();

            return selected;
        }
    }
}
