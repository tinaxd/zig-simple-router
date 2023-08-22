const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Vector = @import("vector.zig").Vector;

// export fn add(a: i32, b: i32) i32 {
//     return a + b;
// }

// test "basic add functionality" {
//     try testing.expect(add(3, 7) == 10);
// }

pub fn Router(comptime V: type) type {
    return struct {
        allocator: Allocator,
        /// Private field
        priv_root_route: Route(V),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .priv_root_route = Route(V).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            (&self.priv_root_route).deinit();
        }

        pub fn put(self: *Self, path: []const u8, handler: V) !void {
            var splitted = try splitPath(self.allocator, path);
            defer splitted.deinit();
            try self.priv_root_route.putSlice(splitted.slice(), handler);
        }

        pub fn get(self: *Self, path: []const u8) !?V {
            var splitted = try splitPath(self.allocator, path);
            defer splitted.deinit();
            return self.priv_root_route.getSlice(splitted.slice());
        }
    };
}

pub fn Route(comptime V: type) type {
    return struct {
        allocator: Allocator,
        /// Private field
        priv_root_handler: ?V,
        /// Private field
        priv_children: std.StringHashMap(Route(V)),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .priv_root_handler = null,
                .priv_children = std.StringHashMap(Route(V)).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var size = self.priv_children.count();
            defer self.priv_children.deinit();

            if (size > 0) {
                var it = (&self.priv_children).iterator();
                var entry = it.next();

                while (entry != null) : (entry = it.next()) {
                    var r = entry.?.value_ptr.*;
                    r.deinit();
                    self.allocator.free(entry.?.key_ptr.*);
                }
            }

            if (self.priv_root_handler != null) {
                self.priv_root_handler = null;
            }
        }

        fn putSlice(self: *Self, path: [][]const u8, handler: V) !void {
            if (path.len == 0) {
                self.priv_root_handler = handler;
                return;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                self.priv_root_handler = handler;
                return;
            }

            if (path.len == 1 and path[0].len > 0 and path[0][0] == ':') {
                self.priv_root_handler = handler;
                return;
            }

            for (path) |path_item| {
                var r = self.priv_children.getPtr(path_item);
                if (r) |route| {
                    try route.putSlice(path[1..], handler);
                    return;
                }

                var key_copy = try self.allocator.dupe(u8, path_item);

                var child = Route(V).init(self.allocator);
                try child.putSlice(path[1..], handler);
                try self.priv_children.put(key_copy, child);
                return;
            }
        }

        fn getSlice(self: *Self, path: [][]const u8) ?V {
            if (path.len == 0) {
                return self.priv_root_handler;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                return self.priv_root_handler;
            }

            for (path) |path_item| {
                var r = self.priv_children.getPtr(path_item);
                if (r) |route| {
                    return route.getSlice(path[1..]);
                }

                return self.priv_root_handler;
            }

            return null;
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
    try router.put("/", 1);
    try router.put("/hello", 2);
    try router.put("/paris/:id", 3);

    const r1 = try router.get("/");
    try testing.expect(r1.? == 1);
    const r2 = try router.get("/hello");
    try testing.expect(r2.? == 2);
    const r3 = try router.get("/paris/123");
    try testing.expect(r3 != null);
    try testing.expect(r3.? == 3);
    const r4 = try router.get("/unknown"); //TODO: fix this (this is returning 1, same as "/")
    try testing.expect(r4 == null);
}
