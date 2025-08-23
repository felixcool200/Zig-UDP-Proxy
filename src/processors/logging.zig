const std = @import("std");

/// Processor that logs packet information while forwarding
pub const LoggingProcessor = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File,
    
    pub fn init(allocator: std.mem.Allocator) LoggingProcessor {
        return .{
            .allocator = allocator,
            .log_file = null,
        };
    }
    
    pub fn processListenerToForward(self: *LoggingProcessor, _: []u8, packet: []u8) []u8 {
        std.log.info("Listener->Forward: {d} bytes", .{packet.len});
        _ = self;
        return packet;
    }
    
    pub fn processForwardToListener(self: *LoggingProcessor, _: []u8, packet: []u8) []u8 {
        std.log.info("Forward->Listener: {d} bytes", .{packet.len});
        _ = self;
        return packet;
    }
};

test "LoggingProcessor forwards packets and logs" {
    var processor = LoggingProcessor.init(std.testing.allocator);
    
    var buffer = [_]u8{1, 2, 3, 4, 5};
    const original_data = buffer;
    
    // Test listener to forward (should log and forward)
    const result1 = processor.processListenerToForward(&buffer, &buffer);
    try std.testing.expect(result1.len == buffer.len);
    try std.testing.expect(std.mem.eql(u8, result1, &original_data));
    
    // Test forward to listener (should log and forward)
    const result2 = processor.processForwardToListener(&buffer, &buffer);
    try std.testing.expect(result2.len == buffer.len);
    try std.testing.expect(std.mem.eql(u8, result2, &original_data));
}