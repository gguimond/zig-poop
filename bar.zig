const std = @import("std");

const Spinner = struct {
    const Self = @This();
    pub const frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
    pub const frame1 = "⠋";
    pub const frame_count = frames.len / frame1.len;

    frame_idx: usize,

    pub fn init() Self {
        return Self{ .frame_idx = 0 };
    }

    pub fn get(self: *const Self) []const u8 {
        return frames[self.frame_idx * frame1.len ..][0..frame1.len];
    }

    pub fn next(self: *Self) void {
        self.frame_idx = (self.frame_idx + 1) % frame_count;
    }
};

const bar = "━";
const half_bar_left = "╸";
const half_bar_right = "╺";
const TIOCGWINSZ: u32 = 0x5413; // https://docs.rs/libc/latest/libc/constant.TIOCGWINSZ.html
const WIDTH_PADDING: usize = 100;

const Winsize = extern struct {
    ws_row: c_ushort,
    ws_col: c_ushort,
    ws_xpixel: c_ushort,
    ws_ypixel: c_ushort,
};

pub fn getScreenWidth(stdout: std.posix.fd_t) usize {
    var winsize: Winsize = undefined;
    _ = std.os.linux.ioctl(stdout, TIOCGWINSZ, @intFromPtr(&winsize));
    return @intCast(winsize.ws_col);
}

pub const EscapeCodes = struct {
    pub const dim = "\x1b[2m";
    pub const pink = "\x1b[38;5;205m";
    pub const white = "\x1b[37m";
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const green = "\x1b[32m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const reset = "\x1b[0m";
    pub const erase_line = "\x1b[2K\r";
};

pub const ProgressBar = struct {
    const Self = @This();

    spinner: Spinner,
    stdout: std.fs.File,
    buf: std.ArrayList(u8),
    last_rendered: i64,

    pub fn init(allocator: std.mem.Allocator, stdout: std.fs.File) !Self {
        const buf = try std.ArrayList(u8).initCapacity(allocator, WIDTH_PADDING);
        return Self{
            .spinner = Spinner.init(),
            .last_rendered = std.time.timestamp(),
            .stdout = stdout,
            .buf = buf,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buf.deinit();
    }

    pub fn render(self: *Self) !void {
        const now = std.time.timestamp();
        //std.debug.print("{d}\n", .{now});
        if (now - self.last_rendered < 50) {
            //return;
        }
        try self.clear();
        self.last_rendered = now;

        var writer = self.buf.writer();

        try writer.print("{s}{s}{s}", .{ EscapeCodes.cyan, self.spinner.get(), EscapeCodes.reset });
        self.spinner.next();
        try self.stdout.writeAll(self.buf.items[0..self.buf.items.len]);
    }

    pub fn clear(self: *Self) !void {
        try self.stdout.writeAll(EscapeCodes.erase_line); // clear and reset line
        self.buf.clearRetainingCapacity();
    }
};
