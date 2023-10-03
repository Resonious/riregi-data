const std = @import("std");
const data = @import("data.zig");

const CURRENT_VERSION = 2;

pub fn perform(app: *data.ActiveAppState) void {
    var metadata = app.metadata();
    std.debug.assert(@sizeOf(data.Order) == 272);

    while (metadata.version < CURRENT_VERSION) {
        defer metadata.version += 1;

        // Version 1->2: populate order timestamps
        if (metadata.version == 1) {
            var orders = app.orders();
            for (0..orders.len - 1) |i| {
                if (orders[i].timestamp == 0) {
                    orders[i].timestamp = 1696236813000;
                }
            }
        }
    }
}

const testing = std.testing;

test "version 1->2" {
    const cwd = std.fs.cwd();
    try cwd.deleteTree("zig-cache/migrationtest1");
    try cwd.makeDir("zig-cache/migrationtest1");

    // Start session
    const dir_path = "zig-cache/migrationtest1";
    var app = try data.ActiveAppState.new(testing.allocator, dir_path);
    defer testing.allocator.destroy(app);
    defer app.deinit();

    // Pretend version is 1 and timestamp is 0
    app.metadata().version = 1;
    try app.completeOrder();

    app.orders()[0].timestamp = 0;
    try testing.expectEqual(app.orders()[0].timestamp, 0);

    perform(app);

    try testing.expect(app.metadata().version != 1);
    try testing.expectEqual(app.orders()[0].timestamp, 1696236813000);
}
