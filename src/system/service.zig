const std = @import("std");

const uefi = std.os.uefi;

pub const Service = struct {
    boot: *uefi.tables.BootServices,
    system_table: *uefi.tables.SystemTable,

    con_out: *uefi.protocol.SimpleTextOutput,
    con_in: *uefi.protocol.SimpleTextInput,

    geo: uefi.protocol.SimpleTextOutput.Geometry,

    pub fn init() uefi.Error!Service {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const con_out = system_table.con_out orelse {
            return uefi.Error.Unsupported;
        };

        const con_in = system_table.con_in orelse {
            return uefi.Error.Unsupported;
        };

        const geo = try con_out.queryMode(con_out.mode.mode);

        return .{
            .system_table = system_table,
            .boot = boot_service,
            .con_out = con_out,
            .con_in = con_in,
            .geo = geo,
        };
    }
};
