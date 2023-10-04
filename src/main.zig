const std = @import("std");
const fs = std.fs;
const os = std.os;
const mem = std.mem;
const fmt = std.fmt;

const migrations = @import("migration.zig");

const data = @import("data.zig");
const Metadata = data.Metadata;
const MenuItem = data.MenuItem;
const Order = data.Order;
const MMappedFile = data.MMappedFile;
const MMapPtr = data.MMapPtr;
const ActiveAppState = data.ActiveAppState;

var rr_error_string: [512]u8 = mem.zeroes([512]u8);

var gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = false }) = .{};
var allocator = gpa.allocator();

export fn rr_get_error() [*c]const u8 {
    if (rr_error_string[0] == 0) return null;
    return &rr_error_string[0];
}

export fn rr_start(dir_path_ptr: [*:0]const u8, dir_path_len: u32) ?*anyopaque {
    const dir_path = dir_path_ptr[0..dir_path_len];

    const result = ActiveAppState.new(allocator, dir_path) catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Failed to start ({}) (init: {s})", .{ e, data.init_state }) catch unreachable;
        return null;
    };

    migrations.perform(result);

    return @ptrCast(result);
}

export fn rr_cleanup(app_state_ptr: *anyopaque) void {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    app_state.deinit();
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
        .price = price,
    }) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Filesystem error", .{}) catch unreachable;
        return 0;
    };

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

export fn rr_menu_update(
    app_state_ptr: *anyopaque,
    index: u32,
    price: i64,
    name: [*c]const u8,
    name_len: u32,
    image_path: [*c]const u8,
    image_path_len: u32,
) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, app_state.menuLen(), "Menu")) {
        return 0;
    }

    var menu_item = MenuItem{
        .price = price,
    };

    _ = std.fmt.bufPrintZ(&menu_item.name, "{s}", .{name[0..name_len]}) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu item name too long", .{}) catch unreachable;
        return 0;
    };
    _ = std.fmt.bufPrintZ(&menu_item.image_path, "{s}", .{image_path[0..image_path_len]}) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu item image_path too long", .{}) catch unreachable;
        return 0;
    };

    app_state.menu()[index] = menu_item;

    return 1;
}

export fn rr_menu_remove(
    app_state_ptr: *anyopaque,
    index: u32,
) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, app_state.menuLen(), "Menu")) {
        return 0;
    }

    app_state.removeMenuItem(@intCast(index));

    return 1;
}

export fn rr_menu_item_name(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(app_state_ptr, "Menu", "menuLen", "menu", index, "name", [*c]const u8, null);
}

export fn rr_menu_item_image_path(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(app_state_ptr, "Menu", "menuLen", "menu", index, "image_path", [*c]const u8, null);
}

export fn rr_menu_item_price(app_state_ptr: *anyopaque, index: u32) i64 {
    return fetchMenuItemAttr(app_state_ptr, "Menu", "menuLen", "menu", index, "price", i64, 0);
}

export fn rr_menu_item_set_name(
    app_state_ptr: *anyopaque,
    index: u32,
    name: [*c]const u8,
    name_len: u32,
) c_int {
    return setMenuItemStringAttr(app_state_ptr, index, "name", name, name_len);
}

export fn rr_menu_item_set_image_path(
    app_state_ptr: *anyopaque,
    index: u32,
    image_path: [*c]const u8,
    image_path_len: u32,
) c_int {
    return setMenuItemStringAttr(app_state_ptr, index, "image_path", image_path, image_path_len);
}

export fn rr_menu_item_set_price(
    app_state_ptr: *anyopaque,
    index: u32,
    price: i64,
) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, app_state.menuLen(), "Menu")) {
        return 0;
    }

    app_state.menu()[index].price = price;

    return 1;
}

export fn rr_orders_len(app_state_ptr: *anyopaque) u64 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    return app_state.ordersLen();
}

export fn rr_current_order_len(app_state_ptr: *anyopaque) u32 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    return app_state.currentOrder().item_count;
}

export fn rr_current_order_total(app_state_ptr: *anyopaque) i64 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    return app_state.currentOrder().total;
}

export fn rr_current_order_payment_method(app_state_ptr: *anyopaque) u16 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    return app_state.currentOrder().payment_method;
}

export fn rr_current_order_set_payment_method(
    app_state_ptr: *anyopaque,
    payment_method: u16,
) void {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));
    app_state.currentOrder().payment_method = payment_method;
}

export fn rr_order_total(app_state_ptr: *anyopaque, index: u64) i64 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u64, index, app_state.ordersLen(), "Order")) {
        return 0;
    }

    return app_state.orders()[@intCast(index)].total;
}

export fn rr_order_timestamp(app_state_ptr: *anyopaque, index: u64) i64 {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u64, index, app_state.ordersLen(), "Order")) {
        return 0;
    }

    return app_state.orders()[@intCast(index)].timestamp;
}

export fn rr_add_item_to_order(app_state_ptr: *anyopaque, menu_item_index: u32) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, menu_item_index, app_state.menuLen(), "Menu")) {
        return 0;
    }

    _ = app_state.addItemToOrder(@intCast(menu_item_index)) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Filesystem error", .{}) catch unreachable;
        return 0;
    };

    return 1;
}

export fn rr_remove_order_item(app_state_ptr: *anyopaque, index: u32) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, app_state.currentOrder().item_count, "Order item")) {
        return 0;
    }

    app_state.removeCurrentOrderItem(index);

    return 1;
}

export fn rr_order_item_name(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(
        app_state_ptr,
        "Order Item",
        "currentOrderItemsCount",
        "currentOrderItems",
        index,
        "name",
        [*c]const u8,
        null,
    );
}

export fn rr_order_item_image_path(app_state_ptr: *anyopaque, index: u32) [*c]const u8 {
    return fetchMenuItemAttr(
        app_state_ptr,
        "Order Item",
        "currentOrderItemsCount",
        "currentOrderItems",
        index,
        "image_path",
        [*c]const u8,
        null,
    );
}

export fn rr_order_item_price(app_state_ptr: *anyopaque, index: u32) i64 {
    return fetchMenuItemAttr(
        app_state_ptr,
        "Order Item",
        "currentOrderItemsCount",
        "currentOrderItems",
        index,
        "price",
        i64,
        0,
    );
}

export fn rr_complete_order(app_state_ptr: *anyopaque) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    app_state.completeOrder() catch |e| {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Filesystem error while completing order {}", .{e}) catch unreachable;
        return 0;
    };

    return 1;
}

fn isOutOfBounds(
    comptime t: type,
    index: t,
    bounds: t,
    comptime whatisit: []const u8,
) bool {
    if (index >= bounds) {
        _ = fmt.bufPrintZ(rr_error_string[0..], whatisit ++ " index ({}) out of bounds ({})", .{ index, bounds }) catch unreachable;
        return true;
    }
    return false;
}

fn fetchMenuItemAttr(
    app_state_ptr: *anyopaque,
    comptime whatisit: []const u8,
    comptime len_getter: []const u8,
    comptime array_getter: []const u8,
    index: u32,
    comptime field_name: []const u8,
    comptime return_type: type,
    on_not_found: return_type,
) return_type {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, @field(ActiveAppState, len_getter)(app_state), whatisit)) {
        return on_not_found;
    }

    var menu_item = &@field(ActiveAppState, array_getter)(app_state)[index];
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

fn setMenuItemStringAttr(
    app_state_ptr: *anyopaque,
    index: u32,
    comptime field_name: []const u8,
    value: [*c]const u8,
    value_len: u32,
) c_int {
    var app_state = @as(*ActiveAppState, @alignCast(@ptrCast(app_state_ptr)));

    if (isOutOfBounds(u32, index, app_state.menuLen(), "Menu")) {
        return 0;
    }

    _ = std.fmt.bufPrintZ(&@field(app_state.menu()[index], field_name), "{s}", .{value[0..value_len]}) catch {
        _ = fmt.bufPrintZ(rr_error_string[0..], "Menu item " ++ field_name ++ " too long", .{}) catch unreachable;
        return 0;
    };

    return 1;
}

test "rr_start errors when passed a bad path" {
    const dir_path = "zig-cache/fake/does/not/exist\x00";
    const app = rr_start(@ptrCast(dir_path), dir_path.len - 1);

    try testing.expectEqual(app, null);
    try testing.expectStringStartsWith(&rr_error_string, "Failed to start (error.FileNotFound)");
}

test "app functionality" {
    const cwd = fs.cwd();
    try cwd.deleteTree("zig-cache/test1");

    cwd.makeDir("zig-cache/test1") catch |e| {
        if (e != std.os.MakeDirError.PathAlreadyExists) {
            return e;
        }
    };

    // Start session
    const dir_path = "zig-cache/test1\x00";
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

    // Try setting only the name
    {
        const new_name = "new tacos";
        const result = rr_menu_item_set_name(app, 1, new_name, new_name.len);

        if (result != 1) {
            std.log.err("MENU ITEM NAME SET FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.menu_item_edit_failed;
        }

        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 1);
        try testing.expectEqualSentinel(u8, 0, fetched_name[0..10 :0], "new tacos\x00");
    }

    // Populate the current order
    {
        try testing.expectEqual(rr_orders_len(app), 1);
        try testing.expectEqual(rr_current_order_len(app), 0);

        var result = rr_add_item_to_order(app, 1);
        if (result != 1) {
            std.log.err("ORDER ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_item_add_failed;
        }

        try testing.expectEqual(rr_current_order_len(app), 1);
        try testing.expectEqual(rr_current_order_total(app), 300);

        const fetched_name: [*:0]const u8 = rr_order_item_name(app, 0);
        try testing.expectEqualSentinel(u8, 0, fetched_name[0..10 :0], "new tacos\x00");

        result = rr_add_item_to_order(app, 0);
        if (result != 1) {
            std.log.err("ORDER ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_item_add_failed;
        }

        try testing.expectEqual(rr_current_order_len(app), 2);
        try testing.expectEqual(rr_current_order_total(app), 152 + 300);
        try testing.expectEqual(rr_order_timestamp(app, 0), 0);
    }

    // Remove an order item
    {
        const result = rr_remove_order_item(app, 0);
        if (result != 1) {
            std.log.err("ORDER ITEM REMOVE FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_item_remove_failed;
        }

        try testing.expectEqual(rr_current_order_total(app), 152);
        try testing.expectEqual(rr_order_item_price(app, 0), 152);
    }

    // Complete the order
    {
        const result = rr_complete_order(app);
        if (result != 1) {
            std.log.err("ORDER COMPLETION FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_completion_failed;
        }

        try testing.expectEqual(rr_current_order_total(app), 0);
        try testing.expectEqual(rr_order_item_price(app, 0), 0);
        try testing.expectEqual(rr_order_total(app, 0), 152);
        try testing.expect(rr_order_timestamp(app, 0) != 0);
    }

    // Populate new order
    {
        try testing.expectEqual(rr_orders_len(app), 2);
        try testing.expectEqual(rr_current_order_len(app), 0);

        var result = rr_add_item_to_order(app, 1);
        if (result != 1) {
            std.log.err("ORDER ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_item_add_failed;
        }

        rr_current_order_set_payment_method(app, 2);

        try testing.expectEqual(rr_current_order_len(app), 1);
        try testing.expectEqual(rr_current_order_total(app), 300);
        try testing.expectEqual(rr_current_order_payment_method(app), 2);

        const fetched_name: [*:0]const u8 = rr_order_item_name(app, 0);
        try testing.expectEqualSentinel(u8, 0, fetched_name[0..10 :0], "new tacos\x00");

        result = rr_add_item_to_order(app, 0);
        if (result != 1) {
            std.log.err("ORDER ITEM ADD FAILED: {s}", .{rr_error_string[0.. :0]});
            return error.order_item_add_failed;
        }

        try testing.expectEqual(rr_current_order_len(app), 2);
        try testing.expectEqual(rr_current_order_total(app), 152 + 300);
    }

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

test "large numbers of items" {
    const cwd = fs.cwd();
    try cwd.deleteTree("zig-cache/test2");

    cwd.makeDir("zig-cache/test2") catch |e| {
        if (e != std.os.MakeDirError.PathAlreadyExists) {
            return e;
        }
    };

    // Start session
    const dir_path = "zig-cache/test2\x00";
    var app = rr_start(@ptrCast(dir_path), dir_path.len - 1) orelse {
        return error.failed_to_start;
    };

    const ToAdd = struct {
        name: []const u8,
        price: i64,
    };
    const lets_add = [_]ToAdd{
        .{
            .name = "item 1",
            .price = 100,
        },
        .{
            .name = "item 2",
            .price = 200,
        },
        .{
            .name = "item 3",
            .price = 200,
        },
        .{
            .name = "item 4",
            .price = 200,
        },
        .{
            .name = "item 5",
            .price = 250,
        },
    };
    for (lets_add) |add| {
        const result = rr_menu_add(app, add.price, add.name.ptr, @intCast(add.name.len), dir_path, dir_path.len);
        try testing.expectEqual(result, 1);
    }

    // Remove one in the middle
    {
        try testing.expectEqual(rr_menu_len(app), 5);
        const result = rr_menu_remove(app, 2);
        try testing.expectEqual(result, 1);
        try testing.expectEqual(rr_menu_len(app), 4);
    }

    // Make sure it's gone and everything else is shifted
    {
        const real_name = "item 1";
        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 0);
        try testing.expectEqualStrings(fetched_name[0..real_name.len], real_name);
    }
    {
        const real_name = "item 2";
        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 1);
        try testing.expectEqualStrings(fetched_name[0..real_name.len], real_name);
    }
    {
        const real_name = "item 4";
        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 2);
        try testing.expectEqualStrings(fetched_name[0..real_name.len], real_name);
    }
    {
        const real_name = "item 5";
        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 3);
        try testing.expectEqualStrings(fetched_name[0..real_name.len], real_name);
    }
    {
        const fetched_name: [*c]const u8 = rr_menu_item_name(app, 4);
        try testing.expectEqual(fetched_name, null);
    }

    // Now let's make wayyy more to test resize
    for (0..40) |i| {
        const add = ToAdd{
            .price = @intCast(i),
            .name = "dont care",
        };

        const result = rr_menu_add(app, add.price, add.name.ptr, @intCast(add.name.len), dir_path, dir_path.len);
        try testing.expectEqual(result, 1);
    }

    {
        const real_name = "dont care";
        const fetched_name: [*:0]const u8 = rr_menu_item_name(app, 32);
        try testing.expectEqualStrings(fetched_name[0..real_name.len], real_name);
        try testing.expectEqual(rr_menu_item_price(app, 32 + 4), 32);
        try testing.expectEqual(rr_menu_item_price(app, 31 + 4), 31);
        try testing.expectEqual(rr_menu_item_price(app, 36 + 4), 36);
    }

    rr_cleanup(app);
}

const testing = std.testing;
