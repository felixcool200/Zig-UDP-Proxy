const std = @import("std");
const proxy = @import("proxy.zig");
const test_utils = @import("test_utils.zig");
const processors = @import("processors.zig");

const CustomProcessor = processors.CustomProcessor;

// Mock version of the proxy socket operations for testing
const MockProxySocketPair = struct {
    const Self = @This();
    
    listener_mock: test_utils.MockSocket,
    forward_mock: test_utils.MockSocket,
    processor: CustomProcessor,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .listener_mock = test_utils.MockSocket.init(allocator),
            .forward_mock = test_utils.MockSocket.init(allocator),
            .processor = CustomProcessor.init(),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.listener_mock.deinit();
        self.forward_mock.deinit();
    }
    
    // Simulate the main proxy processing logic
    pub fn processPacket(self: *Self, from_listener: bool) !?struct { bytes_in: usize, bytes_out: usize } {
        var buffer: [4096]u8 = undefined;
        
        // Mock receiving packet
        const bytes_received = if (from_listener) 
            try self.listener_mock.mockRecv(&buffer)
        else
            try self.forward_mock.mockRecv(&buffer);
            
        if (bytes_received == 0) return null;
        
        // Process packet through processor
        const result = if (from_listener)
            self.processor.processListenerToForward(&buffer, buffer[0..bytes_received])
        else
            self.processor.processForwardToListener(&buffer, buffer[0..bytes_received]);
            
        if (result.len == 0) return .{ .bytes_in = bytes_received, .bytes_out = 0 }; // Dropped
        
        // Mock sending packet
        const bytes_sent = if (from_listener)
            try self.forward_mock.mockSend(result)
        else
            try self.listener_mock.mockSend(result);
            
        return .{ .bytes_in = bytes_received, .bytes_out = bytes_sent };
    }
};

test "main_generic proxy logic with mock UDP - listener to forward" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Queue incoming packet on listener
    try mock_proxy.listener_mock.queuePacket("Hello World");
    
    // Process the packet
    const result = try mock_proxy.processPacket(true);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.bytes_in == 11); // "Hello World"
    try std.testing.expect(result.?.bytes_out == 15); // "FWD:Hello World"
    
    // Verify packet was processed and forwarded
    try std.testing.expect(mock_proxy.processor.packet_count == 1);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, mock_proxy.forward_mock.received_packets.items[0], "FWD:Hello World"));
}

test "main_generic proxy logic with mock UDP - forward to listener" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Queue response packet on forward socket (with header)
    try mock_proxy.forward_mock.queuePacket("FWD:Response");
    
    // Process the packet
    const result = try mock_proxy.processPacket(false);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.bytes_in == 12); // "FWD:Response"
    try std.testing.expect(result.?.bytes_out == 8); // "Response"
    
    // Verify packet was processed and sent back to listener
    try std.testing.expect(mock_proxy.listener_mock.received_packets.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, mock_proxy.listener_mock.received_packets.items[0], "Response"));
}

test "main_generic proxy logic with mock UDP - packet dropping" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Queue a packet that's too large to add header (simulate buffer full)
    var large_packet: [4096]u8 = undefined;
    @memset(&large_packet, 'A');
    try mock_proxy.listener_mock.queuePacket(&large_packet);
    
    // Process the packet - should pass through unchanged
    const result = try mock_proxy.processPacket(true);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.bytes_in == 4096);
    try std.testing.expect(result.?.bytes_out == 4096); // No header added
    
    // Verify original packet was forwarded
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 1);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items[0].len == 4096);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items[0][0] == 'A');
}

test "main_generic proxy logic with mock UDP - no packets available" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Don't queue any packets
    
    // Try to process - should return null (no data)
    const result = try mock_proxy.processPacket(true);
    try std.testing.expect(result == null);
    
    // Verify no processing occurred
    try std.testing.expect(mock_proxy.processor.packet_count == 0);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 0);
}

test "main_generic proxy logic with mock UDP - error handling" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Queue packet and set send error
    try mock_proxy.listener_mock.queuePacket("test");
    mock_proxy.forward_mock.send_error = error.NetworkUnreachable;
    
    // Processing should fail with the mock error
    try std.testing.expectError(error.NetworkUnreachable, mock_proxy.processPacket(true));
    
    // Verify packet was received and processed but not sent
    try std.testing.expect(mock_proxy.processor.packet_count == 1);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 0);
}

test "main_generic proxy logic with mock UDP - bidirectional flow" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    // Simulate request-response flow
    
    // 1. Client sends request to listener
    try mock_proxy.listener_mock.queuePacket("REQUEST");
    var result = try mock_proxy.processPacket(true);
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.eql(u8, mock_proxy.forward_mock.received_packets.items[0], "FWD:REQUEST"));
    
    // 2. Server responds via forward socket
    try mock_proxy.forward_mock.queuePacket("FWD:RESPONSE");
    result = try mock_proxy.processPacket(false);
    try std.testing.expect(result != null);
    try std.testing.expect(std.mem.eql(u8, mock_proxy.listener_mock.received_packets.items[0], "RESPONSE"));
    
    // Verify complete bidirectional flow
    try std.testing.expect(mock_proxy.processor.packet_count == 1); // Only counts listener->forward
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 1);
    try std.testing.expect(mock_proxy.listener_mock.received_packets.items.len == 1);
}

// Integration test simulating multiple packets like main_generic would handle
test "main_generic proxy logic with mock UDP - multiple packet session" {
    var mock_proxy = MockProxySocketPair.init(std.testing.allocator);
    defer mock_proxy.deinit();
    
    const test_packets = [_][]const u8{
        "packet1",
        "packet2", 
        "packet3",
    };
    
    // Queue multiple packets
    for (test_packets) |packet| {
        try mock_proxy.listener_mock.queuePacket(packet);
    }
    
    // Process all packets
    var packets_processed: u32 = 0;
    while (try mock_proxy.processPacket(true)) |result| {
        try std.testing.expect(result.bytes_out > result.bytes_in); // Header was added
        packets_processed += 1;
    }
    
    // Verify all packets were processed
    try std.testing.expect(packets_processed == 3);
    try std.testing.expect(mock_proxy.processor.packet_count == 3);
    try std.testing.expect(mock_proxy.forward_mock.received_packets.items.len == 3);
    
    // Verify headers were added correctly
    try std.testing.expect(std.mem.eql(u8, mock_proxy.forward_mock.received_packets.items[0], "FWD:packet1"));
    try std.testing.expect(std.mem.eql(u8, mock_proxy.forward_mock.received_packets.items[1], "FWD:packet2"));
    try std.testing.expect(std.mem.eql(u8, mock_proxy.forward_mock.received_packets.items[2], "FWD:packet3"));
}