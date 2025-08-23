const std = @import("std");

/// Bidirectional SRT NAK malformer
pub const BidirectionalSRTNakMalformerProcessor = struct {
    listener_to_forward_count: u64,
    forward_to_listener_count: u64,
    
    pub fn init() BidirectionalSRTNakMalformerProcessor {
        return .{ 
            .listener_to_forward_count = 0,
            .forward_to_listener_count = 0,
        };
    }
    
    fn malformNak(packet: []u8) []u8 {
        if (packet.len == 24 and packet[1] == 0x03 and packet[16] & 0x80 != 0) {
            @memset(packet[20..24], 0xff);
        }
        return packet;
    }
    
    pub fn processListenerToForward(self: *BidirectionalSRTNakMalformerProcessor, buffer: []u8, packet: []u8) []u8 {
        _ = buffer;
        const result = malformNak(packet);
        if (packet.len == 24 and packet[20] == 0xff) {
            self.listener_to_forward_count += 1;
        }
        return result;
    }
    
    pub fn processForwardToListener(self: *BidirectionalSRTNakMalformerProcessor, buffer: []u8, packet: []u8) []u8 {
        _ = buffer;
        const result = malformNak(packet);
        if (packet.len == 24 and packet[20] == 0xff) {
            self.forward_to_listener_count += 1;
        }
        return result;
    }
};

test "BidirectionalSRTNakMalformerProcessor both directions" {
    var processor = BidirectionalSRTNakMalformerProcessor.init();
    
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    
    // Test listener to forward
    var buffer: [4096]u8 = undefined;
    _ = processor.processListenerToForward(&buffer, &packet);
    try std.testing.expect(processor.listener_to_forward_count == 1);
    try std.testing.expect(processor.forward_to_listener_count == 0);
    
    // Reset packet for reverse test
    packet[20] = 0x2a;
    packet[21] = 0xd4;
    packet[22] = 0x2a;
    packet[23] = 0xe7;
    
    // Test forward to listener
    _ = processor.processForwardToListener(&buffer, &packet);
    try std.testing.expect(processor.listener_to_forward_count == 1);
    try std.testing.expect(processor.forward_to_listener_count == 1);
}