const std = @import("std");
const fs = std.fs;
const os = std.os;
const mem = std.mem;
const fmt = std.fmt;
const time = std.time;

pub const MMapPtr = []align(mem.page_size) u8;

pub const MMappedFile = struct {
    initialized: bool,
    file: fs.File,
    ptr: MMapPtr,

    const Self = @This();

    pub fn open(dir: fs.Dir, file_name: []const u8, bytesize: u64) !Self {
        var file = try dir.createFile(file_name, .{ .read = true, .truncate = false });
        errdefer file.close();

        var file_size = (try file.stat()).size;

        if (file_size < bytesize) {
            try os.ftruncate(file.handle, bytesize);
        }

        var self = try init(file, bytesize);
        errdefer self.deinit();

        return self;
    }

    pub fn init(file: fs.File, bytelen: u64) !Self {
        var ptr = os.mmap(
            null,
            @intCast(bytelen),
            os.PROT.READ | os.PROT.WRITE,
            os.MAP.SHARED,
            file.handle,
            0,
        ) catch |e| {
            file.close();
            return e;
        };

        return .{
            .initialized = true,
            .file = file,
            .ptr = ptr,
        };
    }

    pub fn deinit(self: *Self) void {
        os.munmap(self.ptr);
        self.file.close();
        self.initialized = false;
    }

    pub fn resize(self: *Self, new_size: u64) !void {
        std.debug.assert(self.initialized);
        os.munmap(self.ptr);
        errdefer deinit(self);

        try os.ftruncate(self.file.handle, new_size);
        self.* = try init(self.file, new_size);
    }
};

pub const MenuItem = extern struct {
    price: i64,
    name: [256:0]u8 = undefined,
    image_path: [512:0]u8 = undefined,
};

pub const Metadata = extern struct {
    // Version number lets us do "migrations" if we need to change data.
    version: i32,

    /// Number of MenuItems inside the menu file.
    menu_len: u32,

    /// Number of Orders in the orders file.
    orders_len: u64,

    /// Serial number of the current order.
    current_order_num: u64,

    const Self = @This();
};

pub const Order = extern struct {
    total: i64 = 0,
    item_count: u32 = 0,

    /// Epoch time in MS.
    timestamp: i64 = 0,

    /// Arbitrary identifier of how the customer paid.
    payment_method: u16 = 0,

    /// Maybe stupid but in case I want to add more fields without hell.
    padding: [246]u8 = undefined,
};

pub var init_state: []const u8 = "not started";

pub const ActiveAppState = struct {
    metadata_file: MMappedFile,
    menu_file: MMappedFile,
    orders_file: MMappedFile,
    current_order_items_file: MMappedFile,
    order_items_dir: fs.Dir,

    const Self = @This();

    pub fn new(allocator: mem.Allocator, dir_path: []const u8) !*Self {
        const cwd = fs.cwd();

        var result = try allocator.create(ActiveAppState);
        errdefer allocator.destroy(result);

        init_state = "opening data dir";
        var dir = try cwd.openDir(dir_path, .{});
        defer dir.close();

        init_state = "opening metadata";
        result.metadata_file = try MMappedFile.open(dir, "rr_metadata", @intCast(@sizeOf(Metadata)));
        errdefer result.metadata_file.deinit();

        // TODO: metadata version will be 0 for a fresh install. this means migrations will run
        // for a fresh install which might be weird? I guess it works though.

        init_state = "opening menu file";
        result.menu_file = try MMappedFile.open(dir, "rr_menu", @sizeOf(MenuItem) * 32);
        errdefer result.menu_file.deinit();

        init_state = "opening orders file";
        result.orders_file = try MMappedFile.open(dir, "rr_orders", @sizeOf(Order) * 32);
        errdefer result.orders_file.deinit();

        // Here I want to make sure we always have a current orders file.
        dir.makeDir("rr_orderitems") catch {};
        init_state = "opening order items dir";
        result.order_items_dir = try dir.openDir("rr_orderitems", .{});
        errdefer result.order_items_dir.close();

        // Open order items file for current order.
        {
            var buf: [16]u8 = undefined;
            const order_num = result.metadata().current_order_num;
            const order_items_file_path = fmt.bufPrint(buf[0..], "{}", .{order_num}) catch unreachable;
            init_state = "opening current order items file";
            result.current_order_items_file = try MMappedFile.open(result.order_items_dir, order_items_file_path, @sizeOf(MenuItem) * 4);
        }

        // Should always have 1 order, as one is opened by default.
        if (result.metadata().orders_len == 0) {
            result.metadata().orders_len = 1;
        }

        init_state = "done";
        return result;
    }

    pub fn deinit(self: *Self) void {
        self.metadata_file.deinit();
        self.menu_file.deinit();
        self.orders_file.deinit();
        self.order_items_dir.close();
        self.current_order_items_file.deinit();
    }

    pub fn metadata(self: *Self) *Metadata {
        return @ptrCast(self.metadata_file.ptr);
    }

    pub fn menuLen(self: *Self) u32 {
        return self.metadata().menu_len;
    }

    pub fn menu(self: *Self) []MenuItem {
        var menu_items_arr: [*]MenuItem = @ptrCast(self.menu_file.ptr.ptr);
        return menu_items_arr[0..self.menuLen()];
    }

    pub fn addMenuItem(self: *Self, item: MenuItem) !*MenuItem {
        const current_menu_len_in_bytes = self.menuLen() * @sizeOf(MenuItem);
        if (current_menu_len_in_bytes >= self.menu_file.ptr.len) {
            try self.menu_file.resize(current_menu_len_in_bytes * 2);
        }

        var menu_items_arr: [*]MenuItem = @ptrCast(self.menu_file.ptr.ptr);
        const i = self.menuLen();
        menu_items_arr[i] = item;
        self.metadata().menu_len += 1;
        return &menu_items_arr[i];
    }

    pub fn removeMenuItem(self: *Self, index: usize) void {
        var menu_slice = self.menu();

        // Shift everything over.
        for (index..menu_slice.len - 1) |i| {
            menu_slice[i] = menu_slice[i + 1];
        }

        // Subtract len.
        self.metadata().menu_len -= 1;
    }

    pub fn orders(self: *Self) []Order {
        var order_arr: [*]Order = @ptrCast(self.orders_file.ptr.ptr);
        return order_arr[0..@intCast(self.ordersLen())];
    }

    pub fn ordersLen(self: *Self) u64 {
        return self.metadata().orders_len;
    }

    pub fn currentOrder(self: *Self) *Order {
        const i: usize = @intCast(self.metadata().current_order_num);
        return &self.orders()[i];
    }

    pub fn currentOrderItemsCount(self: *Self) u32 {
        const i: usize = @intCast(self.metadata().current_order_num);
        return self.orders()[i].item_count;
    }

    pub fn currentOrderItems(self: *Self) []MenuItem {
        var current_order_items_arr: [*]MenuItem = @ptrCast(self.current_order_items_file.ptr.ptr);
        return current_order_items_arr[0..@intCast(self.currentOrder().item_count)];
    }

    pub fn removeCurrentOrderItem(self: *Self, index: usize) void {
        var items_slice = self.currentOrderItems();

        var order = self.currentOrder();

        order.total -= items_slice[index].price;

        // Shift everything over.
        for (index..items_slice.len - 1) |i| {
            items_slice[i] = items_slice[i + 1];
        }

        // Subtract len.
        order.item_count -= 1;
    }

    pub fn addItemToOrder(self: *Self, menu_item_index: usize) !*MenuItem {
        const current_order_len_in_bytes = self.currentOrder().item_count * @sizeOf(MenuItem);
        if (current_order_len_in_bytes >= self.current_order_items_file.ptr.len) {
            try self.current_order_items_file.resize(current_order_len_in_bytes * 2);
        }

        const order = self.currentOrder();

        var order_items_arr: [*]MenuItem = @ptrCast(self.current_order_items_file.ptr.ptr);
        const i = order.item_count;
        order_items_arr[i] = self.menu()[menu_item_index];
        order.item_count += 1;
        order.total += order_items_arr[i].price;
        return &order_items_arr[i];
    }

    pub fn completeOrder(self: *Self) !void {
        const current_orders_len_in_bytes = self.ordersLen() * @sizeOf(Order);
        if (current_orders_len_in_bytes >= self.orders_file.ptr.len) {
            try self.orders_file.resize(current_orders_len_in_bytes * 2);
        }

        self.currentOrder().timestamp = time.milliTimestamp();

        var orders_arr: [*]Order = @ptrCast(self.orders_file.ptr.ptr);
        const i = self.ordersLen();
        orders_arr[@intCast(i)] = Order{};
        self.metadata().orders_len += 1;
        self.metadata().current_order_num += 1;

        // Open the next order file
        var buf: [16]u8 = undefined;
        const order_num = self.metadata().current_order_num;
        const order_items_file_path = fmt.bufPrint(buf[0..], "{}", .{order_num}) catch unreachable;
        self.current_order_items_file.deinit();
        self.current_order_items_file = try MMappedFile.open(self.order_items_dir, order_items_file_path, @sizeOf(MenuItem) * 4);
    }
};
