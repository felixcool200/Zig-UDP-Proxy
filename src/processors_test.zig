const std = @import("std");
const assert = std.debug.assert;
const processors = @import("processors.zig");

test "selectProcessor - basic types" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const basic_cases = .{
        .{ "passthrough", processors.Processor.PassThrough },
        .{ "logging", processors.Processor.Logging },
        .{ "filtering", processors.Processor.Filtering },
        .{ "custom", processors.Processor.Custom },
        .{ "srt-nak", processors.Processor.SRTNak },
        .{ "srt-nak-bidir", processors.Processor.SRTNakBidir },
    };

    inline for (basic_cases) |tc| {
        const processor = try processors.selectProcessor(allocator, tc[0], &.{});
        try std.testing.expectEqual(tc[1], std.meta.activeTag(processor));
    }
}

test "selectProcessor - drop processors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const drop_cases = .{ 1, 100, 500, 1234, 10000 };

    inline for (drop_cases) |pos| {
        const drop_str = std.fmt.allocPrint(allocator, "drop-{d}-3", .{pos}) catch unreachable;
        const processor = try processors.selectProcessor(allocator, drop_str, &.{});
        assert(processor.Dropper.drop_pos == pos);
        assert(processor.Dropper.drop_count == 3);
        allocator.free(drop_str);
    }
}

test "selectMessage returns expected strings" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cases = .{
        .{ "passthrough", "All packets were forwarded without modification\n" },
        .{ "logging", "Packet logging completed\n" },
        .{ "filtering", "Filtered packets containing pattern\n" },
        .{ "custom", "Processed packets with header manipulation\n" },
        .{ "srt-nak", "Malformed SRT NAK packets (listener → forward)\n" },
        .{ "srt-nak-bidir", "Malformed SRT NAK packets (bidirectional)\n" },
    };

    inline for (cases) |tc| {
        const processor = try processors.selectProcessor(allocator, tc[0], &.{});
        const msg = processors.selectMessage(processor);
        assert(std.mem.eql(u8, msg, tc[1]));
    }

    // drop processor message
    const drop_proc = try processors.selectProcessor(allocator, "drop-100-3", &.{});
    const msg = processors.selectMessage(drop_proc);
    assert(std.mem.eql(u8, msg, "Dropped packets around specified position\n"));
}

test "fuzz drop processor with Zig integrated fuzz" {
    const Context = struct {
        allocator: std.mem.Allocator,

        fn fuzzDropProcessor(self: *@This(), input: []const u8) anyerror!void {
            _ = self; // unused but required for signature

            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            if (input.len < 1) return;
            var str_buf: [64]u8 = undefined;
            const len = @min(input.len, str_buf.len);
            @memcpy(str_buf[0..len], input[0..len]);

            const drop_str = std.fmt.allocPrint(allocator, "drop-{s}-3", .{str_buf[0..len]}) catch return;
            defer allocator.free(drop_str);

            const parsed = std.fmt.parseInt(u32, str_buf[0..len], 10) catch return;
            const processor = try processors.selectProcessor(allocator, drop_str, &.{});

            switch (processor) {
                .Dropper => |dropper| {
                    try std.testing.expect(dropper.drop_pos == parsed);
                    try std.testing.expect(dropper.drop_count == 3);
                },
                else => return error.UnexpectedProcessorType,
            }
        }
    };

    var context = Context{ .allocator = std.testing.allocator };
    try std.testing.fuzz(&context, Context.fuzzDropProcessor, .{});
}
