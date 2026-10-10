const std = @import("std");

const uefi = std.os.uefi;

pub fn clear() uefi.Error!void {
    var i: usize = 0;
    var max_area: usize = 0;
    var best_mode: usize = 0;

    const system_table = uefi.system_table;

    const con_out = system_table.con_out orelse {
        return uefi.Error.Unsupported;
    };

    while (i < con_out.mode.max_mode) : (i += 1) {
        const geo = con_out.queryMode(i) catch {
            continue;
        };

        const area = geo.columns * geo.rows;
        if (area <= max_area) {
            continue;
        }

        max_area = area;
        best_mode = i;
    }

    try con_out.reset(false);
    try con_out.setMode(best_mode);
    try con_out.clearScreen();
}
