const std = @import("std");

/// Processor that discards three packets after a specified number
pub fn PacketDropperProcessor(comptime packet_limit: comptime_int) type {
    return struct {
        const Self = @This();
        packet_counter: i32,
        
        pub fn init() Self {
            return .{ .packet_counter = 0 };
        }
        
        pub fn processListenerToForward(self: *Self, buffer: []u8, packet: []u8) []u8 {
            _ = buffer;
            if (self.packet_counter <= packet_limit + 50) {
                self.packet_counter += 1;
            }
            
            if (@abs(self.packet_counter - packet_limit) <= 1) { // Drops three packets
                @memset(packet, 0);
                return packet[0..0]; // Return empty slice to indicate packet drop
            }
            return packet;
        }
        
        pub fn processForwardToListener(self: *Self, buffer: []u8, packet: []u8) []u8 {
            _ = self;
            _ = buffer;
            return packet; // No processing in reverse direction
        }
    };
}

test "PacketDropperProcessor drops three packets" {
    const correctData = [_]u8{
        0x00, 0xde, 0xad, 0xbe,
        0xeb, 0xbe, 0xef, 0x11,
        0x22, 0x33, 0x55, 0x77,
    };
    
    const DropperType = PacketDropperProcessor(100);
    var dropper = DropperType.init();
    
    for (1..200) |i| {
        var packet = correctData;
        var buffer: [4096]u8 = undefined;
        const result = dropper.processListenerToForward(&buffer, &packet);
        
        if (i == 99 or i == 100 or i == 101) {
            const zeroedData = [_]u8{0} ** correctData.len;
            try std.testing.expect(std.mem.eql(u8, &zeroedData, &packet));
            try std.testing.expect(result.len == 0);
        } else {
            try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
            try std.testing.expect(result.len == packet.len);
        }
    }
}

test "PacketDropperProcessor different limits" {
    const DropperType5 = PacketDropperProcessor(5);
    var dropper5 = DropperType5.init();
    
    const data = [_]u8{1, 2, 3, 4, 5};
    
    // Packets 4, 5, 6 should be dropped
    for (1..10) |i| {
        var packet = data;
        var buffer: [4096]u8 = undefined;
        const result = dropper5.processListenerToForward(&buffer, &packet);
        
        if (i >= 4 and i <= 6) {
            try std.testing.expect(result.len == 0);
        } else {
            try std.testing.expect(result.len == data.len);
        }
    }
}