const std = @import("std");
const utils = @import("utils");
const volume = @import("volume");

const uefi = std.os.uefi;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;

const ext4_driver = @embedFile("ext4_x64");

pub const Loader = struct {
    allocator: std.mem.Allocator,

    system_table: *uefi.tables.SystemTable,
    boot_service: *uefi.tables.BootServices,

    con_out: *uefi.protocol.SimpleTextOutput,
    con_in: *uefi.protocol.SimpleTextInput,

    geo: uefi.protocol.SimpleTextOutput.Geometry,

    applications: std.ArrayList(volume.Entry),

    pub fn init(allocator: std.mem.Allocator, system_table: *uefi.tables.SystemTable) uefi.Error!Loader {
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
            .allocator = allocator,
            .system_table = system_table,
            .boot_service = boot_service,
            .con_out = con_out,
            .con_in = con_in,
            .geo = geo,
            .applications = .empty,
        };
    }

    pub fn deinit(self: *Loader) void {
        for (self.applications.items) |*app| {
            app.deinit();
        }

        self.applications.deinit(self.allocator);
    }

    fn show_error(self: *Loader, comptime description: []const u8, err: anyerror) uefi.Error!void {
        try self.con_out.clearScreen();
        try self.con_out.setMode(self.con_out.mode.mode);

        var title_pad: usize = 0;
        const title_msg = std.unicode.utf8ToUtf16LeStringLiteral("boot failed");

        if (self.geo.columns > title_msg.len) {
            title_pad = (self.geo.columns - title_msg.len) / 2;
        }

        try self.con_out.setCursorPosition(title_pad, 0);
        try self.con_out.setAttribute(.{ .foreground = .white, .background = .black });
        _ = try self.con_out.outputString(title_msg.ptr);

        var error_pad: usize = 0;
        const error_msg = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, @errorName(err)) catch {
            return uefi.Error.OutOfResources;
        };
        defer self.allocator.free(error_msg);

        if (self.geo.columns > error_msg.len) {
            error_pad = (self.geo.columns - error_msg.len) / 2;
        }

        try self.con_out.setCursorPosition(error_pad, 2);
        try self.con_out.setAttribute(.{ .foreground = .white, .background = .red });
        _ = try self.con_out.outputString(error_msg.ptr);

        var description_pad: usize = 0;
        const description_msg = std.unicode.utf8ToUtf16LeStringLiteral(description);

        if (self.geo.columns > description.len) {
            description_pad = (self.geo.columns - description.len) / 2;
        }

        try self.con_out.setCursorPosition(description_pad, 3);
        _ = try self.con_out.outputString(description_msg.ptr);

        var reboot_pad: usize = 0;
        const reboot_msg = std.unicode.utf8ToUtf16LeStringLiteral("Press any key to reboot...");

        if (self.geo.columns > reboot_msg.len) {
            reboot_pad = (self.geo.columns - reboot_msg.len) / 2;
        }

        try self.con_out.setAttribute(.{ .foreground = .yellow, .background = .black });
        try self.con_out.setCursorPosition(reboot_pad, 5);
        _ = try self.con_out.outputString(reboot_msg.ptr);

        const events = [_]uefi.Event{self.con_in.wait_for_key};
        _ = try self.boot_service.waitForEvent(&events);
    }

    fn load_ext4_driver(self: *Loader) uefi.Error!void {
        const driver = self.boot_service.loadImage(false, uefi.handle, .{ .buffer = ext4_driver }) catch |err| {
            return try self.show_error("failed to load ext4 driver image", err);
        };

        _ = self.boot_service.startImage(driver) catch |err| {
            return try self.show_error("failed to start ext4 driver", err);
        };

        const controllers = self.boot_service.locateHandleBuffer(.{ .by_protocol = &uefi.protocol.BlockIo.guid }) catch |err| {
            return try self.show_error("failed to locate block devices for ext4 driver", err);
        } orelse {
            return try self.show_error("no block devices found for ext4 driver", uefi.Error.NotFound);
        };

        defer self.boot_service.freePool(@ptrCast(@alignCast(controllers.ptr))) catch {};

        for (controllers) |controller| {
            _ = self.boot_service.connectController(controller, null, null, true) catch {
                continue;
            };
        }
    }

    pub fn bootstrap(self: *Loader) uefi.Error!void {
        try self.load_ext4_driver();

        const handles = self.boot_service.locateHandleBuffer(.{ .by_protocol = &SimpleFileSystem.guid }) catch |err| {
            return try self.show_error("failed to query filesystem handles", err);
        } orelse {
            return try self.show_error("no filesystem found on any device", uefi.Error.NotFound);
        };

        defer self.boot_service.freePool(@ptrCast(@alignCast(handles.ptr))) catch {};

        for (handles) |handle| {
            var vol = volume.Volume.init(self.allocator, handle);

            vol.scan() catch {
                vol.deinit();
                continue;
            };

            for (vol.applications.items) |*app| {
                self.applications.append(self.allocator, app.*) catch |err| {
                    defer vol.deinit();
                    return try self.show_error("out of memory while registering boot entries", err);
                };
            }
        }

        if (self.applications.items.len == 0) {
            return try self.show_error("no bootable entry found on any volume", error.BootImageNotFound);
        }
    }

    pub fn boot(self: *Loader, selected: usize) uefi.Error!void {
        var app = self.applications.items[selected];

        switch (app.bootloader) {
            .Efi => {
                const exit = app.boot(null) catch |err| {
                    return try self.show_error("failed to start EFI application", err);
                };

                if (exit.code != .success) {
                    return try self.show_error("EFI application exited with a non-success status", error.ExitCodeIsNotSuccess);
                }

                return;
            },
            .Image => {
                return try self.show_error("a standalone image (e.g. initrd) cannot be booted directly", uefi.Error.InvalidParameter);
            },
            .Kernel => |*kernel| {
                var utf8_cmdline = std.fmt.allocPrint(self.allocator, "root=PARTUUID={s} rw", .{kernel.part_uuid}) catch |err| {
                    return try self.show_error("failed to build kernel command line", err);
                };
                defer self.allocator.free(utf8_cmdline);

                for (self.applications.items) |application| {
                    if (application.type != .Image) {
                        continue;
                    }

                    const image = application.bootloader.Image;

                    if (!std.ascii.eqlIgnoreCase(image.part_uuid, kernel.part_uuid)) {
                        continue;
                    }

                    if (!utils.extension.is_initrd(image.path)) {
                        continue;
                    }

                    const next = std.fmt.allocPrint(self.allocator, "{s} initrd={s}", .{ utf8_cmdline, image.utf8_path }) catch |err| {
                        return try self.show_error("failed to append initrd to kernel command line", err);
                    };

                    self.allocator.free(utf8_cmdline);
                    utf8_cmdline = next;
                }

                const utf16_cmdline = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, utf8_cmdline) catch |err| {
                    return try self.show_error("failed to build kernel command line", err);
                };
                defer self.allocator.free(utf16_cmdline);

                const exit = app.boot(utf16_cmdline) catch |err| {
                    return try self.show_error("failed to start kernel image", err);
                };

                if (exit.code != .success) {
                    return try self.show_error("kernel image exited with a non-success status", error.ExitCodeIsNotSuccess);
                }

                return;
            },
        }
    }
};
