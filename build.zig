const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "poop",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = b.option(bool, "strip", "strip the binary"),
    });

    b.installArtifact(exe);
}
