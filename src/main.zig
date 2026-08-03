const std = @import("std");
const tunnel = @import("tunnel.zig");

const Config = struct {
    listen: []const u8 = ":8001",
    backend: []const u8 = "127.0.0.1:1234",
    secret: []const u8 = "the answer to life, the universe and everything",
    tunnels: u32 = 0,
    heartbeat: u32 = 10,
    timeout: u32 = 30,
    log_level: u32 = 1,
};

pub fn main(init: std.process.Init) !void {
    const config = parseArgs(init.minimal.args) catch |err| {
        printUsage();
        return err;
    };

    if (config.tunnels == 0) {
        var server = try tunnel.Server.init(init.gpa, init.io, .{
            .listen = config.listen,
            .backend = config.backend,
            .secret = config.secret,
            .heartbeat = config.heartbeat,
            .timeout = config.timeout,
            .log_level = config.log_level,
        });
        try server.start();
    } else {
        var client = try tunnel.Client.init(init.gpa, init.io, .{
            .listen = config.listen,
            .backend = config.backend,
            .secret = config.secret,
            .tunnels = config.tunnels,
            .heartbeat = config.heartbeat,
            .timeout = config.timeout,
            .log_level = config.log_level,
        });
        try client.start();
    }
}

fn parseArgs(args: std.process.Args) !Config {
    var it = std.process.Args.Iterator.init(args);
    return parseArgsIterator(&it);
}

fn parseArgsIterator(it: anytype) !Config {
    var config = Config{};
    _ = it.next();

    while (it.next()) |raw| {
        const arg = raw[0..raw.len];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        }
        if (arg.len < 2 or arg[0] != '-') return error.InvalidArgument;

        const name_start: usize = if (arg.len > 1 and arg[1] == '-') 2 else 1;
        const separator = std.mem.indexOfScalar(u8, arg[name_start..], '=');
        const name_end = if (separator) |offset| name_start + offset else arg.len;
        const name = arg[name_start..name_end];
        const value = if (separator) |_| arg[name_end + 1 ..] else it.next() orelse return error.MissingArgument;

        if (std.mem.eql(u8, name, "listen")) {
            config.listen = value;
        } else if (std.mem.eql(u8, name, "backend")) {
            config.backend = value;
        } else if (std.mem.eql(u8, name, "secret")) {
            config.secret = value;
        } else if (std.mem.eql(u8, name, "tunnels")) {
            config.tunnels = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, name, "heartbeat")) {
            config.heartbeat = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, name, "timeout")) {
            config.timeout = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, name, "log")) {
            config.log_level = try std.fmt.parseInt(u32, value, 10);
        } else {
            return error.UnknownArgument;
        }
    }

    return config;
}

const TestArgs = struct {
    items: []const []const u8,
    index: usize = 0,

    fn next(self: *@This()) ?[]const u8 {
        if (self.index >= self.items.len) return null;
        const value = self.items[self.index];
        self.index += 1;
        return value;
    }
};

test "argument parser accepts defaults, equals, and separate values" {
    var args = TestArgs{ .items = &[_][]const u8{
        "gotunnel",
        "--listen=127.0.0.1:9000",
        "-backend",
        "10.0.0.2:8080",
        "--secret",
        "shared secret",
        "-tunnels",
        "3",
        "--heartbeat=5",
        "-timeout",
        "12",
        "--log",
        "2",
    } };
    const config = try parseArgsIterator(&args);
    try std.testing.expectEqualStrings("127.0.0.1:9000", config.listen);
    try std.testing.expectEqualStrings("10.0.0.2:8080", config.backend);
    try std.testing.expectEqualStrings("shared secret", config.secret);
    try std.testing.expectEqual(@as(u32, 3), config.tunnels);
    try std.testing.expectEqual(@as(u32, 5), config.heartbeat);
    try std.testing.expectEqual(@as(u32, 12), config.timeout);
    try std.testing.expectEqual(@as(u32, 2), config.log_level);
}

test "argument parser rejects unknown, missing, and invalid values" {
    var unknown = TestArgs{ .items = &[_][]const u8{ "gotunnel", "--unknown=1" } };
    try std.testing.expectError(error.UnknownArgument, parseArgsIterator(&unknown));

    var missing = TestArgs{ .items = &[_][]const u8{ "gotunnel", "--secret" } };
    try std.testing.expectError(error.MissingArgument, parseArgsIterator(&missing));

    var invalid = TestArgs{ .items = &[_][]const u8{ "gotunnel", "--tunnels=not-a-number" } };
    try std.testing.expectError(error.InvalidCharacter, parseArgsIterator(&invalid));
}

fn printUsage() void {
    std.debug.print(
        "usage: gotunnel\n" ++
            "  -backend string     backend address (default \"127.0.0.1:1234\")\n" ++
            "  -heartbeat int      tunnel heartbeat interval in seconds (default 10)\n" ++
            "  -listen string      listen address (default \":8001\")\n" ++
            "  -log uint           log level (default 1)\n" ++
            "  -secret string      tunnel secret\n" ++
            "  -timeout int        tunnel read/write timeout in seconds (default 30)\n" ++
            "  -tunnels uint       low-level tunnel count (0 = server mode)\n",
        .{},
    );
}
