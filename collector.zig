const std = @import("std");
const s = @import("./structs.zig");
const fd_t = std.posix.fd_t;
const PERF = std.os.linux.PERF;
const progress_bar = @import("./bar.zig");
const assert = std.debug.assert;

const MAX_SAMPLES = 10000;

pub const Collector = struct {
    const Self = @This();
    command: *s.Command,
    samples_buf: [MAX_SAMPLES]s.Sample,
    max_nano_seconds: u64,
    allocator: std.mem.Allocator,
    bar: progress_bar.ProgressBar,

    pub fn init(allocator: std.mem.Allocator, command: *s.Command, max_nano_seconds: u64, bar: progress_bar.ProgressBar) !Self {
        return Self{ .command = command, .max_nano_seconds = max_nano_seconds, .samples_buf = undefined, .allocator = allocator, .bar = bar };
    }

    fn readPerfFd(fd: fd_t) usize {
        var result: usize = 0;
        const n = std.posix.read(fd, std.mem.asBytes(&result)) catch |err| {
            std.debug.panic("unable to read perf fd: {s}\n", .{@errorName(err)});
        };
        assert(n == @sizeOf(usize));
        return result;
    }

    pub fn collect(
        self: *Self,
    ) !s.Measurements {
        var timer = std.time.Timer.start() catch @panic("need timer to work");
        const first_start = timer.read();
        var sample_index: usize = 0;

        var perf_fds = [1]fd_t{-1} ** s.perf_measurements.len;

        while ((sample_index < 3 or
            (timer.read() - first_start) < self.max_nano_seconds) and
            sample_index < self.samples_buf.len) : (sample_index += 1)
        {
            try self.bar.render();
            for (s.perf_measurements, &perf_fds) |measurement, *perf_fd| {
                var attr: std.os.linux.perf_event_attr = .{
                    .type = PERF.TYPE.HARDWARE,
                    .config = @intFromEnum(measurement.config),
                    .flags = .{
                        .disabled = true,
                        .exclude_kernel = true,
                        .exclude_hv = true,
                        .inherit = true,
                        .enable_on_exec = true,
                    },
                };

                perf_fd.* = std.posix.perf_event_open(&attr, 0, -1, -1, PERF.FLAG.FD_CLOEXEC) catch |err| {
                    std.debug.panic("unable to open perf event: {s}\n", .{@errorName(err)});
                };
            }

            _ = std.os.linux.ioctl(perf_fds[0], PERF.EVENT_IOC.DISABLE, PERF.IOC_FLAG_GROUP);
            _ = std.os.linux.ioctl(perf_fds[0], PERF.EVENT_IOC.RESET, PERF.IOC_FLAG_GROUP);

            var child = std.process.Child.init(self.command.argv, self.allocator);
            child.stdin_behavior = .Ignore;
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Pipe;
            child.request_resource_usage_statistics = true;

            const start = timer.read();
            try child.spawn();

            _ = child.wait() catch |err| {
                std.debug.print("\nerror: Couldn't execute {s}: {s}\n", .{ self.command.argv[0], @errorName(err) });
                std.process.exit(1);
            };
            const end = timer.read();
            _ = std.os.linux.ioctl(perf_fds[0], PERF.EVENT_IOC.DISABLE, PERF.IOC_FLAG_GROUP);
            const peak_rss = child.resource_usage_statistics.getMaxRss() orelse 0;

            self.samples_buf[sample_index] = .{
                .wall_time = end - start,
                .peak_rss = peak_rss,
                .cpu_cycles = readPerfFd(perf_fds[0]),
                .instructions = readPerfFd(perf_fds[1]),
                .cache_references = readPerfFd(perf_fds[2]),
                .cache_misses = readPerfFd(perf_fds[3]),
                .branch_misses = readPerfFd(perf_fds[4]),
            };
            for (&perf_fds) |*perf_fd| {
                std.posix.close(perf_fd.*);
                perf_fd.* = -1;
            }
        }

        const all_samples = self.samples_buf[0..sample_index];

        self.command.measurements = .{
            .wall_time = s.Measurement.compute(all_samples, "wall_time", .nanoseconds),
            .peak_rss = s.Measurement.compute(all_samples, "peak_rss", .bytes),
            .cpu_cycles = s.Measurement.compute(all_samples, "cpu_cycles", .count),
            .instructions = s.Measurement.compute(all_samples, "instructions", .count),
            .cache_references = s.Measurement.compute(all_samples, "cache_references", .count),
            .cache_misses = s.Measurement.compute(all_samples, "cache_misses", .count),
            .branch_misses = s.Measurement.compute(all_samples, "branch_misses", .count),
        };
        self.command.sample_count = all_samples.len;

        return self.command.measurements;
    }
};
