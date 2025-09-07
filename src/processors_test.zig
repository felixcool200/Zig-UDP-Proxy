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

    for (basic_cases) |tc| {
        const processor = try processors.selectProcessor(allocator, tc[0], .{});
        try assert(@typeInfo(processor) == @typeInfo(tc[1]));
    }
}

test "selectProcessor - drop processors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const drop_cases = .{ 1, 100, 500, 1234, 10000 };

    for (drop_cases) |pos| {
        const drop_str = std.fmt.allocPrint(allocator, "drop-{d}-3", .{pos}) catch unreachable;
        const processor = try processors.selectProcessor(allocator, drop_str, .{});
        try assert(processor.Dropper.packet_limit == pos);
        try assert(processor.Dropper.drop_count == 3);
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

    for (cases) |tc| {
        const processor = try processors.selectProcessor(allocator, tc[0], .{});
        const msg = processors.selectMessage(processor);
        try assert(std.mem.eql(u8, msg, tc[1]));
    }

    // drop processor message
    const drop_proc = try processors.selectProcessor(allocator, "drop-100-3", .{});
    const msg = processors.selectMessage(drop_proc);
    try assert(std.mem.eql(u8, msg, "Dropped packets around specified position\n"));
}

test "getProcessorPointer returns valid pointers" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const processor_strings = .{
        "passthrough",
        "logging",
        "filtering",
        "custom",
        "srt-nak",
        "srt-nak-bidir",
        "drop-123-5",
    };

    for (processor_strings) |proc_str| {
        const processor = try processors.selectProcessor(allocator, proc_str, .{});
        const ptr = processors.getProcessorPointer(processor);
        try assert(ptr != null);
    }
}

test "fuzz drop processor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const rng = std.rand.DefaultPrng.init(12345); // deterministic seed for fuzz
    const iterations = 1000;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const drop_pos = rng.random() % 10000 + 1; // 1..10000
        const drop_str = std.fmt.allocPrint(allocator, "drop-{d}-3", .{drop_pos}) catch unreachable;
        const processor = try processors.selectProcessor(allocator, drop_str, .{});
        try assert(processor.Dropper.packet_limit == drop_pos);
        try assert(processor.Dropper.drop_count == 3);
        allocator.free(drop_str);
    }
}

test "fuzz drop processor with Zig integrated fuzz" {
    const global = struct {
        fn fuzzDropProcessor(input: []const u8) anyerror!void {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            if (input.len < 1) return;
            var str_buf: [64]u8 = undefined;
            const len = std.mem.copy(u8, &str_buf, input);
            const drop_str = std.fmt.allocPrint(allocator, "drop-{s}-3", .{str_buf[0..len]}) catch return;

            const parsed = std.fmt.parseInt(u32, drop_str[5 .. len + 5], 10) catch return;
            const processor = try processors.selectProcessor(allocator, drop_str, .{});
            try std.testing.expect(processor.Dropper.packet_limit == parsed);
            try std.testing.expect(processor.Dropper.drop_count == 3);

            allocator.free(drop_str);
        }
    };

    try std.testing.fuzz(global.fuzzDropProcessor, .{});
}

