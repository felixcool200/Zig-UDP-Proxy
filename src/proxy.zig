const std = @import("std");

const BUFFERSIZE = 4096;

const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,
};

// Shared types used by both generic and runtime versions
pub const PollResult = struct {
    has_events: bool,
    pollfds: [2]std.posix.pollfd,
};

pub const ProcessResult = struct {
    bytes_processed: usize,
    direction: enum { ListenerToForward, ForwardToListener },
};

// Shared helper functions
fn createSockets(
    listenIP: []const u8,
    listenPort: u16,
    forwardIP: []const u8,
    forwardPort: u16,
) !struct { listener: Socket, forward: Socket } {
    const listenSock = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        0,
    );
    errdefer std.posix.close(listenSock);

    const forwardsock = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM,
        0,
    );
    errdefer std.posix.close(forwardsock);

    return .{
        .listener = Socket{
            .address = try std.net.Address.parseIp4(listenIP, listenPort),
            .socket = listenSock,
        },
        .forward = Socket{
            .address = try std.net.Address.parseIp4(forwardIP, forwardPort),
            .socket = forwardsock,
        },
    };
}

fn getPollFds(listener: Socket, forward: Socket) [2]std.posix.pollfd {
    return [_]std.posix.pollfd{
        .{
            .fd = listener.socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = forward.socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };
}

fn reciveBuffer(sock: Socket, buffer: []u8) !usize {
    return try std.posix.recv(sock.socket, buffer[0..], 0);
}

fn sendBuffer(toSock: Socket, buffer: []u8) !void {
    const sentBytes = try std.posix.sendto(
        toSock.socket,
        buffer[0..],
        0,
        &toSock.address.any,
        toSock.address.getOsSockLen(),
    );
    if (sentBytes != buffer.len) {
        std.log.warn("Not all bytes sent! Sent {d}/{d} bytes", .{ sentBytes, buffer.len });
    }
}

fn bindSocket(listener: Socket, listen_ip: []const u8, listen_port: u16) !void {
    std.posix.bind(
        listener.socket,
        &listener.address.any,
        listener.address.getOsSockLen(),
    ) catch |err| switch (err) {
        error.AddressNotAvailable => {
            std.log.err("Cannot bind to address {s}:{d}. The IP address is not available on this machine. Try using '0.0.0.0' or '127.0.0.1' instead.", .{ listen_ip, listen_port });
            return err;
        },
        error.AddressInUse => {
            std.log.err("Address {s}:{d} is already in use by another process. Try a different port or stop the conflicting process.", .{ listen_ip, listen_port });
            return err;
        },
        error.AccessDenied => {
            std.log.err("Permission denied when binding to {s}:{d}. Ports below 1024 require root privileges, or try a higher port number.", .{ listen_ip, listen_port });
            return err;
        },
        else => {
            std.log.err("Failed to bind to {s}:{d}: {}", .{ listen_ip, listen_port, err });
            return err;
        },
    };
}

pub fn ProxySocketPairGeneric(comptime PacketProcessor: type) type {
    return struct {
        const Self = @This();

        listener: Socket,
        forward: Socket,
        processor: PacketProcessor,
        listen_ip: []const u8,
        listen_port: u16,

        pub fn init(
            processor: PacketProcessor,
            listenIP: []const u8,
            listenPort: u16,
            forwardIP: []const u8,
            forwardPort: u16,
        ) !Self {
            // Verify at compile time that PacketProcessor has required methods
            comptime {
                const ProcessorType = @TypeOf(processor);
                // const info = @typeInfo(ProcessorType);

                // Check for required methods
                if (!@hasDecl(ProcessorType, "processListenerToForward")) {
                    //@compileError("PacketProcessor must have method: processListenerToForward(self: *@This(), buffer: []u8, packet: []u8) []u8");
                    @compileError("PacketProcessor missing method processListenerToForward; type: " ++ @typeName(ProcessorType));
                }
                if (!@hasDecl(ProcessorType, "processForwardToListener")) {
                    @compileError("PacketProcessor missing method processForwardToListener; type: " ++ @typeName(ProcessorType));
                    //@compileError("PacketProcessor must have method: processForwardToListener(self: *@This(), buffer: []u8, packet: []u8) []u8");
                }
            }

            const sockets = try createSockets(listenIP, listenPort, forwardIP, forwardPort);
            return Self{
                .listener = sockets.listener,
                .forward = sockets.forward,
                .processor = processor,
                .listen_ip = listenIP,
                .listen_port = listenPort,
            };
        }

        // Advanced API: Bind the listener socket (must be called before poll/process)
        pub fn bind(self: *Self) !void {
            try bindSocket(self.listener, self.listen_ip, self.listen_port);
        }

        // Advanced API: Poll for events
        pub fn poll(self: *Self, timeoutMs: i32) !PollResult {
            var pollfds = getPollFds(self.listener, self.forward);
            const readyCount = try std.posix.poll(&pollfds, timeoutMs);
            return PollResult{
                .has_events = readyCount > 0,
                .pollfds = pollfds,
            };
        }

        // Advanced API: Process a single event

        pub fn processEvent(self: *Self, pollfd: std.posix.pollfd, buffer: []u8) !?ProcessResult {
            if ((pollfd.revents & std.posix.POLL.IN) == 0) {
                return null;
            }

            // Define direction
            const condition = (pollfd.fd == self.listener.socket);
            const from = if (condition) self.listener else self.forward;
            const to = if (!condition) self.forward else self.listener;

            // Read, process and send packet
            const receivedBytes: usize = try reciveBuffer(from, buffer);

            // Call appropriate processor method based on direction
            const processedPacket: []u8 = if (condition)
                self.processor.processListenerToForward(buffer, buffer[0..receivedBytes])
            else
                self.processor.processForwardToListener(buffer, buffer[0..receivedBytes]);

            if (processedPacket.len > 0) {
                try sendBuffer(to, processedPacket);
            }

            return ProcessResult{
                .bytes_processed = processedPacket.len,
                .direction = if (condition) .ListenerToForward else .ForwardToListener,
            };
        }

        // Simple API: Run the proxy with built-in event loop
        pub fn start(self: *Self, timeoutMs: i32) !void {
            try self.bind();

            var buffer: [BUFFERSIZE]u8 = undefined;
            std.log.info("Starting proxy loop", .{});

            // Main proxy loop
            while (true) {
                const poll_result = try self.poll(timeoutMs);

                // Break on no use
                if (!poll_result.has_events) {
                    std.log.info(
                        "No packets received in {d:.1}s, exiting",
                        .{@as(f32, @floatFromInt(timeoutMs)) / 1000},
                    );
                    return;
                }

                // Process each ready socket
                for (poll_result.pollfds) |fd| {
                    _ = try self.processEvent(fd, &buffer);
                }
            }
        }

        pub fn deinit(self: *Self) void {
            std.posix.close(self.listener.socket);
            std.posix.close(self.forward.socket);
        }
    };
}

const processors = @import("processors.zig");

// Runtime version that works with the Processor tagged union
pub const ProxySocketPairRuntime = struct {
    const Self = @This();

    listener: Socket,
    forward: Socket,
    processor: *processors.Processor,
    listen_ip: []const u8,
    listen_port: u16,

    pub fn init(
        processor: *processors.Processor,
        listenIP: []const u8,
        listenPort: u16,
        forwardIP: []const u8,
        forwardPort: u16,
    ) !Self {
        const sockets = try createSockets(listenIP, listenPort, forwardIP, forwardPort);
        return Self{
            .listener = sockets.listener,
            .forward = sockets.forward,
            .processor = processor,
            .listen_ip = listenIP,
            .listen_port = listenPort,
        };
    }

    // Advanced API: Bind the listener socket
    pub fn bind(self: *Self) !void {
        try bindSocket(self.listener, self.listen_ip, self.listen_port);
    }

    // Advanced API: Poll for events
    pub fn poll(self: *Self, timeoutMs: i32) !PollResult {
        var pollfds = getPollFds(self.listener, self.forward);
        const readyCount = try std.posix.poll(&pollfds, timeoutMs);
        return PollResult{
            .has_events = readyCount > 0,
            .pollfds = pollfds,
        };
    }

    // Advanced API: Process a single event with runtime dispatch
    pub fn processEvent(self: *Self, pollfd: std.posix.pollfd, buffer: []u8) !?ProcessResult {
        if ((pollfd.revents & std.posix.POLL.IN) == 0) {
            return null;
        }

        // Define direction
        const condition = (pollfd.fd == self.listener.socket);
        const from = if (condition) self.listener else self.forward;
        const to = if (!condition) self.forward else self.listener;

        // Read packet
        const receivedBytes: usize = try reciveBuffer(from, buffer);

        // Runtime dispatch based on processor variant
        const processedPacket: []u8 = switch (self.processor.*) {
            inline else => |*p| if (condition)
                p.processListenerToForward(buffer, buffer[0..receivedBytes])
            else
                p.processForwardToListener(buffer, buffer[0..receivedBytes]),
        };

        if (processedPacket.len > 0) {
            try sendBuffer(to, processedPacket);
        }

        return ProcessResult{
            .bytes_processed = processedPacket.len,
            .direction = if (condition) .ListenerToForward else .ForwardToListener,
        };
    }

    // Simple API: Run the proxy with built-in event loop
    pub fn start(self: *Self, timeoutMs: i32) !void {
        try self.bind();

        var buffer: [BUFFERSIZE]u8 = undefined;
        std.log.info("Starting proxy loop", .{});

        // Main proxy loop
        while (true) {
            const poll_result = try self.poll(timeoutMs);

            // Break on no use
            if (!poll_result.has_events) {
                std.log.info(
                    "No packets received in {d:.1}s, exiting",
                    .{@as(f32, @floatFromInt(timeoutMs)) / 1000},
                );
                return;
            }

            // Process each ready socket
            for (poll_result.pollfds) |fd| {
                _ = try self.processEvent(fd, &buffer);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        std.posix.close(self.listener.socket);
        std.posix.close(self.forward.socket);
    }
};

// Re-export common processors for convenience
pub const PassThroughProcessor = processors.PassThroughProcessor;
pub const LoggingProcessor = processors.LoggingProcessor;
pub const FilteringProcessor = processors.FilteringProcessor;

// Helper function to create a proxy with default pass-through behavior
pub fn createDefaultProxy(
    listenIP: []const u8,
    listenPort: u16,
    forwardIP: []const u8,
    forwardPort: u16,
) !ProxySocketPairGeneric(PassThroughProcessor) {
    const processor = PassThroughProcessor{};
    return ProxySocketPairGeneric(PassThroughProcessor).init(
        processor,
        listenIP,
        listenPort,
        forwardIP,
        forwardPort,
    );
}

// Helper function to create a runtime proxy with a processor union
pub fn createRuntimeProxy(
    processor: *processors.Processor,
    listenIP: []const u8,
    listenPort: u16,
    forwardIP: []const u8,
    forwardPort: u16,
) !ProxySocketPairRuntime {
    return ProxySocketPairRuntime.init(
        processor,
        listenIP,
        listenPort,
        forwardIP,
        forwardPort,
    );
}
