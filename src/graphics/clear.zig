const std = @import("std");
const system = @import("system");

const uefi = std.os.uefi;

pub fn clear(service: system.Service) uefi.Error!void {
    var i: usize = 0;
    var max_area: usize = 0;
    var best_mode: usize = 0;

    while (i < service.con_out.mode.max_mode) : (i += 1) {
        const geo = service.con_out.queryMode(i) catch {
            continue;
        };

        const area = geo.columns * geo.rows;
        if (area <= max_area) {
            continue;
        }

        max_area = area;
        best_mode = i;
    }

    try service.con_out.reset(false);
    try service.con_out.setMode(best_mode);
    try service.con_out.clearScreen();
}
