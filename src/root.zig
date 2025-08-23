const std = @import("std");

// Export the main proxy functionality
pub const proxy = @import("proxy.zig");
pub const ProxySocketPairGeneric = proxy.ProxySocketPairGeneric;

// Export all processors
pub const processors = @import("processors.zig");
pub const PassThroughProcessor = processors.PassThroughProcessor;
pub const LoggingProcessor = processors.LoggingProcessor;
pub const FilteringProcessor = processors.FilteringProcessor;
pub const CustomProcessor = processors.CustomProcessor;

// Export SRT processors
pub const SRTNakMalformerProcessor = processors.SRTNakMalformerProcessor;
pub const BidirectionalSRTNakMalformerProcessor = processors.BidirectionalSRTNakMalformerProcessor;
pub const PacketDropperProcessor = processors.PacketDropperProcessor;

// Re-export the helper function
pub const createDefaultProxy = proxy.createDefaultProxy;

test {
    // Run all tests when testing the library
    std.testing.refAllDecls(@This());
}