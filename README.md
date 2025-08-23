# UDP Proxy in Zig

A UDP packet forwarding library and utilities written in Zig. Supports custom packet processing through compile-time interfaces.

## Features

- UDP packet forwarding between two endpoints
- Compile-time duck-typed packet processors
- Simple and advanced APIs for different use cases
- Built-in processors for common tasks (logging, filtering, SRT protocol)
- Library and executable builds

## Installation

Requires Zig 0.14+.

```bash
git clone <repository-url>
cd zig-udp-proxy
zig build
```

## Usage

### As a Library

Basic proxy with custom processing:

```zig
const std = @import("std");
const udp_proxy = @import("udp-proxy");

const MyProcessor = struct {
    pub fn processListenerToForward(self: *@This(), buffer: []u8, packet: []u8) []u8 {
        // Modify packet in-place, return slice of processed data
        // Return packet[0..0] to drop packet
        return packet; // Forward unchanged
    }
    
    pub fn processForwardToListener(self: *@This(), buffer: []u8, packet: []u8) []u8 {
        // Can expand packet using buffer space if needed
        return packet;
    }
};

pub fn main() !void {
    var processor = MyProcessor{};
    var proxy = try udp_proxy.ProxySocketPairGeneric(MyProcessor).init(
        processor, "127.0.0.1", 8080, "192.168.1.100", 9090
    );
    defer proxy.deinit();
    
    try proxy.start(5000); // Simple API
}
```

Advanced API for custom event loops:

```zig
try proxy.bind();
var buffer: [4096]u8 = undefined;

while (condition) {
    const poll_result = try proxy.poll(timeout_ms);
    if (!poll_result.has_events) continue;
    
    for (poll_result.pollfds) |fd| {
        _ = try proxy.processEvent(fd, &buffer);
    }
}
```

### Built-in Processors

#### Basic Processors
```zig
// Pass-through (no processing)
var processor = udp_proxy.PassThroughProcessor{};

// Logging with packet information
var processor = udp_proxy.LoggingProcessor.init(allocator);

// Pattern-based filtering
var processor = udp_proxy.FilteringProcessor.init("DROP");

// Custom header manipulation
var processor = udp_proxy.CustomProcessor.init();
```

#### SRT Protocol Processors
```zig
// SRT NAK packet malforming (unidirectional)
var processor = udp_proxy.SRTNakMalformerProcessor.init();

// SRT NAK packet malforming (bidirectional)
var processor = udp_proxy.BidirectionalSRTNakMalformerProcessor.init();

// Packet dropping at specific positions
const DropperType = udp_proxy.PacketDropperProcessor(100);
var processor = DropperType.init();
```

### Command Line Tool

```bash
# Unified proxy executable with processor selection
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 [processor_type] [args...]

# Available processor types:
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 passthrough     # Default
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 logging         # Log packets
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 filtering SPAM  # Filter pattern
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 custom          # Header manipulation
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 srt-nak         # SRT NAK malforming
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 srt-nak-bidir   # Bidirectional SRT
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 drop-100        # Drop packets 99-101
./UDP-Proxy 127.0.0.1 8080 192.168.1.100 9090 drop-1000       # Drop packets 999-1001
```

## Processor Interface

Processors must implement these methods:

```zig
pub fn processListenerToForward(self: *@This(), buffer: []u8, packet: []u8) []u8;
pub fn processForwardToListener(self: *@This(), buffer: []u8, packet: []u8) []u8;
```

**Parameters:**
- `buffer`: Full buffer space available for packet expansion
- `packet`: Current packet data slice within the buffer  

**Return Value:**
- Return a slice of the processed packet data
- Return `packet[0..0]` (empty slice) to drop the packet
- Can return slices larger than input if expanding using buffer space
- Can return slices smaller than input for packet trimming (e.g. `packet[4..]` to remove header)

**Key Features:**
- **Zero-copy**: All operations work with slices, no data copying required
- **Flexible sizing**: Can shrink, expand (within buffer limits), or drop packets
- **Type safety**: Return slice length automatically matches processed data size
- **Compile-time verification**: Interface compliance verified at compile time

## Build Targets

- `libud-proxy.a` / `libud-proxy.so` - Static/shared libraries
- `UDP-Proxy` - Unified executable with all processor types
- `library-usage-example` - Usage examples

## Examples

The `examples/` directory demonstrates various usage patterns:

```bash
# Simple API with statistics tracking
./library-usage-example simple 127.0.0.1 8080 192.168.1.100 9090

# Advanced API with custom event loop  
./library-usage-example advanced 127.0.0.1 8080 192.168.1.100 9090

# Demonstration of all built-in processors
./library-usage-example builtin 127.0.0.1 8080 192.168.1.100 9090
```

## Testing

```bash
zig build test
```

## Architecture

- **Generic Types**: `ProxySocketPairGeneric(comptime PacketProcessor: type)`
- **Compile-time Interface Checking**: Uses `@hasDecl()` for duck typing
- **Memory Management**: Stack-allocated buffers, RAII cleanup
- **I/O**: `poll()`-based event loop with configurable timeouts

See `CLAUDE.md` for detailed architecture documentation.

## License

MIT License