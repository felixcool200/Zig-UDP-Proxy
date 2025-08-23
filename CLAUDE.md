# UDP Proxy Library - Architecture Documentation

## Overview

The UDP Proxy Library is a high-performance networking library written in Zig that provides flexible UDP packet forwarding capabilities with custom processing. The architecture emphasizes zero-cost abstractions, compile-time safety, and multiple usage patterns to support everything from simple proxy applications to complex network processing systems.

## Core Architecture Principles

### 1. Zero-Cost Abstractions
- **Compile-time duck typing**: Interface compliance verified at compile time
- **No runtime overhead**: Direct method calls instead of function pointers
- **Stack allocation**: Minimal heap usage for performance-critical paths
- **Monomorphization**: Each processor type generates specialized code

### 2. Type Safety
- **Compile-time interface verification**: Processors must implement required methods
- **Strong typing**: No void pointers or unsafe casts in the core API
- **Memory safety**: Leverages Zig's built-in memory safety guarantees

### 3. Flexibility
- **Multiple API levels**: Simple, Advanced, and Legacy interfaces
- **Pluggable processors**: Easy to create custom packet processing logic
- **Library and executable**: Can be used as both library and standalone tools

## Type System Architecture

### Generic Proxy Type

```zig
pub fn ProxySocketPairGeneric(comptime PacketProcessor: type) type {
    return struct {
        const Self = @This();
        
        listener: Socket,
        forward: Socket,  
        processor: PacketProcessor,
        
        // Methods...
    };
}
```

**Key Design Decisions:**
- **Compile-time parameterization**: Each processor type creates a unique proxy type
- **Value semantics**: Processor is stored by value, not reference
- **Interface verification**: Uses `@hasDecl()` to verify required methods at compile time

### Processor Interface Contract

Every processor must implement:

```zig
pub fn processListenerToForward(self: *@This(), buffer: []u8, packet: []u8) []u8
pub fn processForwardToListener(self: *@This(), buffer: []u8, packet: []u8) []u8
```

**Interface Characteristics:**
- **Duck typing**: No explicit interface declaration required
- **Mutable access**: Processors can maintain state between calls
- **Slice-based processing**: Operates on packet slices within buffer space
- **Flexible sizing**: Return slice controls packet size and content (empty slice = drop)
- **Zero-copy operations**: All data manipulation works with slices, no copying required

**Parameters:**
- **`buffer`**: Full buffer space available for packet expansion/manipulation
- **`packet`**: Current packet data slice within the buffer

**Return Value:**
- **Slice of processed data**: Can be same, smaller, or larger than input packet
- **Empty slice** (`packet[0..0]`): Drops the packet 
- **Expanded slice**: Can use buffer space beyond packet for adding headers/data
- **Contracted slice**: Can return subset of packet (e.g., `packet[4..]` removes 4-byte header)

## API Layer Architecture

### 1. Simple API
```zig
try proxy.start(timeout_ms);
```

**Purpose**: Easy-to-use interface for common use cases
**Characteristics**:
- Built-in event loop
- Automatic socket management
- Basic timeout handling
- Minimal configuration required

### 2. Advanced API
```zig
try proxy.bind();
const poll_result = try proxy.poll(timeout_ms);
for (poll_result.pollfds) |fd| {
    _ = try proxy.processEvent(fd, &buffer);
}
```

**Purpose**: Fine-grained control for integration with existing event loops
**Characteristics**:
- Manual event loop control
- Custom polling intervals
- Per-event processing
- Integration with other I/O operations

### 3. Legacy API
```zig
const proxy = try ProxySocketPair.initWithCB(
    listen_ip, listen_port, forward_ip, forward_port,
    callback_func, callback_func
);
```

**Purpose**: Backward compatibility with function pointer-based design
**Characteristics**:
- Function pointer callbacks
- Runtime dispatch
- Compatible with existing code

## Network Architecture

### Socket Management

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────┐
│   Client    │◄──►│   Proxy Server   │◄──►│   Target    │
│             │    │                  │    │   Server    │
│ 192.168.1.5 │    │ Listener: :8080  │    │ 10.0.0.100  │
│             │    │ Forward:  :9090  │    │             │
└─────────────┘    └──────────────────┘    └─────────────┘
```

**Data Flow:**
1. **Client → Proxy**: Packets received on listener socket
2. **Processor**: `processListenerToForward()` called
3. **Proxy → Target**: Modified packets sent to forward socket
4. **Target → Proxy**: Response packets received on forward socket  
5. **Processor**: `processForwardToListener()` called
6. **Proxy → Client**: Modified responses sent back to original client

### Polling Architecture

Uses `poll()` system call for efficient I/O multiplexing:

```zig
const PollResult = struct {
    has_events: bool,
    pollfds: [2]std.posix.pollfd,
};
```

**Benefits:**
- **Efficient**: Only blocks when no data is available
- **Scalable**: Handles multiple sockets with single thread
- **Timeout support**: Configurable timeouts for different use cases
- **Cross-platform**: Uses platform-specific optimal polling mechanisms

## Memory Architecture

### Buffer Management

```zig
const BUFFERSIZE = 4096;
var buffer: [BUFFERSIZE]u8 = undefined;
```

**Strategy:**
- **Stack allocation**: Buffers allocated on stack for performance
- **Fixed size**: 4KB buffers accommodate most UDP packets
- **Reuse**: Single buffer reused for all packet processing
- **No copying**: In-place modification reduces memory allocations

### State Management

**Processor State:**
- Stored by value in proxy instance
- Can maintain counters, statistics, configuration
- Accessed via mutable pointer during processing

**Socket State:**
- File descriptors managed automatically
- Address information cached at initialization
- Proper cleanup via RAII patterns

## Error Handling Architecture

### Zig Error Model Integration

```zig
pub fn processEvent(self: *Self, pollfd: std.posix.pollfd, buffer: []u8) !?ProcessResult
```

**Error Categories:**
- **System errors**: Socket operations, network failures
- **Timeout errors**: No data available within timeout period
- **Configuration errors**: Invalid addresses, ports, etc.

**Error Propagation:**
- Errors bubble up through call stack
- Cleanup handled via `defer` and `errdefer`
- Resource leaks prevented by automatic cleanup

## Processor Architecture

### Built-in Processors

The processor architecture is organized into modular files for maintainability:

```
src/processors/
├── pass_through.zig         # Basic forwarding
├── logging.zig              # Packet logging
├── filtering.zig            # Pattern filtering  
├── custom.zig              # Header manipulation
├── srt_nak_malformer.zig   # SRT protocol NAK malforming
├── srt_nak_malformer_bidirectional.zig
└── packet_dropper.zig      # Configurable packet dropping
```

#### Basic Processors

**PassThroughProcessor** (`processors/pass_through.zig`)
- **Stateless**: No internal state required
- **Zero overhead**: Compiles to simple pass-through
- **Default behavior**: Forwards all packets unchanged

**LoggingProcessor** (`processors/logging.zig`)
- **Stateful**: Maintains logging configuration
- **Resource management**: Handles file operations
- **Debug tool**: Useful for development and troubleshooting

**FilteringProcessor** (`processors/filtering.zig`)
- **Pattern matching**: Uses string search for packet content
- **Configuration**: Pattern specified at initialization
- **Selective dropping**: Only affects matching packets

**CustomProcessor** (`processors/custom.zig`)
- **Header manipulation**: Adds "FWD:" headers going forward
- **Statistics tracking**: Counts processed packets
- **Bidirectional processing**: Different logic for each direction

#### SRT Protocol Processors

**SRTNakMalformerProcessor** (`processors/srt_nak_malformer.zig`)
- **Protocol-specific**: Understands SRT NAK packet structure
- **Precise targeting**: Only affects specific packet types (24-byte NAK packets)
- **Statistics tracking**: Counts malformed packets
- **Unidirectional**: Only processes listener-to-forward direction

**BidirectionalSRTNakMalformerProcessor** (`processors/srt_nak_malformer_bidirectional.zig`)
- **Bidirectional processing**: Malforms NAK packets in both directions
- **Separate statistics**: Tracks counts for each direction
- **Shared logic**: Common malformation function used by both directions

**PacketDropperProcessor** (`processors/packet_dropper.zig`)
- **Compile-time configuration**: Drop point specified at compile time
- **Generic type**: `PacketDropperProcessor(comptime packet_limit: comptime_int)`
- **Stateful counting**: Tracks packet numbers
- **Precise timing**: Drops exactly 3 packets at specified position

## Build System Architecture

### Multi-target Build Strategy

```
src/
├── root.zig              # Library entry point
├── proxy.zig             # Core generic implementation
├── processors.zig       # Processor index/exports
├── processors/           # Individual processor modules
│   ├── pass_through.zig
│   ├── logging.zig
│   ├── filtering.zig
│   ├── custom.zig
│   ├── srt_nak_malformer.zig
│   ├── srt_nak_malformer_bidirectional.zig
│   └── packet_dropper.zig
├── main.zig             # Unified proxy executable with processor selection
├── proxy_test.zig        # Integration tests
└── test_utils.zig       # Test utilities

Build Targets:
├── libud-proxy.a          # Static library
├── libud-proxy.so         # Shared library
├── UDP-Proxy              # Unified executable (all processor types)
└── library-usage-example  # Usage examples
```

### Module System

**Library exports** (src/root.zig):
```zig
pub const ProxySocketPairGeneric = proxy.ProxySocketPairGeneric;

// Export all processors
pub const processors = @import("processors.zig");
pub const PassThroughProcessor = processors.PassThroughProcessor;
pub const LoggingProcessor = processors.LoggingProcessor;
pub const CustomProcessor = processors.CustomProcessor;
pub const SRTNakMalformerProcessor = processors.SRTNakMalformerProcessor;
// ... etc
```

**Processor index** (src/processors.zig):
```zig
// Export all processors from their individual files
pub const PassThroughProcessor = @import("processors/pass_through.zig").PassThroughProcessor;
pub const LoggingProcessor = @import("processors/logging.zig").LoggingProcessor;
pub const FilteringProcessor = @import("processors/filtering.zig").FilteringProcessor;
// ... etc
```

**Benefits:**
- **Clean API surface**: Only essential types exported
- **Backward compatibility**: Legacy API still available
- **Modular design**: Users can import specific components

## Performance Architecture

### Optimization Strategies

1. **Compile-time specialization**: Each processor type generates optimized code
2. **Minimal allocations**: Stack-based buffers, no dynamic allocation in hot path
3. **Direct calls**: No virtual dispatch or function pointer overhead
4. **Efficient I/O**: Uses optimal polling mechanisms for platform
5. **Cache-friendly**: Small, predictable memory access patterns

### Benchmarking Considerations

**Key Metrics:**
- **Throughput**: Packets per second under sustained load
- **Latency**: Time from packet receipt to forwarding
- **Memory usage**: RSS and heap allocation patterns
- **CPU utilization**: Percentage of CPU time used per packet

**Typical Performance Characteristics:**
- Sub-microsecond processing latency for simple processors
- Millions of packets per second throughput on modern hardware
- Constant memory usage regardless of traffic volume
- Linear scaling with number of active connections

## Testing Architecture

### Test Categories

1. **Unit tests**: Individual processor functionality
2. **Integration tests**: Full proxy operation
3. **Protocol tests**: SRT-specific functionality
4. **Performance tests**: Benchmarking and profiling

### Test Structure
```
tests/
├── unit/
│   ├── processors_test.zig
│   ├── networking_test.zig
│   └── api_test.zig
├── integration/
│   ├── proxy_test.zig
│   └── srt_test.zig
└── benchmarks/
    ├── throughput_test.zig
    └── latency_test.zig
```

## Thread Safety Architecture

### Current Model: Single-threaded
- **Simplicity**: No locking or synchronization required
- **Performance**: No contention or cache coherence issues
- **Predictability**: Deterministic execution order

### Future Multi-threading Considerations
- **Per-connection threads**: Each proxy instance in separate thread
- **Worker pool**: Multiple threads sharing work queue
- **Lock-free processors**: Using atomic operations for shared state

## Extensibility Architecture

### Plugin System Design

Future extension points:
1. **Dynamic loading**: Runtime processor loading
2. **Scripting integration**: Lua/WASM processors
3. **Network protocols**: TCP, SCTP support
4. **Monitoring**: Metrics collection and reporting

### API Stability
- **Core interfaces**: Guaranteed stable across minor versions
- **Processor interface**: Backward compatible extensions only
- **Build system**: Semantic versioning for breaking changes

## Security Architecture

### Memory Safety
- **Zig guarantees**: Buffer overflow protection, null pointer safety
- **Bounds checking**: All array accesses verified
- **Resource management**: Automatic cleanup prevents leaks

### Network Security
- **Input validation**: Packet size and format verification  
- **Address validation**: IP address and port range checking
- **Rate limiting**: Processor-level packet rate controls

### Attack Surface Analysis
- **Minimal dependencies**: Reduces external vulnerability exposure
- **Simple protocol handling**: Less complex parsing code
- **Stateless design**: Reduces state-based attack vectors

---

This architecture enables the UDP Proxy Library to provide high performance, type safety, and flexibility while maintaining simplicity and ease of use. The design scales from simple packet forwarding to complex protocol processing with minimal overhead and maximum reliability.