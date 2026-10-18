const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const library_dir = b.option([]const u8, "native-lib-dir", "Directory containing liblicensebox.so") orelse "/usr/local/lib";
    const module = b.addModule("licensebox", .{ .root_source_file = b.path("src/licensebox.zig"), .target = target, .optimize = optimize });
    module.addLibraryPath(.{ .cwd_relative = library_dir });
    module.linkSystemLibrary("licensebox", .{});
    module.link_libc = true;
    const test_step = b.step("test", "Run binding tests");
    const unit = b.addTest(.{ .root_source_file = b.path("tests/binding.zig"), .target = target, .optimize = optimize });
    unit.root_module.addImport("licensebox", module);
    test_step.dependOn(&b.addRunArtifact(unit).step);
    const adapter = b.addExecutable(.{ .name = "adapter", .root_source_file = b.path("tests/adapter.zig"), .target = target, .optimize = optimize });
    adapter.root_module.addImport("licensebox", module);
    b.installArtifact(adapter);
    const consumer = b.addExecutable(.{ .name = "status", .root_source_file = b.path("examples/status.zig"), .target = target, .optimize = optimize });
    consumer.root_module.addImport("licensebox", module);
    b.installArtifact(consumer);
    b.installFile("src/licensebox.zig", "share/licensebox/licensebox.zig");
}
