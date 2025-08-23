const std = @import("std");

/// Processor that drops packets containing a specific pattern
pub const FilteringProcessor = struct {
    drop_pattern: []const u8,
    
    pub fn init(pattern: []const u8) FilteringProcessor {
        return .{ .drop_pattern = pattern };
    }
    
    pub fn processListenerToForward(self: *FilteringProcessor, _: []u8, packet: []u8) []u8 {
        if (std.mem.indexOf(u8, packet, self.drop_pattern)) |_| {
            std.log.info("Dropped packet containing pattern: {s}", .{self.drop_pattern});
            return packet[0..0]; // Drop packet (empty slice)
        }
        return packet;
    }
    
    pub fn processForwardToListener(self: *FilteringProcessor, _: []u8, packet: []u8) []u8 {
        // Allow all packets in reverse direction
        _ = self;
        return packet;
    }
};

test "FilteringProcessor drops packets with pattern" {
    var processor = FilteringProcessor.init("DROP");
    
    // Test packet without pattern - should pass
    var buffer1 = [_]u8{'H', 'e', 'l', 'l', 'o'};
    const result1 = processor.processListenerToForward(&buffer1, &buffer1);
    try std.testing.expect(result1.len == buffer1.len);
    
    // Test packet with pattern - should drop
    var buffer2 = [_]u8{'D', 'R', 'O', 'P', 'M', 'E'};
    const result2 = processor.processListenerToForward(&buffer2, &buffer2);
    try std.testing.expect(result2.len == 0);
    
    // Test reverse direction - should always pass
    const result3 = processor.processForwardToListener(&buffer2, &buffer2);
    try std.testing.expect(result3.len == buffer2.len);
}

test "FilteringProcessor with different patterns" {
    var processor = FilteringProcessor.init("BAD");
    
    var data1 = [_]u8{'G', 'O', 'O', 'D'};
    var data2 = [_]u8{'B', 'A', 'D', 'D', 'A', 'T', 'A'};
    
    try std.testing.expect(processor.processListenerToForward(&data1, &data1).len == data1.len);
    try std.testing.expect(processor.processListenerToForward(&data2, &data2).len == 0);
}