const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Callbacks = extern struct {
    context: ?*anyopaque = null,
    on_sign_in: ?*const fn (?*anyopaque, [*:0]const u8, [*:0]const u8) callconv(.c) void = null,
    clock: ?*const fn (?*anyopaque) callconv(.c) f64 = null,
    machine_binding: ?*const fn (?*anyopaque, [*]u8, usize) callconv(.c) c_int = null,
    cancelled: ?*const fn (?*anyopaque) callconv(.c) c_int = null,
};
extern "licensebox" fn lb_client_create_json([*:0]const u8, ?*const Callbacks, *?*anyopaque) c_int;
extern "licensebox" fn lb_client_call_json(*anyopaque, [*:0]const u8, [*:0]const u8, *?[*:0]u8) c_int;
extern "licensebox" fn lb_client_destroy(?*anyopaque) void;
extern "licensebox" fn lb_free(?*anyopaque) void;
extern "licensebox" fn lb_result_code(c_int) [*:0]const u8;
extern "licensebox" fn lb_error_code(*anyopaque) [*:0]const u8;
extern "licensebox" fn lb_error_message(*anyopaque) [*:0]const u8;
extern "licensebox" fn lb_derive_binding([*:0]const u8, [*:0]const u8, [*:0]const u8, [*]u8, usize) c_int;
extern "licensebox" fn lb_native_binding([*:0]const u8, [*]u8, usize) c_int;
extern "licensebox" fn lb_verify_lease_json([*:0]const u8, [*:0]const u8, [*:0]const u8, f64, *?[*:0]u8) c_int;

pub const Failure = struct {
    code: []u8,
    message: []u8,
    pub fn deinit(self: Failure, allocator: Allocator) void {
        allocator.free(self.code);
        allocator.free(self.message);
    }
};
/// Both branches own their allocations. Release exactly once with deinit.
pub const Outcome = union(enum) {
    value: []u8,
    failure: Failure,
    pub fn deinit(self: Outcome, allocator: Allocator) void {
        switch (self) {
            .value => |v| allocator.free(v),
            .failure => |f| f.deinit(allocator),
        }
    }
};
fn failure(a: Allocator, code: []const u8, message: []const u8) !Failure {
    const c = try a.dupe(u8, code);
    errdefer a.free(c);
    return .{ .code = c, .message = try a.dupe(u8, message) };
}
fn nativeFailure(a: Allocator, r: c_int, h: ?*anyopaque) !Failure {
    var code = std.mem.span(lb_result_code(r));
    var message = code;
    if (h) |handle| {
        if (!std.mem.eql(u8, code, "invalid_argument")) {
            const saved = std.mem.span(lb_error_code(handle));
            if (!std.mem.eql(u8, saved, "ok")) code = saved;
            message = std.mem.span(lb_error_message(handle));
        }
    }
    return failure(a, code, message);
}
fn z(a: Allocator, value: []const u8) ![:0]u8 {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidArgument;
    return a.dupeZ(u8, value);
}
fn output(a: Allocator, r: c_int, h: ?*anyopaque, p: ?[*:0]u8) !Outcome {
    defer if (p) |v| lb_free(v);
    if (r != 0) return .{ .failure = try nativeFailure(a, r, h) };
    const value = p orelse return .{ .failure = try failure(a, "protocol_error", "missing native result") };
    return .{ .value = try a.dupe(u8, std.mem.span(value)) };
}
pub const ClientResult = union(enum) { client: *Client, failure: Failure };
/// Own the returned Client pointer once; aliases share state. close is idempotent;
/// destroy frees the object and invalidates all aliases. Do not copy Client by
/// value. Callback context is borrowed and must outlive destroy; callbacks must
/// not reenter. Clock/binding are trusted platform/testing seams only.
pub const Client = struct {
    allocator: Allocator,
    handle: ?*anyopaque = null,
    callbacks: Callbacks,
    mutex: std.Thread.Mutex = .{},
    pub fn init(a: Allocator, options_json: []const u8, callbacks: Callbacks) !ClientResult {
        const options = try z(a, options_json);
        defer a.free(options);
        const self = try a.create(Client);
        errdefer a.destroy(self);
        self.* = .{ .allocator = a, .callbacks = callbacks };
        const r = lb_client_create_json(options, &self.callbacks, &self.handle);
        if (r != 0) {
            const f = try nativeFailure(a, r, null);
            a.destroy(self);
            return .{ .failure = f };
        }
        return .{ .client = self };
    }
    pub fn close(self: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        lb_client_destroy(self.handle);
        self.handle = null;
    }
    pub fn destroy(self: *Client) void {
        self.close();
        self.allocator.destroy(self);
    }
    pub fn call(self: *Client, operation: []const u8, args_json: []const u8) !Outcome {
        const a = self.allocator;
        const op = try z(a, operation);
        defer a.free(op);
        const args = try z(a, args_json);
        defer a.free(args);
        self.mutex.lock();
        defer self.mutex.unlock();
        const h = self.handle orelse return .{ .failure = try failure(a, "invalid_argument", "closed client") };
        var p: ?[*:0]u8 = null;
        const r = lb_client_call_json(h, op, args, &p);
        return output(a, r, h, p);
    }
    pub fn lease(self: *Client) !Outcome {
        return self.call("lease", "{}");
    }
    pub fn requireModule(self: *Client, name: []const u8) !Outcome {
        const args = try std.json.stringifyAlloc(self.allocator, .{ .module = name }, .{});
        defer self.allocator.free(args);
        return self.call("require", args);
    }
    pub fn status(self: *Client) !Outcome {
        return self.call("status", "{}");
    }
    pub fn signIn(self: *Client, timeout: f64) !Outcome {
        const args = try std.json.stringifyAlloc(self.allocator, .{ .timeout = timeout }, .{});
        defer self.allocator.free(args);
        return self.call("sign_in", args);
    }
    pub fn logout(self: *Client) !Outcome {
        return self.call("logout", "{}");
    }
    pub fn modules(self: *Client) !Outcome {
        return self.call("modules", "{}");
    }
    pub fn requests(self: *Client) !Outcome {
        return self.call("requests", "{}");
    }
    pub fn requestAccess(self: *Client, names: []const []const u8, note: []const u8) !Outcome {
        const args = try std.json.stringifyAlloc(self.allocator, .{ .modules = names, .note = note }, .{});
        defer self.allocator.free(args);
        return self.call("request", args);
    }
    pub fn accessLink(self: *Client) !Outcome {
        return self.call("access-link", "{}");
    }
    pub fn recordUsage(self: *Client, command: []const u8, success: bool, elapsed: f64) !Outcome {
        const args = try std.json.stringifyAlloc(self.allocator, .{ .command = command, .success = success, .elapsed = elapsed }, .{});
        defer self.allocator.free(args);
        return self.call("record", args);
    }
};
pub fn deriveBinding(a: Allocator, product: []const u8, source: []const u8, raw_id: []const u8) !Outcome {
    const p = try z(a, product);
    defer a.free(p);
    const s = try z(a, source);
    defer a.free(s);
    const raw = std.mem.trimRight(u8, raw_id, "\x00");
    if (std.mem.indexOfScalar(u8, raw, 0) != null) return .{ .failure = try failure(a, "identity_unavailable", "invalid identifier") };
    const r = try z(a, raw);
    defer a.free(r);
    var b: [128]u8 = undefined;
    const code = lb_derive_binding(p, s, r, &b, b.len);
    if (code != 0) return .{ .failure = try nativeFailure(a, code, null) };
    return .{ .value = try std.json.stringifyAlloc(a, std.mem.sliceTo(&b, 0), .{}) };
}
pub fn nativeBinding(a: Allocator, product: []const u8) !Outcome {
    const p = try z(a, product);
    defer a.free(p);
    var b: [128]u8 = undefined;
    const code = lb_native_binding(p, &b, b.len);
    if (code != 0) return .{ .failure = try nativeFailure(a, code, null) };
    return .{ .value = try std.json.stringifyAlloc(a, std.mem.sliceTo(&b, 0), .{}) };
}
pub fn verifyLease(a: Allocator, token: []const u8, product: []const u8, keys_json: []const u8, now: f64) !Outcome {
    const t = try z(a, token);
    defer a.free(t);
    const p = try z(a, product);
    defer a.free(p);
    const k = try z(a, keys_json);
    defer a.free(k);
    var out: ?[*:0]u8 = null;
    const code = lb_verify_lease_json(t, p, k, now, &out);
    return output(a, code, null, out);
}
