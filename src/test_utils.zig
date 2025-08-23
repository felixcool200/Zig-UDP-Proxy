const std = @import("std");

pub const MockSocket = struct {
    received_packets: std.ArrayList([]u8),
    packets_to_send: std.ArrayList([]u8),
    send_error: ?anyerror = null,
    recv_error: ?anyerror = null,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) MockSocket {
        return .{
            .received_packets = std.ArrayList([]u8).init(allocator),
            .packets_to_send = std.ArrayList([]u8).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *MockSocket) void {
        for (self.received_packets.items) |packet| {
            self.allocator.free(packet);
        }
        for (self.packets_to_send.items) |packet| {
            self.allocator.free(packet);
        }
        self.received_packets.deinit();
        self.packets_to_send.deinit();
    }
    
    pub fn queuePacket(self: *MockSocket, data: []const u8) !void {
        const packet = try self.allocator.dupe(u8, data);
        try self.packets_to_send.append(packet);
    }
    
    pub fn mockRecv(self: *MockSocket, buffer: []u8) !usize {
        if (self.recv_error) |err| return err;
        
        if (self.packets_to_send.items.len == 0) return 0;
        
        const packet = self.packets_to_send.orderedRemove(0);
        defer self.allocator.free(packet);
        
        const copy_len = @min(packet.len, buffer.len);
        @memcpy(buffer[0..copy_len], packet[0..copy_len]);
        return copy_len;
    }
    
    pub fn mockSend(self: *MockSocket, data: []const u8) !usize {
        if (self.send_error) |err| return err;
        
        const packet = try self.allocator.dupe(u8, data);
        try self.received_packets.append(packet);
        return data.len;
    }
};

// Test helper for integration testing
pub fn testProxyIntegration(
    comptime ProcessorType: type,
    processor: ProcessorType,
    test_packets: []const []const u8,
    allocator: std.mem.Allocator
) !void {
    _ = processor;
    _ = test_packets;
    _ = allocator;
    // Would implement full proxy mock test here
}

test "MockSocket basic functionality" {
    var mock = MockSocket.init(std.testing.allocator);
    defer mock.deinit();
    
    // Queue a packet to be "received"
    try mock.queuePacket("test packet");
    
    // Mock receiving it
    var buffer: [100]u8 = undefined;
    const received = try mock.mockRecv(&buffer);
    try std.testing.expect(received == 11);
    try std.testing.expect(std.mem.eql(u8, buffer[0..11], "test packet"));
    
    // Mock sending a packet
    const sent = try mock.mockSend("response packet");
    try std.testing.expect(sent == 15);
    try std.testing.expect(mock.received_packets.items.len == 1);
    try std.testing.expect(std.mem.eql(u8, mock.received_packets.items[0], "response packet"));
}