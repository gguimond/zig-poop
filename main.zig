const bar = @import("./bar.zig");
const std = @import("std");

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const stdout = std.io.getStdOut();

    var _bar = try bar.ProgressBar.init(arena, stdout);
    defer _bar.deinit();

    try _bar.render();

    std.time.sleep(2 * std.time.ns_per_s);

    try _bar.render();

    std.time.sleep(2 * std.time.ns_per_s);

    try _bar.clear();
}
