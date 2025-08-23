const std = @import("std");

/// Custom packet processor that adds/removes headers and tracks statistics
pub const CustomProcessor = struct {
    packet_count: u64,
    
    pub fn init() CustomProcessor {
        return .{ .packet_count = 0 };
    }
    
    pub fn processListenerToForward(self: *CustomProcessor, buffer: []u8, packet: []u8) []u8 {
        self.packet_count += 1;
        
        // Example: Add a simple header to packets going forward
        if (packet.len > 0 and packet.len + 4 <= buffer.len) {
            // Calculate packet start within buffer
            const packet_start = @intFromPtr(packet.ptr) - @intFromPtr(buffer.ptr);
            
            // Check if we have space to expand
            if (packet_start + packet.len + 4 <= buffer.len) {
                // Shift data to make room for header
                std.mem.copyBackwards(u8, buffer[packet_start + 4..packet_start + packet.len + 4], packet);
                buffer[packet_start] = 'F';
                buffer[packet_start + 1] = 'W';
                buffer[packet_start + 2] = 'D';
                buffer[packet_start + 3] = ':';
                return buffer[packet_start..packet_start + packet.len + 4];
            }
        }
        
        return packet;
    }
    
    pub fn processForwardToListener(self: *CustomProcessor, _: []u8, packet: []u8) []u8 {
        _ = self;
        
        // Example: Remove the header from return packets
        if (packet.len >= 4 and packet[0] == 'F' and packet[1] == 'W' and packet[2] == 'D' and packet[3] == ':') {
            // Remove header by returning a slice starting from position 4
            return packet[4..];
        }
        
        return packet;
    }
};

test "CustomProcessor adds and removes headers" {
    var processor = CustomProcessor.init();
    
    // Test adding header
    var buffer = [_]u8{'H', 'e', 'l', 'l', 'o', 0, 0, 0, 0}; // Extra space for header
    const result1 = processor.processListenerToForward(&buffer, buffer[0..5]);
    try std.testing.expect(result1.len == 9); // 5 + 4 byte header
    try std.testing.expect(result1[0] == 'F' and result1[1] == 'W' and result1[2] == 'D' and result1[3] == ':');
    try std.testing.expect(result1[4] == 'H' and result1[5] == 'e'); // Original data shifted
    try std.testing.expect(processor.packet_count == 1);
    
    // Test removing header
    const result2 = processor.processForwardToListener(&buffer, result1);
    try std.testing.expect(result2.len == 5); // Back to original size
    try std.testing.expect(result2[0] == 'H' and result2[1] == 'e'); // Header removed
}

test "CustomProcessor handles large packets" {
    var processor = CustomProcessor.init();
    
    // Large packet that can't have header added (buffer exactly matches packet size)
    var large_buffer: [100]u8 = undefined;
    @memset(&large_buffer, 'A');
    
    const result = processor.processListenerToForward(&large_buffer, &large_buffer);
    try std.testing.expect(result.len == large_buffer.len); // No modification (no space for header)
    try std.testing.expect(processor.packet_count == 1);
}