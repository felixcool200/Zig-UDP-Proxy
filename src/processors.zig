const std = @import("std");

// Export all processors from their individual files
pub const PassThroughProcessor = @import("processors/pass_through.zig").PassThroughProcessor;
pub const LoggingProcessor = @import("processors/logging.zig").LoggingProcessor;
pub const FilteringProcessor = @import("processors/filtering.zig").FilteringProcessor;
pub const CustomProcessor = @import("processors/custom.zig").CustomProcessor;

// SRT processors
pub const SRTNakMalformerProcessor = @import("processors/srt_nak_malformer.zig").SRTNakMalformerProcessor;
pub const BidirectionalSRTNakMalformerProcessor = @import("processors/srt_nak_malformer_bidirectional.zig").BidirectionalSRTNakMalformerProcessor;
pub const PacketDropperProcessor = @import("processors/packet_dropper.zig").PacketDropperProcessor;

pub const Processor = union(enum) {
    PassThrough: PassThroughProcessor,
    Logging: LoggingProcessor,
    Filtering: FilteringProcessor,
    Custom: CustomProcessor,
    SRTNak: SRTNakMalformerProcessor,
    SRTNakBidir: BidirectionalSRTNakMalformerProcessor,
    Dropper: PacketDropperProcessor,
};

pub const ProcessorSelectionError = error{
    InvalidProcessor,
    InvalidDropPosition,
    InvalidDropCount,
};

pub fn selectProcessor(
    allocator: std.mem.Allocator,
    processor_type: []const u8,
    args: [][]const u8,
) !Processor {
    return blk: {
        if (std.mem.eql(u8, processor_type, "passthrough")) {
            break :blk Processor{ .PassThrough = PassThroughProcessor{} };
        } else if (std.mem.eql(u8, processor_type, "logging")) {
            break :blk Processor{ .Logging = LoggingProcessor.init(allocator) };
        } else if (std.mem.eql(u8, processor_type, "filtering")) {
            const pattern = if (args.len > 6) args[6] else "DROP";
            break :blk Processor{ .Filtering = FilteringProcessor.init(pattern) };
        } else if (std.mem.eql(u8, processor_type, "custom")) {
            break :blk Processor{ .Custom = CustomProcessor.init() };
        } else if (std.mem.eql(u8, processor_type, "srt-nak")) {
            break :blk Processor{ .SRTNak = SRTNakMalformerProcessor.init() };
        } else if (std.mem.eql(u8, processor_type, "srt-nak-bidir")) {
            break :blk Processor{ .SRTNakBidir = BidirectionalSRTNakMalformerProcessor.init() };
        } else if (std.mem.startsWith(u8, processor_type, "drop-")) {
            var it = std.mem.splitAny(u8, processor_type, "-");
            _ = it.next(); // skip the "drop" prefix

            const pos_slice = it.next() orelse return ProcessorSelectionError.InvalidDropPosition;
            const drop_pos = std.fmt.parseInt(u32, pos_slice, 10) catch return ProcessorSelectionError.InvalidDropPosition;

            const count_slice = it.next() orelse return ProcessorSelectionError.InvalidDropCount;
            const drop_count = std.fmt.parseInt(u32, count_slice, 10) catch return ProcessorSelectionError.InvalidDropCount;

            break :blk Processor{ .Dropper = PacketDropperProcessor.init(drop_pos, drop_count) };
        } else {
            return ProcessorSelectionError.InvalidProcessor;
        }
    };
}

// ------------------------- Message selection -------------------------
pub fn selectMessage(processor: Processor) []const u8 {
    return switch (processor) {
        .PassThrough => "All packets were forwarded without modification\n",
        .Logging => "Packet logging completed\n",
        .Filtering => "Filtered packets containing pattern\n",
        .Custom => "Processed packets with header manipulation\n",
        .SRTNak => "Malformed SRT NAK packets (listener → forward)\n",
        .SRTNakBidir => "Malformed SRT NAK packets (bidirectional)\n",
        .Dropper => "Dropped packets around specified position\n",
    };
}

// ------------------------- Proxy pointer extraction -------------------------
fn getProcessorPointer(processor: Processor) *anyopaque {
    return switch (processor) {
        .PassThrough => &processor.PassThrough,
        .Logging => &processor.Logging,
        .Filtering => &processor.Filtering,
        .Custom => &processor.Custom,
        .SRTNak => &processor.SRTNak,
        .SRTNakBidir => &processor.SRTNakBidir,
        .Dropper => &processor.Dropper.proc,
    };
}

test {
    // Run all processor tests
    std.testing.refAllDecls(@This());
}

const processors_test = @import("processors_test.zig");
