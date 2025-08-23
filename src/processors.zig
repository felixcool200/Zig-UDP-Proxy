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

test {
    // Run all processor tests
    std.testing.refAllDecls(@This());
}