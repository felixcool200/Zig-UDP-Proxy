const std = @import("std");
const proxy = @import("proxy.zig");
const processors = @import("processors.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 5) {
        try printUsage(args[0]);
        return;
    }

    const listenIP = args[1];
    const listenPort = try std.fmt.parseInt(u16, args[2], 10);
    const forwardIP = args[3];
    const forwardPort = try std.fmt.parseInt(u16, args[4], 10);

    const processor_type = if (args.len > 5) args[5] else "passthrough";

    try stdout.print("UDP Proxy: {s}:{d} -> {s}:{d}\n", .{ listenIP, listenPort, forwardIP, forwardPort });
    try stdout.print("Processor: {s}\n", .{processor_type});

    if (std.mem.eql(u8, processor_type, "passthrough")) {
        const processor = processors.PassThroughProcessor{};
        var proxy_instance = proxy.ProxySocketPairGeneric(processors.PassThroughProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort) catch |err| {
            try stderr.print("ERROR: Failed to initialize proxy: {}\n", .{err});
            return;
        };
        defer proxy_instance.deinit();
        proxy_instance.start(5000) catch |err| {
            try stderr.print("ERROR: Proxy failed to start: {}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, processor_type, "logging")) {
        const processor = processors.LoggingProcessor.init(allocator);
        var proxy_instance = try proxy.ProxySocketPairGeneric(processors.LoggingProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy_instance.deinit();
        try proxy_instance.start(5000);
    } else if (std.mem.eql(u8, processor_type, "filtering")) {
        const pattern = if (args.len > 6) args[6] else "DROP";
        const processor = processors.FilteringProcessor.init(pattern);
        var proxy_instance = try proxy.ProxySocketPairGeneric(processors.FilteringProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy_instance.deinit();
        try proxy_instance.start(5000);
        try stdout.print("Filtered packets containing: {s}\n", .{pattern});
    } else if (std.mem.eql(u8, processor_type, "custom")) {
        const processor = processors.CustomProcessor.init();
        var proxy_instance = try proxy.ProxySocketPairGeneric(processors.CustomProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy_instance.deinit();
        try proxy_instance.start(5000);
        try stdout.print("Processed {d} packets with header manipulation\n", .{processor.packet_count});
    } else if (std.mem.eql(u8, processor_type, "srt-nak")) {
        const processor = processors.SRTNakMalformerProcessor.init();
        var proxy_instance = try proxy.ProxySocketPairGeneric(processors.SRTNakMalformerProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy_instance.deinit();
        try proxy_instance.start(5000);
        try stdout.print("Malformed {d} SRT NAK packets\n", .{processor.malform_count});
    } else if (std.mem.eql(u8, processor_type, "srt-nak-bidir")) {
        const processor = processors.BidirectionalSRTNakMalformerProcessor.init();
        var proxy_instance = try proxy.ProxySocketPairGeneric(processors.BidirectionalSRTNakMalformerProcessor).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy_instance.deinit();
        try proxy_instance.start(5000);
        try stdout.print("Malformed NAK packets - L->F: {d}, F->L: {d}\n", .{ processor.listener_to_forward_count, processor.forward_to_listener_count });
    } else if (std.mem.startsWith(u8, processor_type, "drop-")) {
        const drop_pos_str = processor_type[5..];
        const drop_pos = std.fmt.parseInt(i32, drop_pos_str, 10) catch {
            try stderr.print("Invalid drop position: {s}\n", .{drop_pos_str});
            return;
        };

        if (drop_pos == 100) {
            const DropperType = processors.PacketDropperProcessor(100);
            const processor = DropperType.init();
            var proxy_instance = try proxy.ProxySocketPairGeneric(DropperType).init(processor, listenIP, listenPort, forwardIP, forwardPort);
            defer proxy_instance.deinit();
            try proxy_instance.start(5000);
            try stdout.print("Dropped packets 99, 100, and 101\n", .{});
        } else if (drop_pos == 1000) {
            const DropperType = processors.PacketDropperProcessor(1000);
            const processor = DropperType.init();
            var proxy_instance = try proxy.ProxySocketPairGeneric(DropperType).init(processor, listenIP, listenPort, forwardIP, forwardPort);
            defer proxy_instance.deinit();
            try proxy_instance.start(5000);
            try stdout.print("Dropped packets 999, 1000, and 1001\n", .{});
        } else {
            try stderr.print("Unsupported drop position: {d} (only 100 and 1000 are supported)\n", .{drop_pos});
            try printUsage(args[0]);
        }
    } else {
        try stderr.print("Unknown processor type: {s}\n", .{processor_type});
        try printUsage(args[0]);
    }
}

fn printUsage(program_name: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\Usage: {s} <listen_ip> <listen_port> <forward_ip> <forward_port> [processor_type] [args...]
        \\
        \\Processor types:
        \\  passthrough     - Forward all packets unchanged (default)
        \\  logging         - Log packet information
        \\  filtering       - Drop packets containing pattern (specify pattern as 6th arg)
        \\  custom          - Add/remove 'FWD:' headers
        \\  srt-nak         - Malform SRT NAK packets (listener->forward)
        \\  srt-nak-bidir   - Malform SRT NAK packets (both directions)
        \\  drop-100        - Drop packets 99, 100, and 101
        \\  drop-1000       - Drop packets 999, 1000, and 1001
        \\
        \\Examplesg
        \\  {s} 127.0.0.1 8080 192.168.1.100 9090
        \\  {s} 127.0.0.1 8080 192.168.1.100 9090 logging
        \\  {s} 127.0.0.1 8080 192.168.1.100 9090 filtering SPAM
        \\  {s} 127.0.0.1 8080 192.168.1.100 9090 srt-nak
        \\
    , .{ program_name, program_name, program_name, program_name, program_name });
}

