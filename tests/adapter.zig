const std = @import("std");
const lb = @import("licensebox");
var now: f64 = 0;
var binding: []const u8 = "";
fn clockCb(_: ?*anyopaque) callconv(.c) f64 {
    return now;
}
fn bindingCb(_: ?*anyopaque, out: [*]u8, capacity: usize) callconv(.c) c_int {
    if (binding.len >= capacity) return 1;
    @memcpy(out[0..binding.len], binding);
    out[binding.len] = 0;
    return 0;
}
fn signinCb(_: ?*anyopaque, _: [*:0]const u8, _: [*:0]const u8) callconv(.c) void {}
fn field(r: std.json.Value, key: []const u8) []const u8 {
    return if (r.object.get(key)) |v| v.string else "";
}
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn run(a: std.mem.Allocator, r: std.json.Value) !lb.Outcome {
    const op = field(r, "op");
    const product = field(r, "product");
    const n = r.object.get("now");
    now = if (n) |v| switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => 0,
    } else 0;
    const keys = try std.json.stringifyAlloc(a, r.object.get("keys") orelse .null, .{});
    defer a.free(keys);
    if (eq(op, "derive")) return lb.deriveBinding(a, product, field(r, "source"), field(r, "raw_id"));
    if (eq(op, "native")) return lb.nativeBinding(a, product);
    if (eq(op, "verify")) return lb.verifyLease(a, field(r, "token"), product, keys, now);
    var options = std.json.ObjectMap.init(a);
    defer options.deinit();
    for ([_][]const u8{ "product", "keys", "server", "directory", "ca_bundle" }) |key| {
        if (r.object.get(key)) |v| try options.put(key, v);
    }
    try options.put("version", .{ .string = "conformance" });
    const options_json = try std.json.stringifyAlloc(a, std.json.Value{ .object = options }, .{});
    defer a.free(options_json);
    binding = field(r, "binding");
    const created = try lb.Client.init(a, options_json, .{ .clock = clockCb, .on_sign_in = signinCb, .machine_binding = if (r.object.contains("binding")) bindingCb else null });
    const client = switch (created) {
        .client => |c| c,
        .failure => |f| return .{ .failure = f },
    };
    defer client.destroy();
    if (eq(op, "require")) return client.requireModule(if (r.object.get("module")) |v| v.string else "core");
    if (eq(op, "heartbeat") or eq(op, "heartbeat-repeat") or eq(op, "heartbeat-after-require")) {
        const name = if (r.object.get("module")) |v| v.string else "core";
        if (eq(op, "heartbeat-after-require")) {
            const required = try client.requireModule("core");
            switch (required) {
                .failure => return required,
                .value => required.deinit(a),
            }
        }
        if (eq(op, "heartbeat-repeat")) {
            const first = try client.heartbeat(name);
            switch (first) {
                .failure => return first,
                .value => first.deinit(a),
            }
        }
        return client.heartbeat(name);
    }
    if (eq(op, "repeat")) {
        const first = try client.requireModule("core");
        switch (first) {
            .failure => return first,
            .value => first.deinit(a),
        }
        return client.requireModule("core");
    }
    if (eq(op, "sign_in")) return client.signIn(3);
    if (eq(op, "request")) return client.requestAccess(&.{"export"}, "café – test");
    if (eq(op, "record")) {
        const first = try client.recordUsage("export", true, 0.125);
        switch (first) {
            .failure => return first,
            .value => first.deinit(a),
        }
        return client.recordUsage("export", false, 0.025);
    }
    return client.call(op, "{}");
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const input = try std.io.getStdIn().readToEndAlloc(a, 1 << 20);
    const r = try std.json.parseFromSlice(std.json.Value, a, input, .{});
    defer r.deinit();
    const out = try run(a, r.value);
    defer out.deinit(a);
    const writer = std.io.getStdOut().writer();
    switch (out) {
        .value => |v| try writer.print("{{\"ok\":true,\"value\":{s}}}\n", .{v}),
        .failure => |f| {
            const code = try std.json.stringifyAlloc(a, f.code, .{});
            try writer.print("{{\"ok\":false,\"error\":{s}}}\n", .{code});
        },
    }
}
