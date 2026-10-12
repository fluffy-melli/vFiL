const std = @import("std");
const utils = @import("utils");
const decide = @import("decide");
const volume = @import("volume");
const graphics = @import("graphics");

const ext4_x64 = @embedFile("ext4_x64");

const uefi = std.os.uefi;
const LoadedImage = uefi.protocol.LoadedImage;
const LoadedImageProtocol = uefi.protocol.LoadedImage;
const GraphicsOutput = uefi.protocol.GraphicsOutput;
const ImageExitData = uefi.tables.BootServices.ImageExitData;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;
const DevicePathProtocol = uefi.protocol.DevicePath;

pub const Loader = struct {
    allocator: std.mem.Allocator,

    applications: std.ArrayList(volume.Entry),

    pub fn init(allocator: std.mem.Allocator) uefi.Error!Loader {
        var applications: std.ArrayList(volume.Entry) = .empty;

        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const driver = try boot_service.loadImage(false, uefi.handle, .{ .buffer = ext4_x64 });
        _ = try boot_service.startImage(driver);

        const controllers = try boot_service.locateHandleBuffer(.{ .by_protocol = &uefi.protocol.BlockIo.guid }) orelse {
            return uefi.Error.Unsupported;
        };

        for (controllers) |ctr| {
            _ = boot_service.connectController(ctr, null, null, true) catch {};
        }

        const handles = try boot_service.locateHandleBuffer(.{ .by_protocol = &SimpleFileSystem.guid }) orelse {
            return uefi.Error.DeviceError;
        };

        for (handles) |handle| {
            var vol = volume.Volume.init(allocator, handle);

            vol.scan() catch {
                vol.deinit();
                continue;
            };

            for (vol.applications.items) |*app| {
                applications.append(allocator, app.*) catch {
                    app.deinit();
                    return uefi.Error.OutOfResources;
                };
            }
        }

        return Loader{
            .allocator = allocator,
            .applications = applications,
        };
    }

    pub fn deinit(self: *Loader) void {
        for (self.applications.items) |*app| {
            app.deinit();
        }

        self.applications.deinit(self.allocator);
    }

    pub fn boot(self: *Loader, selected: usize) uefi.Error!ImageExitData {
        var app = self.applications.items[selected];

        if (app.type != .Kernel) {
            return try app.boot(null);
        }

        const kernel = app.bootloader.Kernel;

        var cmdline = std.fmt.allocPrint(self.allocator, "root=PARTUUID={s} rw", .{kernel.part_uuid}) catch {
            return uefi.Error.OutOfResources;
        };
        errdefer self.allocator.free(cmdline);

        for (self.applications.items) |application| {
            if (application.type != .Image) {
                continue;
            }

            const image = application.bootloader.Image;

            if (!std.ascii.eqlIgnoreCase(image.part_uuid, kernel.part_uuid)) {
                continue;
            }

            if (!utils.extension.is_initrd(image.utf8_path)) {
                continue;
            }

            const next = std.fmt.allocPrint(self.allocator, "{s} initrd={s}", .{ cmdline, image.utf8_path }) catch {
                return uefi.Error.OutOfResources;
            };

            self.allocator.free(cmdline);
            cmdline = next;
        }

        return try app.boot(cmdline);
    }

    pub fn wait(_: Loader) uefi.Error!void {
        const system_table = uefi.system_table;

        const boot_service = system_table.boot_services orelse {
            return uefi.Error.Unsupported;
        };

        const con_in = system_table.con_in orelse {
            return uefi.Error.Unsupported;
        };

        const events = [_]uefi.Event{con_in.wait_for_key};

        _ = try boot_service.waitForEvent(&events);
    }
};
