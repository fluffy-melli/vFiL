const std = @import("std");
const utils = @import("utils");
const decide = @import("decide");
const volume = @import("volume");

const uefi = std.os.uefi;
const GraphicsOutput = uefi.protocol.GraphicsOutput;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;
const DevicePathProtocol = uefi.protocol.DevicePath;

pub const Loader = struct {
    allocator: std.mem.Allocator,

    applications: std.ArrayList(decide.os.Table),

    pub fn init(allocator: std.mem.Allocator) uefi.Error!Loader {
        var applications: std.ArrayList(decide.os.Table) = .empty;

        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const handles = try boot_service.locateHandleBuffer(.{ .by_protocol = &SimpleFileSystem.guid }) orelse {
            return uefi.Error.DeviceError;
        };

        var os_detecter = try decide.os.Detecter.init(allocator);
        defer os_detecter.deinit();

        for (handles) |handle| {
            var vol = volume.Volume.init(allocator);

            vol.scan(handle) catch continue;

            if (vol.applications.items.len == 0) {
                vol.deinit();
                continue;
            }

            for (vol.applications.items) |application| {
                const os_type = os_detecter.do(application);

                if (os_type == .Unknown) {
                    allocator.free(application);
                    continue;
                }

                const table = decide.os.Table{
                    .type = os_type,
                    .path = application,
                    .handle = handle,
                };

                applications.append(allocator, table) catch {
                    allocator.free(application);
                    return uefi.Error.OutOfResources;
                };
            }

            vol.applications.items.len = 0;
            vol.deinit();
        }

        return Loader{
            .allocator = allocator,
            .applications = applications,
        };
    }

    pub fn deinit(self: *Loader) void {
        for (self.applications.items) |application| {
            self.allocator.free(application.path);
        }

        self.applications.deinit(self.allocator);
    }

    pub fn start_application(self: *Loader, index: usize) uefi.Error!void {
        const application = self.applications.items[index];

        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const device_path = try boot_service.openProtocol(DevicePathProtocol, application.handle, .{ .by_handle_protocol = .{} }) orelse {
            return uefi.Error.DeviceError;
        };

        const file_device_path = device_path.createFileDevicePath(self.allocator, application.path) catch {
            return uefi.Error.OutOfResources;
        };

        const image_handle = try boot_service.loadImage(false, uefi.handle, .{ .device_path = file_device_path });

        _ = try boot_service.startImage(image_handle);
    }

    pub fn wait(self: *Loader) uefi.Error!void {
        const events = [_]uefi.Event{self.con_in.wait_for_key};

        _ = try self.boot_service.waitForEvent(&events);
    }
};
