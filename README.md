# Simple Router

Grug wants simple router that works well with [Zap](https://github.com/zigzap/zap).
Grug will probably deprecate this once Zap gets an official router implementation.

```zig
const std = @import("std");
const zap = @import("zap");
const router = @import("router");

fn dispatch_routes(r: zap.SimpleRequest) void {
    // dispatch
    if (r.path) |the_path| {
        var p = routes.get(the_path) catch unreachable;
        if (p) |*match| {
            defer match.deinit();
            if (match.item != null) {
                std.debug.print("route {s}\n", .{match.path() catch unreachable});
                match.item.?(r);
                return;
            }
            std.debug.print("route '{s}' has nil handler", .{match.path() catch unreachable});
        }
    }
    // or default: present menu
    r.sendBody(
        \\ <html>
        \\   <body>
        \\     <p><a href="/static">static</a></p>
        \\     <p><a href="/dynamic">dynamic</a></p>
        \\     <p><a href="/dynamic/1">very dynamic</a></p>
        \\     <p><a href="/dynamic/2">very dynamic</a></p>
        \\   </body>
        \\ </html>
    ) catch return;
}

fn static_site(r: zap.SimpleRequest) void {
    r.sendBody("<html><body><h1>Hello from STATIC ZAP!</h1></body></html>") catch return;
}

var dynamic_counter: i32 = 0;
fn dynamic_site(r: zap.SimpleRequest) void {
    dynamic_counter += 1;
    var buf: [128]u8 = undefined;
    const filled_buf = std.fmt.bufPrintZ(
        &buf,
        "<html><body><h1>Hello # {d} from DYNAMIC ZAP!!!</h1></body></html>",
        .{dynamic_counter},
    ) catch "ERROR";
    r.sendBody(filled_buf) catch return;
}

fn setup_routes(a: std.mem.Allocator) !void {
    routes = router.Router(zap.SimpleHttpRequestFn).init(a);
    try routes.put("/static", static_site);
    try routes.put("/dynamic", dynamic_site);
    try routes.put("/dynamic/:very_dynamic", dynamic_site);
}

var routes: router.Router(zap.SimpleHttpRequestFn) = undefined;

pub fn main() !void {
    try setup_routes(std.heap.page_allocator);
    var listener = zap.SimpleHttpListener.init(.{
        .port = 3000,
        .on_request = dispatch_routes,
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
```
