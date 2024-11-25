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

const Error = error{
    UndefinedPathBits,
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

        pub fn get(self: *Self, path: []const u8) !?Match(V) {
            var splitted = try splitPath(self._allocator, path);
            defer splitted.deinit();

            var m = try Match(V).init(self._allocator);

            if (try self._root_route.getSlice(splitted.slice(), &m)) {
                return m;
            }
            m.deinit();

            return null;
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
            const size = self._children.count();
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
                child_route_name = path[0];
                child_route_kind = RouteKind.Wildcard;
            } else {
                child_route_match = path[0];
                child_route_name = path[0];
                child_route_kind = RouteKind.Custom;
            }

            const r = self._children.getPtr(child_route_match);
            if (r) |route| {
                try route.putSlice(path[1..], handler);
                return;
            }

            const key_copy = try self.allocator.dupe(u8, child_route_match);
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

        fn getSlice(self: *Self, path: [][]const u8, match_ptr: *Match(V)) !bool {
            if (path.len == 0) {
                if (match_ptr._path_bits != null and self._name != null) {
                    try match_ptr._path_bits.?.append(self._name.?);
                }

                match_ptr.item = self._root_handler;
                return true;
            }

            if (path.len == 1 and std.mem.eql(u8, path[0], "")) {
                if (match_ptr._path_bits != null and self._name != null) {
                    try match_ptr._path_bits.?.append(self._name.?);
                }

                match_ptr.item = self._root_handler;
                return true;
            }

            if (self._children.getPtr(path[0])) |child| {
                if (match_ptr._path_bits != null and self._name != null) {
                    try match_ptr._path_bits.?.append(self._name.?);
                }

                return child.getSlice(path[1..], match_ptr);
            }

            if (self._children.getPtr(wildcard)) |child| {
                if (match_ptr._path_bits != null and self._name != null) {
                    try match_ptr._path_bits.?.append(self._name.?);
                }

                return child.getSlice(path[1..], match_ptr);
            }

            return false;
        }
    };
}

pub fn Match(comptime V: type) type {
    return struct {
        allocator: Allocator,
        item: ?V,
        _path_bits: ?Vector([]const u8),
        _compiled_path: ?[]u8,

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{
                .allocator = allocator,
                .item = null,
                ._path_bits = try Vector([]const u8).init(allocator, 0),
                ._compiled_path = null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self._path_bits != null) {
                self._path_bits.?.deinit();
                self._path_bits = null;
            }

            if (self._compiled_path != null) {
                self.allocator.free(self._compiled_path.?);
                self._compiled_path = null;
            }

            self.item = undefined;
            self.* = undefined;
        }

        pub fn path(self: *Self) ![]u8 {
            if (self._compiled_path != null) {
                return self._compiled_path.?;
            }

            try self.compilePath();

            return self._compiled_path.?;
        }

        fn compilePath(self: *Self) !void {
            if (self._path_bits == null) {
                return Error.UndefinedPathBits;
            }

            var sz: usize = 0;

            for (self._path_bits.?.slice(), 0..) |p, i| {
                sz += p.len;
                if (i > 0) {
                    sz += 1;
                }
            }

            var output = try self.allocator.alloc(u8, sz);

            var cursor: usize = 0;

            for (self._path_bits.?.slice(), 0..) |p, i| {
                if (i > 0) {
                    output[cursor] = '/';
                    cursor += 1;
                }
                std.mem.copyForwards(u8, output[cursor..], p);
                cursor += p.len;
            }

            self._compiled_path = output;
        }
    };
}

/// Extract path parameters from a path.
/// Ex:
/// var params = extractParamsFromPath(std.heap.page_allocator, "/users/:user", req.path)
/// std.debug.print("{}", .{params.get("user")})
pub fn extractParamsFromPath(allocator: Allocator, template_path: []const u8, src_path: []const u8) !std.StringHashMap([]const u8) {
    var m = std.StringHashMap([]const u8).init(allocator);

    var v_template = try splitPath(allocator, template_path);
    defer v_template.deinit();
    var v_src = try splitPath(allocator, src_path);
    defer v_src.deinit();

    const s_template = v_template.slice();
    const s_src = v_src.slice();

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

        const bit = i_template[1..];
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

    var slice = std.mem.splitSequence(u8, fpath, "/");

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
    const p_tpl: []const u8 = "/users/:user/say-hello";
    const p_src: []const u8 = "/users/mike/say-hello/ok";

    var m = try extractParamsFromPath(std.testing.allocator, p_tpl, p_src);
    defer m.deinit();

    const umike = m.get("user") orelse unreachable;

    try testing.expect(std.mem.eql(u8, umike, "mike"));
}

test "router" {
    var router = Router(u8).init(std.testing.allocator);
    defer router.deinit();
    try router.put("/", 1);
    try router.put("/hello", 2);
    try router.put("/paris/:id", 3);

    var r1 = try router.get("/");
    defer r1.?.deinit();
    try testing.expect(r1.?.item == 1);
    var r2 = try router.get("/hello");
    defer r2.?.deinit();
    try testing.expect(r2.?.item == 2);
    var r3 = try router.get("/paris/123");
    try testing.expect(r3 != null);
    defer r3.?.deinit();
    try testing.expect(r3.?.item == 3);

    const p = try r3.?.path();
    try testing.expect(std.mem.eql(u8, p, "paris/:id"));

    var r3params = try extractParamsFromPath(std.testing.allocator, p, "/paris/123");
    defer r3params.deinit();

    try testing.expect(std.mem.eql(u8, r3params.get("id").?, "123"));

    const r4 = try router.get("/unknown");
    try testing.expect(r4 == null);
}
