const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Vector(comptime T: type) type {
    return struct {
        /// Private field. Please use slice() instead. Using this field directly
        /// is not recommended because this property may be bigger than the actual
        /// slice (it is as big as the vector's capacity).
        _items: []T,
        allocator: Allocator,
        size: usize,

        const Self = @This();

        pub fn init(allocator: Allocator, cap: usize) !Self {
            return .{
                .allocator = allocator,
                .size = 0,
                ._items = try allocator.alloc(T, @max(cap, 4)),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self._items);
            self.size = 0;
        }

        pub fn append(self: *Self, item: T) !void {
            if (self._items.len > self.size + 1) {
                self._items[self.size] = item;
                self.size += 1;
                return;
            }

            const new_array = try self.allocator.alloc(T, self._items.len * 2);

            std.mem.copyForwards(T, new_array, self._items);
            self.allocator.free(self._items);

            self._items = new_array;
            self._items[self.size] = item;
            self.size += 1;
        }

        pub fn slice(self: *Self) []T {
            return self._items[0..self.size];
        }
    };
}

test "append" {
    var vec = try Vector(u8).init(std.testing.allocator, 2);
    defer vec.deinit();
    try vec.append(10);
    try vec.append(15);
    try vec.append(22);
    try vec.append(123);

    const s = vec.slice();

    try std.testing.expectEqual(s[0], 10);
    try std.testing.expectEqual(s[1], 15);
    try std.testing.expectEqual(s[2], 22);
    try std.testing.expectEqual(s[3], 123);
}
