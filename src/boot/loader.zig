const std = @import("std");
const utils = @import("utils");
const volume = @import("volume");
const system = @import("system");

const uefi = std.os.uefi;
const SimpleFileSystem = uefi.protocol.SimpleFileSystem;

const ext4_driver = @embedFile("ext4_x64");

pub const Loader = struct {
    allocator: std.mem.Allocator,

    applications: std.ArrayList(volume.Entry),

    service: system.Service,

    pub fn init(allocator: std.mem.Allocator) uefi.Error!Loader {
        const service = try system.Service.init();

        return .{
            .allocator = allocator,
            .applications = .empty,
            .service = service,
        };
    }

    pub fn deinit(self: *Loader) void {
        for (self.applications.items) |*app| {
            app.deinit();
        }

        self.applications.deinit(self.allocator);
    }

    fn show_error(self: *Loader, comptime description: []const u8, err: anyerror) uefi.Error!void {
        try self.service.con_out.clearScreen();
        try self.service.con_out.setMode(self.service.con_out.mode.mode);

        var title_pad: usize = 0;
        const title_msg = std.unicode.utf8ToUtf16LeStringLiteral("boot failed");

        if (self.service.geo.columns > title_msg.len) {
            title_pad = (self.service.geo.columns - title_msg.len) / 2;
        }

        try self.service.con_out.setCursorPosition(title_pad, 0);
        try self.service.con_out.setAttribute(.{ .foreground = .white, .background = .black });
        _ = try self.service.con_out.outputString(title_msg.ptr);

        var error_pad: usize = 0;
        const error_msg = std.unicode.utf8ToUtf16LeAllocZ(self.allocator, @errorName(err)) catch {
            return uefi.Error.OutOfResources;
        };
        defer self.allocator.free(error_msg);

        if (self.service.geo.columns > error_msg.len) {
            error_pad = (self.service.geo.columns - error_msg.len) / 2;
        }

        try self.service.con_out.setCursorPosition(error_pad, 2);
        try self.service.con_out.setAttribute(.{ .foreground = .white, .background = .red });
        _ = try self.service.con_out.outputString(error_msg.ptr);

        var description_pad: usize = 0;
        const description_msg = std.unicode.utf8ToUtf16LeStringLiteral(description);

        if (self.service.geo.columns > description.len) {
            description_pad = (self.service.geo.columns - description.len) / 2;
        }

        try self.service.con_out.setCursorPosition(description_pad, 3);
        _ = try self.service.con_out.outputString(description_msg.ptr);

        var reboot_pad: usize = 0;
        const reboot_msg = std.unicode.utf8ToUtf16LeStringLiteral("Press any key to reboot...");

        if (self.service.geo.columns > reboot_msg.len) {
            reboot_pad = (self.service.geo.columns - reboot_msg.len) / 2;
        }

        try self.service.con_out.setAttribute(.{ .foreground = .yellow, .background = .black });
        try self.service.con_out.setCursorPosition(reboot_pad, 5);
        _ = try self.service.con_out.outputString(reboot_msg.ptr);

        const events = [_]uefi.Event{self.service.con_in.wait_for_key};
        _ = try self.service.boot.waitForEvent(&events);
    }

    fn load_ext4_driver(self: *Loader) uefi.Error!void {
        const driver = self.service.boot.loadImage(false, uefi.handle, .{ .buffer = ext4_driver }) catch |err| {
            return try self.show_error("failed to load ext4 driver image", err);
        };

        _ = self.service.boot.startImage(driver) catch |err| {
            return try self.show_error("failed to start ext4 driver", err);
        };

        const controllers = self.service.boot.locateHandleBuffer(.{ .by_protocol = &uefi.protocol.BlockIo.guid }) catch |err| {
            return try self.show_error("failed to locate block devices for ext4 driver", err);
        } orelse {
            return try self.show_error("no block devices found for ext4 driver", uefi.Error.NotFound);
        };

        defer self.service.boot.freePool(@ptrCast(@alignCast(controllers.ptr))) catch {};

        for (controllers) |controller| {
            _ = self.service.boot.connectController(controller, null, null, true) catch {
                continue;
            };
        }
    }

    pub fn bootstrap(self: *Loader) uefi.Error!usize {
        try self.load_ext4_driver();

        const max = std.math.maxInt(usize);

        const handles = self.service.boot.locateHandleBuffer(.{ .by_protocol = &SimpleFileSystem.guid }) catch |err| {
            try self.show_error("failed to query filesystem handles", err);
            return max;
        } orelse {
            try self.show_error("no filesystem found on any device", uefi.Error.NotFound);
            return max;
        };

        defer self.service.boot.freePool(@ptrCast(@alignCast(handles.ptr))) catch {};

        for (handles) |handle| {
            volume.scan(self.allocator, self.service, &self.applications, handle) catch {
                continue;
            };
        }

        if (self.applications.items.len == 0) {
            try self.show_error("no bootable entry found on any volume", error.BootImageNotFound);
            return max;
        }

        const last_boot_state_name = std.unicode.utf8ToUtf16LeStringLiteral("LastBooted");

        const buffer = system.nvram.creaft_buffer(self.allocator, self.service, last_boot_state_name) catch {
            return max;
        } orelse {
            return max;
        };
        defer self.allocator.free(buffer);

        const value = system.nvram.read(self.service, buffer, last_boot_state_name) catch {
            return max;
        } orelse {
            return max;
        };

        if (value.len != 2) {
            return max;
        }

        if (self.applications.items.len != @as(usize, value[0])) {
            return max;
        }

        const booted = @as(usize, value[1]);

        return booted;
    }

    pub fn boot(self: *Loader, booted: usize, selected: usize) uefi.Error!void {
        var app = self.applications.items[selected];

        if (booted != selected) {
            const last_boot_state_name = std.unicode.utf8ToUtf16LeStringLiteral("LastBooted");

            const u8_app_len = std.math.cast(u8, self.applications.items.len) orelse {
                return try self.show_error("too many boot entries", error.Overflow);
            };

            const u8_selected = std.math.cast(u8, selected) orelse {
                return try self.show_error("too many boot entries", error.Overflow);
            };

            const value: [2]u8 = .{ u8_app_len, u8_selected };

            system.nvram.write(self.service, last_boot_state_name, &value) catch {};
        }

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
                var utf8_cmdline = self.allocator.print("root=PARTUUID={s} rw", .{kernel.part_uuid}) catch |err| {
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

                    const next = self.allocator.print("{s} initrd={s}", .{ utf8_cmdline, image.utf8_path }) catch |err| {
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
