const std = @import("std");
const s = @import("./structs.zig");

pub const Formatter = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    tty_conf: std.io.tty.Config,
    command: s.Command,
    measurements: s.Measurements,
    stdout: std.fs.File,

    pub fn init(allocator: std.mem.Allocator, tty_conf: std.io.tty.Config, command: s.Command, measurements: s.Measurements, stdout: std.fs.File) !Self {
        return Self{
            .allocator = allocator,
            .tty_conf = tty_conf,
            .command = command,
            .measurements = measurements,
            .stdout = stdout,
        };
    }

    pub fn print(
        self: *Self,
    ) !void {
        try self.printHeaders();
        //std.debug.print("{?}\n", .{measurements});

        inline for (@typeInfo(s.Measurements).Struct.fields) |field| {
            const measurement = @field(self.command.measurements, field.name);
            try self.printMeasurement(measurement, field.name);
        }
    }

    pub fn printHeaders(
        self: *Self,
    ) !void {
        var stdout_bw = std.io.bufferedWriter(self.stdout.writer());
        const writer = stdout_bw.writer();

        try self.tty_conf.setColor(writer, .bold);
        try writer.print("Benchmark", .{});
        try self.tty_conf.setColor(writer, .dim);
        try writer.print(" ({d} runs)", .{self.command.sample_count});
        try self.tty_conf.setColor(writer, .reset);
        try writer.writeAll(":");
        for (self.command.argv) |arg| try writer.print(" {s}", .{arg});
        try writer.writeAll("\n");

        try self.tty_conf.setColor(writer, .bold);
        try writer.writeAll("  measurement");
        try writer.writeByteNTimes(' ', 23 - "  measurement".len);
        try self.tty_conf.setColor(writer, .bright_green);
        try writer.writeAll("mean");
        try self.tty_conf.setColor(writer, .reset);
        try self.tty_conf.setColor(writer, .bold);
        try writer.writeAll(" ± ");
        try self.tty_conf.setColor(writer, .green);
        try writer.writeAll("σ");
        try self.tty_conf.setColor(writer, .reset);

        try self.tty_conf.setColor(writer, .bold);
        try writer.writeByteNTimes(' ', 12);
        try self.tty_conf.setColor(writer, .cyan);
        try writer.writeAll("min");
        try self.tty_conf.setColor(writer, .reset);
        try self.tty_conf.setColor(writer, .bold);
        try writer.writeAll(" … ");
        try self.tty_conf.setColor(writer, .magenta);
        try writer.writeAll("max");
        try self.tty_conf.setColor(writer, .reset);

        try writer.writeAll("\n");
        try stdout_bw.flush();
    }

    pub fn printMeasurement(
        self: *Self,
        m: s.Measurement,
        name: []const u8,
    ) !void {
        var stdout_bw = std.io.bufferedWriter(self.stdout.writer());
        const w = stdout_bw.writer();
        try w.print("  {s}", .{name});

        var buf: [200]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        var count: usize = 0;

        const spaces = 32 - ("  (mean  ):".len + name.len + 2);
        try w.writeByteNTimes(' ', spaces);
        try self.tty_conf.setColor(w, .bright_green);
        try printUnit(fbs.writer(), m.mean, m.unit);
        try w.writeAll(fbs.getWritten());
        count += fbs.pos;
        fbs.pos = 0;
        try self.tty_conf.setColor(w, .reset);
        try w.writeAll(" ± ");
        try self.tty_conf.setColor(w, .green);
        try printUnit(fbs.writer(), m.std_dev, m.unit);
        try w.writeAll(fbs.getWritten());
        count += fbs.pos;
        fbs.pos = 0;
        try self.tty_conf.setColor(w, .reset);

        try w.writeByteNTimes(' ', 38 - ("  measurement      ".len + count + 3));
        count = 0;

        try self.tty_conf.setColor(w, .cyan);
        try printUnit(fbs.writer(), @floatFromInt(m.min), m.unit);
        try w.writeAll(fbs.getWritten());
        count += fbs.pos;
        fbs.pos = 0;
        try self.tty_conf.setColor(w, .reset);
        try w.writeAll(" … ");
        try self.tty_conf.setColor(w, .magenta);
        try printUnit(fbs.writer(), @floatFromInt(m.max), m.unit);
        try w.writeAll(fbs.getWritten());
        count += fbs.pos;
        fbs.pos = 0;
        try self.tty_conf.setColor(w, .reset);

        try w.writeByteNTimes(' ', 46 - (count + 1));
        count = 0;

        try self.tty_conf.setColor(w, .reset);
        try w.writeAll("\n");
        try stdout_bw.flush();
    }

    fn printUnit(w: anytype, x: f64, unit: s.Measurement.Unit) !void {
        const num = x;
        var val: f64 = 0;
        var ustr: []const u8 = "  ";
        if (num >= 1000_000_000_000) {
            val = num / 1000_000_000_000;
            ustr = switch (unit) {
                .count => "T ",
                .nanoseconds => "ks",
                .bytes => "TB",
            };
        } else if (num >= 1000_000_000) {
            val = num / 1000_000_000;
            ustr = switch (unit) {
                .count => "G ",
                .nanoseconds => "s ",
                .bytes => "GB",
            };
        } else if (num >= 1000_000) {
            val = num / 1000_000;
            ustr = switch (unit) {
                .count => "M ",
                .nanoseconds => "ms",
                .bytes => "MB",
            };
        } else if (num >= 1000) {
            val = num / 1000;
            ustr = switch (unit) {
                .count => "K ",
                .nanoseconds => "us",
                .bytes => "KB",
            };
        } else {
            val = num;
            ustr = switch (unit) {
                .count => "  ",
                .nanoseconds => "ns",
                .bytes => "  ",
            };
        }
        try printNum3SigFigs(w, val);
        try w.writeAll(ustr);
    }

    fn printNum3SigFigs(w: anytype, num: f64) !void {
        if (num >= 1000 or @round(num) == num) {
            try w.print("{d: >4.0}", .{num});
            // TODO Do we need special handling here since it overruns 3 sig figs?
        } else if (num >= 100) {
            try w.print("{d: >4.0}", .{num});
        } else if (num >= 10) {
            try w.print("{d: >3.1}", .{num});
        } else {
            try w.print("{d: >3.2}", .{num});
        }
    }
};
