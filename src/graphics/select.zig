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

pub fn select(service: system.Service, applications: std.ArrayList(volume.Entry)) uefi.Error!usize {
    var selected: usize = 0;

    try graphics.clear(service);

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

        const events = [_]uefi.Event{service.con_in.wait_for_key};
        _ = try service.boot.waitForEvent(&events);

        const key = try service.con_in.readKeyStroke();

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
            try graphics.clear(service);

            return selected;
        }
    }
}
