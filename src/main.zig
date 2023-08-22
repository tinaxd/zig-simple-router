const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Vector = @import("vector.zig").Vector;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

pub fn Router(comptime V: type) type {
    return struct {
        allocator: Allocator,
        root_route: Route(V),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .root_route = Route(V).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            (&self.root_route).deinit();
        }

        pub fn put(self: *Self, path: []const u8, handler: V) !void {
            var splitted = try splitPath(self.allocator, path);
            defer splitted.deinit();
            try self.root_route.putSlice(splitted.slice(), handler);
        }
    };
}

pub fn Route(comptime V: type) type {
    return struct {
        allocator: Allocator,
        root_handler: ?V,
        children: std.StringHashMap(Route(V)),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .root_handler = null,
                .children = std.StringHashMap(Route(V)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var size = self.children.count();
            defer self.children.deinit();

            if (size > 0) {
                var it = (&self.children).iterator();
                var entry = it.next();

                while (entry != null) : (entry = it.next()) {
                    var r = entry.?.value_ptr.*;
                    r.deinit();
                    self.allocator.free(entry.?.key_ptr.*);
                }
            }

            if (self.root_handler != null) {
                self.root_handler = null;
            }
        }

        fn putSlice(self: *Self, path: [][]const u8, handler: V) !void {
            if (path.len == 0) {
                self.root_handler = handler;
                return;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                self.root_handler = handler;
                return;
            }

            if (path.len == 1 and path[0].len > 0 and path[0][0] == ':') {
                self.root_handler = handler;
                return;
            }

            for (path, 0..) |path_item, i| {
                _ = i;
                std.debug.print(":) {s} {}\n\n\n", .{ path_item, path_item.len });

                var r = self.children.getPtr(path_item);
                if (r) |route| {
                    try route.putSlice(path[1..], handler);
                    return;
                }

                var key_copy = try self.allocator.dupe(u8, path_item);

                var child = Route(V).init(self.allocator);
                try child.putSlice(path[1..], handler);
                try self.children.put(key_copy, child);
                return;
            }
        }
    };
}

fn splitPath(allocator: Allocator, path: []const u8) !Vector([]const u8) {
    var slice = std.mem.split(u8, path, "/");

    var pathSlice = try Vector([]const u8).init(allocator, 0);

    var nextItem = slice.next();

    while (nextItem != null) : (nextItem = slice.next()) {
        try pathSlice.append(nextItem.?);
    }

    return pathSlice;
}

test "split_path" {
    var splits = try splitPath(std.testing.allocator, "/bacon/ator");
    defer splits.deinit();

    for (splits.slice(), 0..) |item, i| {
        std.debug.print("{s} {}\n", .{ item, i });
    }
}

test "router" {
    var router = Router(u8).init(std.testing.allocator);
    defer router.deinit();
    // try router.put("/", 1);
    // try router.put("/hello", 2);
    try router.put("paris/hello", 2);
}
