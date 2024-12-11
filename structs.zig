const std = @import("std");
const PERF = std.os.linux.PERF;

pub const Command = struct {
    raw_cmd: []const u8,
    argv: []const []const u8,
    measurements: Measurements,
    sample_count: usize,
};

pub const Measurements = struct {
    wall_time: Measurement,
    peak_rss: Measurement,
    cpu_cycles: Measurement,
    instructions: Measurement,
    cache_references: Measurement,
    cache_misses: Measurement,
    branch_misses: Measurement,
};

pub const Measurement = struct {
    median: u64,
    min: u64,
    max: u64,
    mean: f64,
    std_dev: f64,
    sample_count: u64,
    unit: Unit,

    const Unit = enum {
        nanoseconds,
        bytes,
        count,
    };

    pub fn compute(samples: []Sample, comptime field: []const u8, unit: Unit) Measurement {
        std.mem.sort(Sample, samples, {}, Sample.lessThanContext(field).lessThan);
        // Compute stats
        var total: u64 = 0;
        var min: u64 = std.math.maxInt(u64);
        var max: u64 = 0;
        for (samples) |s| {
            const v = @field(s, field);
            total += v;
            if (v < min) min = v;
            if (v > max) max = v;
        }
        const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(samples.len));
        var std_dev: f64 = 0;
        for (samples) |s| {
            const v = @field(s, field);
            const delta: f64 = @as(f64, @floatFromInt(v)) - mean;
            std_dev += delta * delta;
        }
        if (samples.len > 1) {
            std_dev /= @floatFromInt(samples.len - 1);
            std_dev = @sqrt(std_dev);
        }

        return .{
            .median = @field(samples[samples.len / 2], field),
            .mean = mean,
            .min = min,
            .max = max,
            .std_dev = std_dev,
            .sample_count = samples.len,
            .unit = unit,
        };
    }
};

pub const Sample = struct {
    wall_time: u64,
    cpu_cycles: u64,
    instructions: u64,
    cache_references: u64,
    cache_misses: u64,
    branch_misses: u64,
    peak_rss: u64,

    pub fn lessThanContext(comptime field: []const u8) type {
        return struct {
            fn lessThan(
                _: void,
                lhs: Sample,
                rhs: Sample,
            ) bool {
                return @field(lhs, field) < @field(rhs, field);
            }
        };
    }
};

pub const PerfMeasurement = struct {
    name: []const u8,
    config: PERF.COUNT.HW,
};

pub const perf_measurements = [_]PerfMeasurement{
    .{ .name = "cpu_cycles", .config = PERF.COUNT.HW.CPU_CYCLES },
    .{ .name = "instructions", .config = PERF.COUNT.HW.INSTRUCTIONS },
    .{ .name = "cache_references", .config = PERF.COUNT.HW.CACHE_REFERENCES },
    .{ .name = "cache_misses", .config = PERF.COUNT.HW.CACHE_MISSES },
    .{ .name = "branch_misses", .config = PERF.COUNT.HW.BRANCH_MISSES },
};
