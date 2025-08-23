const std = @import("std");

/// Simple pass-through processor that forwards all packets unchanged
pub const PassThroughProcessor = struct {
    pub fn processListenerToForward(_: *PassThroughProcessor, _: []u8, packet: []u8) []u8 {
        return packet;
    }
    
    pub fn processForwardToListener(_: *PassThroughProcessor, _: []u8, packet: []u8) []u8 {
        return packet;
    }
};

test "PassThroughProcessor forwards packets unchanged" {
    var processor = PassThroughProcessor{};
    
    var buffer = [_]u8{1, 2, 3, 4, 5, 0, 0, 0}; // Extra space for expansion
    const original_data = buffer[0..5];
    
    // Test listener to forward
    const result1 = processor.processListenerToForward(&buffer, buffer[0..5]);
    try std.testing.expect(result1.len == original_data.len);
    try std.testing.expect(std.mem.eql(u8, result1, original_data));
    
    // Test forward to listener
    const result2 = processor.processForwardToListener(&buffer, buffer[0..5]);
    try std.testing.expect(result2.len == original_data.len);
    try std.testing.expect(std.mem.eql(u8, result2, original_data));
}