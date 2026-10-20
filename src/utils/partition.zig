const std = @import("std");

const uefi = std.os.uefi;
const DevicePathProtocol = uefi.protocol.DevicePath;

pub fn get_part_uuid(allocator: std.mem.Allocator, device_path: *const DevicePathProtocol) uefi.Error![]u8 {
    var p: [*]const u8 = @ptrCast(device_path);

    while (true) {
        const node_type = p[0];
        const sub_type = p[1];

        if (node_type == 0x7f) {
            return uefi.Error.NotFound;
        }

        const len = std.mem.readInt(u16, p[2..4], .little);
        if (len < 4) {
            return uefi.Error.InvalidParameter;
        }

        if (node_type == 0x04 and sub_type == 0x01) {
            if (len != 42) {
                return uefi.Error.InvalidParameter;
            }

            const sig = p[24..40];
            const format = p[40];
            const sig_type = p[41];
            const part_number = std.mem.readInt(u32, p[4..8], .little);

            if (format == 2 and sig_type == 2) {
                const a = std.mem.readInt(u32, sig[0..4], .little);
                const b = std.mem.readInt(u16, sig[4..6], .little);
                const c = std.mem.readInt(u16, sig[6..8], .little);

                return allocator.print("{x:0>8}-{x:0>4}-{x:0>4}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ a, b, c, sig[8], sig[9], sig[10], sig[11], sig[12], sig[13], sig[14], sig[15] }) catch {
                    return uefi.Error.OutOfResources;
                };
            }

            if (format == 1 and sig_type == 1) {
                const disk_sig = std.mem.readInt(u32, sig[0..4], .little);

                return allocator.print("{x:0>8}-{x:0>2}", .{ disk_sig, part_number }) catch {
                    return uefi.Error.OutOfResources;
                };
            }
        }

        p += len;
    }
}
