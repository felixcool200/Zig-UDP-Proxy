const std = @import("std");
const udp_proxy = @import("udp-proxy");

// Example custom processor for statistics tracking
const StatsProcessor = struct {
    listener_to_forward_packets: u64,
    forward_to_listener_packets: u64,
    total_bytes: u64,

    pub fn init() StatsProcessor {
        return .{
            .listener_to_forward_packets = 0,
            .forward_to_listener_packets = 0,
            .total_bytes = 0,
        };
    }

    pub fn processListenerToForward(self: *StatsProcessor, buffer: []u8, packet: []u8) []u8 {
        self.listener_to_forward_packets += 1;
        self.total_bytes += packet.len;
        _ = buffer;
        return packet;
    }

    pub fn processForwardToListener(self: *StatsProcessor, buffer: []u8, packet: []u8) []u8 {
        self.forward_to_listener_packets += 1;
        self.total_bytes += packet.len;
        _ = buffer;
        return packet;
    }

    pub fn printStats(self: *const StatsProcessor) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("=== Proxy Statistics ===\n", .{});
        try stdout.print("Listener->Forward packets: {d}\n", .{self.listener_to_forward_packets});
        try stdout.print("Forward->Listener packets: {d}\n", .{self.forward_to_listener_packets});
        try stdout.print("Total bytes proxied: {d}\n", .{self.total_bytes});
        try stdout.print("========================\n", .{});
    }
};

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

    if (args.len < 6) {
        try stdout.print("Usage: {s} <mode> <listen_ip> <listen_port> <forward_ip> <forward_port>\n", .{args[0]});
        try stdout.print("Modes:\n", .{});
        try stdout.print("  simple   - Use simple API with built-in event loop\n", .{});
        try stdout.print("  advanced - Use advanced API with custom event loop\n", .{});
        try stdout.print("  builtin  - Demonstrate all built-in processors\n", .{});
        return;
    }

    const mode = args[1];
    const listenIP = args[2];
    const listenPort = try std.fmt.parseInt(u16, args[3], 10);
    const forwardIP = args[4];
    const forwardPort = try std.fmt.parseInt(u16, args[5], 10);

    try stdout.print("UDP Proxy: {s}:{d} -> {s}:{d}\n", .{ listenIP, listenPort, forwardIP, forwardPort });

    if (std.mem.eql(u8, mode, "simple")) {
        try runSimpleExample(listenIP, listenPort, forwardIP, forwardPort);
    } else if (std.mem.eql(u8, mode, "advanced")) {
        try runAdvancedExample(listenIP, listenPort, forwardIP, forwardPort);
    } else if (std.mem.eql(u8, mode, "builtin")) {
        try runBuiltinProcessorsExample(allocator, listenIP, listenPort, forwardIP, forwardPort);
    } else {
        try stderr.print("Unknown mode: {s}\n", .{mode});
        try stderr.print("Available modes: simple, advanced, builtin\n", .{});
    }
}

fn runSimpleExample(listenIP: []const u8, listenPort: u16, forwardIP: []const u8, forwardPort: u16) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Simple API Example ===\n", .{});

    // Create a proxy with statistics tracking
    var processor = StatsProcessor.init();
    var proxy = try udp_proxy.ProxySocketPairGeneric(StatsProcessor).init(
        processor,
        listenIP,
        listenPort,
        forwardIP,
        forwardPort,
    );
    defer proxy.deinit();

    // Simple API - just call start() and it handles everything
    try stdout.print("Starting proxy with simple API...\n", .{});
    try proxy.start(10000); // 10 second timeout

    // Print stats after proxy stops
    try processor.printStats();
}

fn runAdvancedExample(listenIP: []const u8, listenPort: u16, forwardIP: []const u8, forwardPort: u16) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Advanced API Example ===\n", .{});

    // Create a proxy with statistics tracking
    var processor = StatsProcessor.init();
    var proxy = try udp_proxy.ProxySocketPairGeneric(StatsProcessor).init(
        processor,
        listenIP,
        listenPort,
        forwardIP,
        forwardPort,
    );
    defer proxy.deinit();

    // Advanced API - manual control over the event loop
    try proxy.bind();

    var buffer: [4096]u8 = undefined;
    var packet_count: u32 = 0;
    const max_packets = 100; // Process at most 100 packets for this example

    try stdout.print("Starting proxy with advanced API (max {d} packets)...\n", .{max_packets});

    // Custom event loop with packet counting
    while (packet_count < max_packets) {
        // Poll for events with 5 second timeout
        const poll_result = try proxy.poll(5000);

        if (!poll_result.has_events) {
            try stdout.print("No events in 5 seconds, continuing...\n", .{});
            continue;
        }

        // Process each ready socket
        for (poll_result.pollfds) |fd| {
            if (try proxy.processEvent(fd, &buffer)) |result| {
                packet_count += 1;

                try stdout.print("Packet #{d}: {d} bytes {s}\n", .{
                    packet_count,
                    result.bytes_processed,
                    if (result.direction == .ListenerToForward) "L->F" else "F->L",
                });

                // Print stats every 10 packets
                if (packet_count % 10 == 0) {
                    try processor.printStats();
                }
            }
        }
    }

    try stdout.print("Processed {d} packets, stopping.\n", .{packet_count});
    try processor.printStats();
}

fn runBuiltinProcessorsExample(allocator: std.mem.Allocator, listenIP: []const u8, listenPort: u16, forwardIP: []const u8, forwardPort: u16) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Built-in Processors Examples ===\n", .{});

    // Example 1: PassThroughProcessor (default behavior)
    try stdout.print("\n1. Pass-Through Processor:\n", .{});
    {
        const processor = udp_proxy.PassThroughProcessor{};
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Forwards all packets unchanged\n", .{});
        // Would run: try proxy.start(2000);
    }

    // Example 2: LoggingProcessor
    try stdout.print("\n2. Logging Processor:\n", .{});
    {
        const processor = udp_proxy.LoggingProcessor.init(allocator);
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Logs packet size and direction\n", .{});
        // Would run: try proxy.start(2000);
    }

    // Example 3: FilteringProcessor
    try stdout.print("\n3. Filtering Processor:\n", .{});
    {
        const processor = udp_proxy.FilteringProcessor.init("SPAM");
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Drops packets containing 'SPAM'\n", .{});
        // Would run: try proxy.start(2000);
    }

    // Example 4: CustomProcessor with header manipulation
    try stdout.print("\n4. Custom Processor:\n", .{});
    {
        const processor = udp_proxy.CustomProcessor.init();
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Adds 'FWD:' header going forward, removes it coming back\n", .{});
        // Would run: try proxy.start(2000);
        try stdout.print("   Processed packets: {d}\n", .{processor.packet_count});
    }

    // Example 5: SRT NAK Malformer
    try stdout.print("\n5. SRT NAK Malformer:\n", .{});
    {
        const processor = udp_proxy.SRTNakMalformerProcessor.init();
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Malforms SRT NAK packets for testing\n", .{});
        // Would run: try proxy.start(2000);
        try stdout.print("   Malformed packets: {d}\n", .{processor.malform_count});
    }

    // Example 6: Packet Dropper
    try stdout.print("\n6. Packet Dropper (drops packets 99, 100, 101):\n", .{});
    {
        const processor = udp_proxy.PacketDropperProcessor.init(99, 3);
        var proxy = try udp_proxy.ProxySocketPairGeneric(@TypeOf(processor)).init(processor, listenIP, listenPort, forwardIP, forwardPort);
        defer proxy.deinit();

        try stdout.print("   Drops exactly 3 packets at position 100\n", .{});
        // Would run: try proxy.start(2000);
    }

    try stdout.print("\nAll built-in processors demonstrated!\n", .{});
}

