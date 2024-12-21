const std = @import("std");
const proxy = @import("proxy.zig");

pub fn discardThreePacketsAfter(packetLimit: comptime_int) *const fn ([]u8, usize) usize {
    const PKT_LIMIT = packetLimit;
    const func = struct {
        fn discardThreePackets(data: []u8, dataLen: usize) usize {
            const state = struct {
                var packetCounter: i32 = 0;
            };

            if (state.packetCounter <= PKT_LIMIT + 50) {
                //std.debug.print("PACKET {}\n", .{@abs(state.packetCounter - PKT_LIMIT)});
                state.packetCounter += 1;
            }

            if (@abs(state.packetCounter - PKT_LIMIT) <= 1) { //Drops three packets
                @memset(data, 0);
                //std.debug.print("DROPPING PACKET\n", .{});
                return 0;
            }
            return dataLen;
        }
    };
    return &func.discardThreePackets;
}

// SRT NAK packet format
//    0                   1                   2                   3
//    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//   +-+-+-+-+-+-+-+-+-+-+-+-+- SRT Header +-+-+-+-+-+-+-+-+-+-+-+-+-+
//   |1|        Control Type         |           Reserved            |
//   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//   |                   Type-specific Information                   |
//   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//   |                           Timestamp                           |
//   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//   |                   Destination SRT Socket ID                   |
//   +-+-+-+-+-+-+-+-+-+-+-+- CIF (Loss List) -+-+-+-+-+-+-+-+-+-+-+-+
//   |1|         Range of lost packets from sequence number          |
//   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//   |0|                    Up to sequence number                    |
//   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

pub fn createSRTMalformedNAK(data: []u8, dataLen: usize) usize {
    if (data[1] == 0x03 and dataLen == 24 and data[16] & 0x80 != 0) { //IS A NAK, with only range (based on length), and first field is a range (start with a one)
        //std.debug.print("Found SRT NAK\n", .{});
        @memset(data[20..24], 0xff);
    }
    return dataLen;
}

test "discardThreePackets" {
    const correctData = [_]u8{ 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01 };
    const discardValue = 100;
    for (1..discardValue * 2) |i| {
        var packet = [_]u8{ 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01 };
        const processedBytes = discardThreePacketsAfter(discardValue)(
            &packet,
            packet.len,
        );
        if (i == discardValue - 1 or i == discardValue or i == discardValue + 1) {
            const zeroedData = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
            try std.testing.expect(std.mem.eql(u8, &zeroedData, &packet));
            try std.testing.expect(processedBytes == 0);
        } else {
            try std.testing.expect(std.mem.eql(u8, &correctData, &packet)); // catch std.debug.print("i: {}, data:{any}\n", .{ i, packet });
            try std.testing.expect(processedBytes == packet.len);
        }
    }
}

test "createSRTMalformedNAK: Change packet" {
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    const correctData = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0xff, 0xff, 0xff, 0xff,
    };
    const processedBytes = createSRTMalformedNAK(&packet, packet.len);
    try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
    try std.testing.expect(processedBytes == packet.len);
}

test "createSRTMalformedNAK: No change to packet longer" {
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
        0x2a, 0xd4, 0x2a, 0xf2,
    };
    const correctData = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0xaa, 0xd4, 0x2a, 0xe3,
        0x2a, 0xd4, 0x2a, 0xe7,
        0x2a, 0xd4, 0x2a, 0xf2,
    };
    const processedBytes = createSRTMalformedNAK(&packet, packet.len);
    try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
    try std.testing.expect(processedBytes == packet.len);
}

test "createSRTMalformedNAK: No change to packet shorter" {
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    const correctData = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    const processedBytes = createSRTMalformedNAK(&packet, packet.len);
    try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
    try std.testing.expect(processedBytes == packet.len);
}

test "createSRTMalformedNAK: No change to packet 2 packets, no range" {
    var packet = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe1,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    const correctData = [_]u8{
        0x80, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x29, 0x9d, 0x2a,
        0x3f, 0x0d, 0xa6, 0xfb,
        0x2a, 0xd4, 0x2a, 0xe1,
        0x2a, 0xd4, 0x2a, 0xe7,
    };
    const processedBytes = createSRTMalformedNAK(&packet, packet.len);
    try std.testing.expect(std.mem.eql(u8, &correctData, &packet));
    try std.testing.expect(processedBytes == packet.len);
}
