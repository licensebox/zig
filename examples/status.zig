const std = @import("std");
const lb = @import("licensebox");
pub fn main() !void {
    const a = std.heap.page_allocator;
    const created = try lb.Client.init(a,
        \\{"product":"your-product","keys":{"current":"YOUR_PUBLIC_KEY"}}
    , .{});
    switch (created) {
        .failure => |f| {
            defer f.deinit(a);
            std.debug.print("{s}: {s}\n", .{ f.code, f.message });
        },
        .client => |client| {
            defer client.destroy();
            const result = try client.requireModule("core");
            defer result.deinit(a);
            switch (result) {
                .value => |v| std.debug.print("{s}\n", .{v}),
                .failure => |f| std.debug.print("{s}: {s}\n", .{ f.code, f.message }),
            }
        },
    }
}
