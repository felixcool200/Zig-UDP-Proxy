const std = @import("std");
const proxy = @import("proxy.zig");
const processors = @import("processors.zig");

// ------------------------- Main -------------------------
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const args_mut = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args_mut);

    // Convert to [][]const u8
    var args: [][]const u8 = try allocator.alloc([]const u8, args_mut.len);
    defer allocator.free(args); // Free outer slice automatically

    var i: usize = 0;
    while (i < args_mut.len) : (i += 1) {
        args[i] = args_mut[i]; // cast inner slice to const
    }

    if (args.len < 5) {
        try printUsage(args[0]);
        return;
    }

    const listenIP = args[1];
    const listenPort = try std.fmt.parseInt(u16, args[2], 10);
    const forwardIP = args[3];
    const forwardPort = try std.fmt.parseInt(u16, args[4], 10);

    const processor_type = if (args.len > 5) args[5] else "passthrough";

    try stdout.print(
        "UDP Proxy: {s}:{d} -> {s}:{d}\nProcessor: {s}\n",
        .{ listenIP, listenPort, forwardIP, forwardPort, processor_type },
    );

    var processor = try processors.selectProcessor(allocator, processor_type, args);

    var proxy_instance = proxy.ProxySocketPairRuntime.init(
        &processor,
        listenIP,
        listenPort,
        forwardIP,
        forwardPort,
    ) catch |err| {
        try stderr.print("ERROR: Failed to initialize proxy: {}\n", .{err});
        return;
    };
    defer proxy_instance.deinit();

    proxy_instance.start(5000) catch |err| {
        try stderr.print("ERROR: Proxy failed to start: {}\n", .{err});
        return;
    };

    try stdout.print("{s}", .{processors.selectMessage(processor)});
}

// ------------------------- Usage -------------------------
fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage: {s} <listen_ip> <listen_port> <forward_ip> <forward_port> [processor_type] [args...]
        \\
        \\Processor types:
        \\  passthrough     - Forward all packets unchanged (default)
        \\  logging         - Log packet information
        \\  filtering       - Drop packets containing pattern (6th arg)
        \\  custom          - Add/remove 'FWD:' headers
        \\  srt-nak         - Malform SRT NAK packets (listener->forward)
        \\  srt-nak-bidir   - Malform SRT NAK packets (both directions)
        \\  drop-<pos>      - Drop packets around position
        \\
    , .{program_name});
}
