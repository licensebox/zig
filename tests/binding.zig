const std = @import("std");
const lb = @import("licensebox");
test "binding vector, errors, aliases, close, native output ownership" {
    const a = std.testing.allocator;
    const out = try lb.deriveBinding(a, "demo", "linux-machine-id", "12345678123456789abc1234567890ab");
    defer out.deinit(a);
    try std.testing.expectEqualStrings("\"m1:linux-machine-id:783b8906a4af61095e68f3f0b4468a953be69ddd7afcf35850b501a7361f309e\"", out.value);
    const created = try lb.Client.init(a,
        \\{"product":"demo","keys":{"k":"A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"},"directory":"build/test-state"}
    , .{});
    const client = created.client;
    defer client.destroy();
    const alias = client;
    const status = try client.status();
    defer status.deinit(a);
    try std.testing.expectEqualStrings("not_signed_in", status.failure.code);
    const logout = try client.logout();
    defer logout.deinit(a);
    try std.testing.expectEqualStrings("null", logout.value);
    client.close();
    alias.close();
    const closed = try alias.status();
    defer closed.deinit(a);
    try std.testing.expectEqualStrings("invalid_argument", closed.failure.code);
}
