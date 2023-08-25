const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Vector = @import("vector.zig").Vector;

const wildcard: []const u8 = "*";

const RouteKind = enum {
    Empty,
    ForwardSlash,
    Wildcard,
    Custom,
};

pub fn Router(comptime V: type) type {
    return struct {
        _allocator: Allocator,
        /// Private field
        _root_route: Route(V),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            var new_router = .{
                ._allocator = allocator,
                ._root_route = Route(V).init(allocator),
            };
            new_router._root_route._is_root = true;
            return new_router;
        }

        pub fn deinit(self: *Self) void {
            (&self._root_route).deinit();
        }

        pub fn put(self: *Self, path: []const u8, handler: V) !void {
            var splitted = try splitPath(self._allocator, path);
            defer splitted.deinit();
            try self._root_route.putSlice(splitted.slice(), handler);
        }

        pub fn get(self: *Self, path: []const u8) !?V {
            var splitted = try splitPath(self._allocator, path);
            defer splitted.deinit();
            return self._root_route.getSlice(splitted.slice());
        }
    };
}

pub fn Route(comptime V: type) type {
    return struct {
        allocator: Allocator,
        _root_handler: ?V,
        _kind: RouteKind,
        _name: ?[]const u8,
        _children: std.StringHashMap(Route(V)),
        _is_root: bool,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                ._root_handler = null,
                ._children = std.StringHashMap(Route(V)).init(allocator),
                ._kind = RouteKind.Empty,
                ._name = null,
                ._is_root = false,
            };
        }

        pub fn deinit(self: *Self) void {
            var size = self._children.count();
            defer self._children.deinit();

            if (size > 0) {
                var it = (&self._children).iterator();
                var entry = it.next();

                while (entry != null) : (entry = it.next()) {
                    var r = entry.?.value_ptr.*;
                    r.deinit();
                    self.allocator.free(entry.?.key_ptr.*);
                }
            }

            if (self._root_handler != null) {
                self._root_handler = null;
            }
        }

        fn putSlice(self: *Self, path: [][]const u8, handler: V) !void {
            if (path.len == 0) {
                // self._root_handler = handler;
                // self._kind = RouteKind.ForwardSlash;
                unreachable;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                self._root_handler = handler;
                self._kind = RouteKind.ForwardSlash;
                return;
            }

            if (path[0].len == 0) {
                unreachable;
            }

            var child_route_match: []const u8 = undefined;
            var child_route_name: []const u8 = undefined;
            var child_route_kind = RouteKind.Empty;

            if (path[0][0] == ':') {
                child_route_match = wildcard;
                child_route_name = path[0][1..];
                child_route_kind = RouteKind.Wildcard;
            } else {
                child_route_match = path[0];
                child_route_name = path[0];
                child_route_kind = RouteKind.Custom;
            }

            var r = self._children.getPtr(child_route_match);
            if (r) |route| {
                try route.putSlice(path[1..], handler);
                return;
            }

            var key_copy = try self.allocator.dupe(u8, child_route_match);
            var child = Route(V).init(self.allocator);
            child._kind = child_route_kind;
            child._name = child_route_name;

            if (path.len == 1) {
                child._root_handler = handler;
            } else {
                try child.putSlice(path[1..], handler);
            }

            try self._children.put(key_copy, child);
        }

        fn getSlice(self: *Self, path: [][]const u8) ?V {
            if (path.len == 0) {
                // if (self._name == )
                return self._root_handler;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                return self._root_handler;
            }

            if (self._children.getPtr(path[0])) |child| {
                return child.getSlice(path[1..]);
            }

            if (self._children.getPtr(wildcard)) |child| {
                return child.getSlice(path[1..]);
            }

            return null;
        }
    };
}

pub fn Match(comptime V: type) type {
    return struct {
        path: []const u8,
        item: V,
    };
}

/// Extract path parameters from a path.
/// Ex:
/// var params = ExtractParamsFromPath(std.heap.page_allocator, "/users/:user", req.path)
/// std.debug.print("{}", .{params.get("user")})
pub fn ExtractParamsFromPath(allocator: Allocator, template_path: []const u8, src_path: []const u8) !std.StringHashMap([]const u8) {
    var m = std.StringHashMap([]const u8).init(allocator);

    var v_template = try splitPath(allocator, template_path);
    defer v_template.deinit();
    var v_src = try splitPath(allocator, src_path);
    defer v_src.deinit();

    var s_template = v_template.slice();
    var s_src = v_src.slice();

    for (s_src, 0..) |i_src, i| {
        if (s_template.len <= i) {
            break;
        }

        if (i_src.len < 1) {
            continue;
        }

        var i_template = s_template[i];

        if (i_template.len < 1) {
            continue;
        }

        if (i_template[0] != ':') {
            continue;
        }

        var bit = i_template[1..];
        try m.put(bit, i_src);
    }

    return m;
}

fn splitPath(allocator: Allocator, path: []const u8) !Vector([]const u8) {
    if (path.len == 0) {
        return try Vector([]const u8).init(allocator, 1);
    }

    var fpath: []const u8 = undefined;

    if (path[0] == '/') {
        fpath = path[1..];
    } else {
        fpath = path;
    }

    var slice = std.mem.split(u8, fpath, "/");

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

test "extract_params_from_path" {
    var p_tpl: []const u8 = "/users/:user/say-hello";
    var p_src: []const u8 = "/users/mike/say-hello/ok";

    var m = try ExtractParamsFromPath(std.testing.allocator, p_tpl, p_src);
    defer m.deinit();

    var umike = m.get("user") orelse unreachable;

    try testing.expect(std.mem.eql(u8, umike, "mike"));
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
    const r4 = try router.get("/unknown");
    try testing.expect(r4 == null);
}
