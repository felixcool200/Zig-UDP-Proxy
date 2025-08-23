const std = @import("std");

/// SRT NAK malformer processor (unidirectional)
pub const SRTNakMalformerProcessor = struct {
    malform_count: u64,
    
    pub fn init() SRTNakMalformerProcessor {
        return .{ .malform_count = 0 };
    }
    
    pub fn processListenerToForward(self: *SRTNakMalformerProcessor, buffer: []u8, packet: []u8) []u8 {
        _ = buffer;
        // This is a NAK with only a range (based on length),
        // and the first field represents a range (starting with 1).
        if (packet.len == 24 and packet[1] == 0x03 and packet[16] & 0x80 != 0) {
            @memset(packet[20..24], 0xff);
            self.malform_count += 1;
        }
        return packet;
    }
    
    pub fn processForwardToListener(self: *SRTNakMalformerProcessor, buffer: []u8, packet: []u8) []u8 {
        _ = self;
        _ = buffer;
        return packet; // No processing in reverse direction
    }
};

test "SRTNakMalformerProcessor: Change packet" {
    var processor = SRTNakMalformerProcessor.init();
    
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    
    const expected = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0xff, 0xff, 0xff, 0xff,
    };
    
    var buffer: [4096]u8 = undefined;
    const result = processor.processListenerToForward(&buffer, &packet);
    try std.testing.expect(std.mem.eql(u8, &expected, &packet));
    try std.testing.expect(result.len == packet.len);
    try std.testing.expect(processor.malform_count == 1);
}

test "SRTNakMalformerProcessor: No change to packet longer" {
    var processor = SRTNakMalformerProcessor.init();
    
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
        0x2a, 0xd4, 0x2a, 0xf2,
    };
    
    const expected = packet;
    
    var buffer: [4096]u8 = undefined;
    const result = processor.processListenerToForward(&buffer, &packet);
    try std.testing.expect(std.mem.eql(u8, &expected, &packet));
    try std.testing.expect(result.len == packet.len);
    try std.testing.expect(processor.malform_count == 0);
}

test "SRTNakMalformerProcessor: No change to packet shorter" {
    var processor = SRTNakMalformerProcessor.init();
    
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    
    const expected = packet;
    
    var buffer: [4096]u8 = undefined;
    const result = processor.processListenerToForward(&buffer, &packet);
    try std.testing.expect(std.mem.eql(u8, &expected, &packet));
    try std.testing.expect(result.len == packet.len);
    try std.testing.expect(processor.malform_count == 0);
}

test "SRTNakMalformerProcessor: No change to packet 2 packets, no range" {
    var processor = SRTNakMalformerProcessor.init();
    
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe1,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    
    const expected = packet;
    
    var buffer: [4096]u8 = undefined;
    const result = processor.processListenerToForward(&buffer, &packet);
    try std.testing.expect(std.mem.eql(u8, &expected, &packet));
    try std.testing.expect(result.len == packet.len);
    try std.testing.expect(processor.malform_count == 0);
}