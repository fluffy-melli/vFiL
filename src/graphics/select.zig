const std = @import("std");
const utils = @import("utils");
const decide = @import("decide");

const graphics = @import("_.zig");

const uefi = std.os.uefi;

pub fn select(allocator: std.mem.Allocator, applications: std.ArrayList(decide.os.Table)) uefi.Error!usize {
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

    while (true) {
        try graphics.clear();

        try con_out.setAttribute(.{ .foreground = .white, .background = .black });
        try graphics.printf(allocator, "\r\n", .{});
        try graphics.print_spaces(title_pad);
        try graphics.printf(allocator, "{s}\r\n\r\n", .{title});

        for (applications.items, 0..) |app, i| {
            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            try graphics.print_spaces(9);

            if (i == selected) {
                try con_out.setAttribute(.{ .foreground = .white, .background = .lightgray });
            } else {
                try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            }

            if (i == selected) {
                try graphics.printf(allocator, " > ", .{});
            } else {
                try graphics.print_spaces(3);
            }

            const os_name = app.type.name();
            try graphics.printf(allocator, "{s}", .{os_name});

            const used = 24 + os_name.len;
            if (used < geo.columns) {
                try graphics.print_spaces(geo.columns - used);
            }

            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
            try graphics.printf(allocator, "\r\n", .{});
        }

        try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
        try graphics.printf(allocator, "\r\n", .{});
        try graphics.print_spaces(instruction_pad);
        try graphics.printf(allocator, "{s}\r\n", .{instruction});

        const events = [_]uefi.Event{con_in.wait_for_key};
        _ = try boot_services.waitForEvent(&events);

        const key = try con_in.readKeyStroke();

        if (key.scan_code == 0x01) {
            if (selected == 0) {
                selected = applications.items.len - 1;
                continue;
            }

            selected -= 1;
        }

        if (key.scan_code == 0x02) {
            if (selected >= applications.items.len - 1) {
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
