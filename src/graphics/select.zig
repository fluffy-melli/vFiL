const std = @import("std");
const utils = @import("utils");
const decide = @import("decide");

const graphics = @import("_.zig");

const uefi = std.os.uefi;

fn drawMenu(allocator: std.mem.Allocator, applications: []const decide.os.Table, selected: usize) uefi.Error!void {
    const system_table = uefi.system_table;

    const con_out = system_table.con_out orelse {
        return uefi.Error.Unsupported;
    };

    try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });

    try graphics.clear();

    try con_out.setAttribute(.{ .foreground = .white, .background = .black });

    try graphics.printf(allocator, "\r\n    Select an operating system to boot:\r\n\r\n", .{});

    for (applications, 0..) |app, i| {
        try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
        try graphics.printf(allocator, "    ", .{});

        if (i == selected) {
            try con_out.setAttribute(.{ .foreground = .white, .background = .lightgray });
        } else {
            try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
        }

        const marker_len: usize = 3;
        if (i == selected) {
            try graphics.printf(allocator, " > ", .{});
        } else {
            try graphics.printf(allocator, "   ", .{});
        }

        const os_name = app.type.name();

        try graphics.printf(allocator, "{s}", .{os_name});

        const used = marker_len + os_name.len;
        if (used < 50) {
            try graphics.print_spaces(50 - used);
        }

        try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
        try graphics.printf(allocator, "\r\n", .{});
    }

    try con_out.setAttribute(.{ .foreground = .lightgray, .background = .black });
    try graphics.printf(allocator, "\r\n    Use Up/Down to select, Enter to boot.\r\n", .{});
}

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

    var selected: usize = 0;

    while (true) {
        try drawMenu(allocator, applications.items, selected);

        const events = [_]uefi.Event{con_in.wait_for_key};
        _ = try boot_services.waitForEvent(&events);

        const key = try con_in.readKeyStroke();

        if (key.scan_code == 0x01) {
            if (selected > 0) {
                selected -= 1;
            }
        } else if (key.scan_code == 0x02) {
            if (selected + 1 < applications.items.len) {
                selected += 1;
            }
        } else if (key.unicode_char == 0x000D) {
            try con_out.setAttribute(.{ .foreground = .white, .background = .black });
            try graphics.clear();

            return selected;
        }
    }
}
