const std = @import("std");

/// Processor that drops a configurable number of packets starting at a runtime-defined packet number
pub const PacketDropperProcessor = struct {
    const Self = @This();
    drop_pos: u32, // packet index to start dropping
    drop_count: u32, // number of packets to drop
    packet_counter: u32, // how many packets processed so far

    pub fn init(drop_pos: u32, drop_count: u32) Self {
        return Self{
            .drop_pos = drop_pos,
            .drop_count = drop_count,
            .packet_counter = 0,
        };
    }

    pub fn processListenerToForward(self: *Self, buffer: []u8, packet: []u8) []u8 {
        _ = buffer;

        // Early return if the drop_pos is far in the past
        if (self.packet_counter > self.drop_pos + self.drop_count + 50) {
            return packet;
        }

        self.packet_counter += 1;

        // Drop packets if within the drop window
        if (self.packet_counter >= self.drop_pos and
            self.packet_counter < self.drop_pos + self.drop_count)
        {
            @memset(packet, 0);
            return packet[0..0]; // indicate drop
        }

        return packet; // forward normally
    }

    pub fn processForwardToListener(self: *Self, buffer: []u8, packet: []u8) []u8 {
        _ = self;
        _ = buffer;
        return packet;
    }
};

test "PacketDropperProcessor drops three packets at runtime position" {
    const correctData = [_]u8{
        0x00, 0xde, 0xad, 0xbe,
        0xeb, 0xbe, 0xef, 0x11,
        0x22, 0x33, 0x55, 0x77,
    };

    const drop_pos = 100;
    const drop_count = 3;
    var dropper = PacketDropperProcessor.init(drop_pos, drop_count);

    for (1..200) |i| {
        var packet = correctData;
        var buffer: [4096]u8 = undefined;
        const result = dropper.processListenerToForward(&buffer, &packet);

        if (i >= drop_pos and i < drop_pos + drop_count) {
            const zeroedData = [_]u8{0} ** correctData.len;
            try std.testing.expect(std.mem.eql(u8, &zeroedData, &packet));
            try std.testing.expect(result.len == 0);
        } else {
            try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
            try std.testing.expect(result.len == packet.len);
        }
    }
}

test "PacketDropperProcessor different drop counts" {
    const data = [_]u8{ 1, 2, 3, 4, 5 };

    const test_cases = .{
        .{ .pos = 2, .count = 1 },
        .{ .pos = 3, .count = 2 },
        .{ .pos = 1, .count = 4 },
    };

    inline for (test_cases) |tc| {
        var dropper = PacketDropperProcessor.init(tc.pos, tc.count);

        for (1..10) |i| {
            var packet = data;
            var buffer: [4096]u8 = undefined;
            const result = dropper.processListenerToForward(&buffer, &packet);

            if (i >= tc.pos and i < tc.pos + tc.count) {
                try std.testing.expect(result.len == 0);
            } else {
                try std.testing.expect(result.len == data.len);
            }
        }
    }
}

test "PacketDropperProcessor does not drop after drop window" {
    const data = [_]u8{ 0x11, 0x22, 0x33 };
    var dropper = PacketDropperProcessor.init(3, 2);

    // Process packets beyond drop window
    for (1..10) |i| {
        var packet = data;
        var buffer: [4096]u8 = undefined;
        const result = dropper.processListenerToForward(&buffer, &packet);

        if (i >= 3 and i < 5) {
            try std.testing.expect(result.len == 0);
        } else {
            try std.testing.expect(result.len == data.len);
        }
    }

    // packet_counter far beyond drop window should just forward
    dropper.packet_counter = 1000;
    var packet = data;
    var buffer: [4096]u8 = undefined;
    const result = dropper.processListenerToForward(&buffer, &packet);
    try std.testing.expect(result.len == data.len);
}

test "PacketDropperProcessor forward-to-listener unchanged" {
    const data = [_]u8{ 0x11, 0x22, 0x33 };
    var dropper = PacketDropperProcessor.init(1, 5);

    for (1..10) |_| {
        var packet = data;
        var buffer: [4096]u8 = undefined;
        const result = dropper.processForwardToListener(&buffer, &packet);

        try std.testing.expect(result.len == data.len);
        try std.testing.expect(std.mem.eql(u8, &data, &packet));
    }
}

test "PacketDropperProcessor zero drop count behaves normally" {
    const data = [_]u8{ 0x11, 0x22, 0x33 };
    var dropper = PacketDropperProcessor.init(5, 0);

    for (1..10) |_| {
        var packet = data;
        var buffer: [4096]u8 = undefined;
        const result = dropper.processListenerToForward(&buffer, &packet);
        try std.testing.expect(result.len == data.len);
        try std.testing.expect(std.mem.eql(u8, &data, &packet));
    }
}
