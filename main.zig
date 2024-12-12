const bar = @import("./bar.zig");
const s = @import("./structs.zig");
const std = @import("std");
const collector = @import("./collector.zig");
const formatter = @import("./formatter.zig");

const usage_text =
    \\Usage: poop [options] <command1> ... <commandN>
    \\
    \\Compares the performance of the provided commands.
    \\
    \\Options:
    \\ -d, --duration <ms>    (default: 5000) how long to repeatedly sample each command
    \\
;

fn parseCmd(list: *std.ArrayList([]const u8), cmd: []const u8) !void {
    var it = std.mem.tokenizeScalar(u8, cmd, ' ');
    while (it.next()) |st| try list.append(st);
}

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try std.process.argsAlloc(arena);
    const stdout = std.io.getStdOut();

    var _bar = try bar.ProgressBar.init(arena, stdout);

    const tty_conf: std.io.tty.Config = std.io.tty.detectConfig(stdout);
    var commands = std.ArrayList(s.Command).init(arena);
    var max_nano_seconds: u64 = std.time.ns_per_s * 5;

    defer _bar.deinit();

    var arg_i: usize = 1;
    while (arg_i < args.len) : (arg_i += 1) {
        const arg = args[arg_i];
        if (!std.mem.startsWith(u8, arg, "-")) {
            var cmd_argv = std.ArrayList([]const u8).init(arena);
            try parseCmd(&cmd_argv, arg);
            try commands.append(.{
                .raw_cmd = arg,
                .argv = try cmd_argv.toOwnedSlice(),
                .measurements = undefined,
                .sample_count = undefined,
            });
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage_text);
            return std.process.cleanExit();
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--duration")) {
            arg_i += 1;
            if (arg_i >= args.len) {
                std.debug.print("'{s}' requires a duration in milliseconds.\n{s}", .{ arg, usage_text });
                std.process.exit(1);
            }
            const next = args[arg_i];
            const max_ms = std.fmt.parseInt(u64, next, 10) catch |err| {
                std.debug.print("unable to parse --duration argument '{s}': {s}\n", .{
                    next, @errorName(err),
                });
                std.process.exit(1);
            };
            max_nano_seconds = std.time.ns_per_ms * max_ms;
        }
    }

    if (commands.items.len == 0) {
        try stdout.writeAll(usage_text);
        std.process.exit(1);
    }

    for (commands.items) |*command| {
        var c = try collector.Collector.init(arena, command, max_nano_seconds, _bar);
        const measurements = try c.collect();
        //std.debug.print("{?}\n", .{measurements});
        var f = try formatter.Formatter.init(arena, tty_conf, command.*, measurements, stdout);
        try f.print();
    }

    //std.debug.print("{s}\n", .{"hello"});
}
