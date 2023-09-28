const std = @import("std");
const fs = std.fs;
const os = std.os;
const mem = std.mem;
const fmt = std.fmt;

const MMapPtr = []align(mem.page_size) u8;

const MenuItem = extern struct {
    /// 0 means "null", and every number thereafter refers to a variation of this struct that doesn't yet exist.
    version: i32 = 1,
    /// Pretty much the index of this menu item.
    id: u32,
    /// 0 or 1 if the menu item should be shown.
    active: u8 = 1,
    /// Price!
    price: i64,
    name: [256:0]u8 = undefined,
    image_path: [512:0]u8 = undefined,
};

const Metadata = extern struct {
    version: i32,
    menu_len: u32,

    const Self = @This();

    pub fn init() Self {
        return .{
            .version = 1,
            .menu_len = 0,
        };
    }
};

const MMappedFile = struct {
    file: fs.File,
    ptr: MMapPtr,

    const Self = @This();

    pub fn init(file: fs.File, bytelen: usize) !Self {
        var ptr = os.mmap(
            null,
            bytelen,
            os.PROT.READ | os.PROT.WRITE,
            os.MAP.SHARED,
            file.handle,
            0,
        ) catch |e| {
            file.close();
            return e;
        };

        return .{
            .file = file,
            .ptr = ptr,
        };
    }

    pub fn deinit(self: *Self) void {
        os.munmap(self.ptr);
        self.file.close();
    }
};

/// Represents an active session
const ActiveAppState = struct {
    metadata_file: MMappedFile,
    menu_file: MMappedFile,

    const Self = @This();

    fn metadata(self: *Self) *Metadata {
        return @ptrCast(self.metadata_file.ptr);
    }

    fn menuLen(self: *Self) u32 {
        return self.metadata().menu_len;
    }

    fn menu(self: *Self) []MenuItem {
        var menu_items_arr: [*]MenuItem = @ptrCast(self.menu_file.ptr.ptr);
        return menu_items_arr[0..self.menuLen()];
    }

    fn addMenuItem(self: *Self, item: MenuItem) *MenuItem {
        const current_menu_len_in_bytes = self.menuLen() * @sizeOf(MenuItem);
        if (current_menu_len_in_bytes > self.menu_file.ptr.len) {
            @panic("TODO: expand menu file when too many items added?");
        }

        var menu_items_arr: [*]MenuItem = @ptrCast(self.menu_file.ptr.ptr);
        const i = self.menuLen();
        menu_items_arr[i] = item;
        self.metadata().menu_len += 1;
        return &menu_items_arr[i];
    }
};

var rr_error_string: [512]u8 = mem.zeroes([512]u8);

var gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = false }) = .{};
var allocator = gpa.allocator();

export fn rr_get_error() [*c]const u8 {
    if (rr_error_string[0] == 0) return null;
    return &rr_error_string[0];
}

export fn rr_start(dir_path_ptr: [*:0]const u8, dir_path_len: u32) ?*anyopaque {
    const dir_path = dir_path_ptr[0..dir_path_len];
    const cwd = fs.cwd();

    var result = allocator.create(ActiveAppState) catch {
        rr_error_string[0] = 'O';
        rr_error_string[1] = 'O';
        rr_error_string[2] = 'M';
        rr_error_string[3] = 0;
        return null;
    };
    errdefer allocator.destroy(result);

    var dir = cwd.openDir(dir_path, .{}) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to open dir ({})", .{e}) catch unreachable;
        return null;
    };
    defer dir.close();

    var metadata_file = dir.createFile("rr_metadata", .{ .read = true, .truncate = false }) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to open metadata file ({})", .{e}) catch unreachable;
        return null;
    };
    errdefer metadata_file.close();

    var metadata_size = (metadata_file.stat() catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to stat metadata file ({})", .{e}) catch unreachable;
        return null;
    }).size;

    if (metadata_size == 0) {
        os.ftruncate(metadata_file.handle, @sizeOf(Metadata)) catch |e| {
            _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to truncate metadata file ({})", .{e}) catch unreachable;
            return null;
        };
    }

    var menu_file = dir.createFile("rr_menu", .{ .read = true, .truncate = false }) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to open menu file ({})", .{e}) catch unreachable;
        return null;
    };
    errdefer menu_file.close();

    result.metadata_file = MMappedFile.init(metadata_file, @sizeOf(Metadata)) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to mmap metadata file ({})", .{e}) catch unreachable;
        return null;
    };
    errdefer result.metadata_file.deinit();

    var menu_bytes_len = (menu_file.stat() catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to stat menu file ({})", .{e}) catch unreachable;
        return null;
    }).size;

    if (menu_bytes_len == 0) {
        // 32 menu items should be enough to start..
        menu_bytes_len = @sizeOf(MenuItem) * 32;

        os.ftruncate(menu_file.handle, menu_bytes_len) catch |e| {
            _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to truncate menu file ({})", .{e}) catch unreachable;
            return null;
        };
    }

    result.menu_file = MMappedFile.init(menu_file, menu_bytes_len) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to mmap menu file ({})", .{e}) catch unreachable;
        return null;
    };
    errdefer result.menu_file.deinit();

    return @ptrCast(result);
}

export fn rr_cleanup(app_state_ptr: *anyopaque) void {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    app_state.metadata_file.deinit();
    app_state.menu_file.deinit();

    allocator.destroy(app_state);
}

export fn rr_menu_len(app_state_ptr: *anyopaque) u32 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    return app_state.menuLen();
}

/// Returns 1 when successful. When 0, use rr_get_error to know why it failed.
export fn rr_menu_add(
    app_state_ptr: *anyopaque,
    price: i64,
    name: [*c]const u8,
    name_len: u32,
    image_path: [*c]const u8,
    image_path_len: u32,
) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    var menu_item = app_state.addMenuItem(MenuItem{
        .version = 1,
        .id = app_state.menuLen(),
        .active = 1,
        .price = price,
    });

    _ = std.fmt.bufPrintZ(&menu_item.name, "{s}", .{name[0..name_len]}) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu item name too long", .{}) catch unreachable;
        return 0;
    };
    _ = std.fmt.bufPrintZ(&menu_item.image_path, "{s}", .{image_path[0..image_path_len]}) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu item image_path too long", .{}) catch unreachable;
        return 0;
    };

    return 1;
}

export fn rr_menu_item_name(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(app_state_ptr, index, "name", [*c]const u8, null);
}

export fn rr_menu_item_image_path(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(app_state_ptr, index, "image_path", [*c]const u8, null);
}

export fn rr_menu_item_price(app_state_ptr: *anyopaque, index: u32) i64 {
    return fetchMenuItemAttr(app_state_ptr, index, "price", i64, 0);
}

fn fetchMenuItemAttr(
    app_state_ptr: *anyopaque,
    index: u32,
    comptime field_name: []const u8,
    comptime return_type: type,
    on_not_found: return_type,
) return_type {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (index >= app_state.menuLen()) {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu index ({}) out of bounds ({})", .{ index, app_state.menuLen() }) catch unreachable;
        return on_not_found;
    }

    var menu_item = &app_state.menu()[index];
    const field = @typeInfo(@TypeOf(@field(menu_item.*, field_name)));

    switch (field) {
        .Array => {
            return @ptrCast(&@field(menu_item.*, field_name));
        },

        else => {
            return @field(menu_item.*, field_name);
        },
    }
}

test "rr_start errors when passed a bad path" {
    const dir_path = "zig-cache/fake/does/not/exist\x00";
    const app = rr_start(@ptrCast(dir_path), dir_path.len - 1);

    try testing.expectEqual(app, null);
    try testing.expectStringStartsWith(&rr_error_string, "Failed to open dir");
}

test "app functionality" {
    const cwd = fs.cwd();
    try cwd.deleteTree("zig-cache/test");

    cwd.makeDir("zig-cache/test") catch |e| {
        if (e != std.os.MakeDirError.PathAlreadyExists) {
            return e;
        }
    };

    // Start session
    const dir_path = "zig-cache/test\x00";
    var app = rr_start(@ptrCast(dir_path), dir_path.len - 1) orelse {
        std.log.err("FAILED TO START: {s}", .{rr_error_string[0.. :0]});
        return error.failed_to_start;
    };

    // Mess around with the menu
    try testing.expectEqual(rr_menu_len(app), 0);

    {
        const name = "tacos x1";
        const image = "/tmp/img.png";
        const result = rr_menu_add(app, 152, name, name.len, image, image.len);

        if (result != 1) {
            std.log.err("MENU ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.menu_item_add_failed;
        }
    }
    try testing.expectEqual(rr_menu_len(app), 1);
    try testing.expectEqual(rr_menu_item_price(app, 0), 152);

    {
        const name = "tacos x3";
        const image = "/tmp/img2.png";
        const result = rr_menu_add(app, 300, name, name.len, image, image.len);

        if (result != 1) {
            std.log.err("MENU ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.menu_item_add_failed;
        }
    }
    try testing.expectEqual(rr_menu_len(app), 2);
    try testing.expectEqual(rr_menu_item_price(app, 1), 300);

    // Cleanup and then start again. All data should be persisted.
    rr_cleanup(app);
    app = rr_start(@ptrCast(dir_path), dir_path.len - 1) orelse {
        std.log.err("FAILED TO START (2): {s}", .{rr_error_string[0.. :0]});
        return error.failed_to_start;
    };
    try testing.expectEqual(rr_menu_len(app), 2);
    try testing.expectEqual(rr_menu_item_price(app, 0), 152);
    try testing.expectEqual(rr_menu_item_price(app, 1), 300);
    rr_cleanup(app);
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

const testing = std.testing;

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
