const std = @import("std");

const BUFFERSIZE = 4096;

const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,
};

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
                    @compileError("PacketProcessor must have method: processListenerToForward(self: *@This(), buffer: []u8, packet: []u8) []u8");
                }
                if (!@hasDecl(ProcessorType, "processForwardToListener")) {
                    @compileError("PacketProcessor must have method: processForwardToListener(self: *@This(), buffer: []u8, packet: []u8) []u8");
                }
            }

            const listenSock = try std.posix.socket(
                std.posix.AF.INET,
                std.posix.SOCK.DGRAM,
                0,
            );
            const forwardsock = try std.posix.socket(
                std.posix.AF.INET,
                std.posix.SOCK.DGRAM,
                0,
            );

            // On error call close
            errdefer std.posix.close(listenSock);
            errdefer std.posix.close(forwardsock);

            return Self{
                .listener = Socket{
                    .address = try std.net.Address.parseIp4(listenIP, listenPort),
                    .socket = listenSock,
                },
                .forward = Socket{
                    .address = try std.net.Address.parseIp4(forwardIP, forwardPort),
                    .socket = forwardsock,
                },
                .processor = processor,
                .listen_ip = listenIP,
                .listen_port = listenPort,
            };
        }

        fn getPollFds(self: *const Self) [2]std.posix.pollfd {
            return [_]std.posix.pollfd{
                .{
                    .fd = self.listener.socket,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = self.forward.socket,
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
                std.log.warn("Not all bytes sent! Sent {d}/{d} bytes", .{sentBytes, buffer.len});
            }
        }

        // Advanced API: Bind the listener socket (must be called before poll/process)
        pub fn bind(self: *Self) !void {
            std.posix.bind(
                self.listener.socket,
                &self.listener.address.any,
                self.listener.address.getOsSockLen(),
            ) catch |err| switch (err) {
                error.AddressNotAvailable => {
                    std.log.err("Cannot bind to address {s}:{d}. The IP address is not available on this machine. Try using '0.0.0.0' or '127.0.0.1' instead.", .{ self.listen_ip, self.listen_port });
                    return err;
                },
                error.AddressInUse => {
                    std.log.err("Address {s}:{d} is already in use by another process. Try a different port or stop the conflicting process.", .{ self.listen_ip, self.listen_port });
                    return err;
                },
                error.AccessDenied => {
                    std.log.err("Permission denied when binding to {s}:{d}. Ports below 1024 require root privileges, or try a higher port number.", .{ self.listen_ip, self.listen_port });
                    return err;
                },
                else => {
                    std.log.err("Failed to bind to {s}:{d}: {}", .{ self.listen_ip, self.listen_port, err });
                    return err;
                },
            };
        }

        // Advanced API: Poll for events
        pub const PollResult = struct {
            has_events: bool,
            pollfds: [2]std.posix.pollfd,
        };

        pub fn poll(self: *Self, timeoutMs: i32) !PollResult {
            var pollfds = self.getPollFds();
            const readyCount = try std.posix.poll(&pollfds, timeoutMs);
            return PollResult{
                .has_events = readyCount > 0,
                .pollfds = pollfds,
            };
        }

        // Advanced API: Process a single event
        pub const ProcessResult = struct {
            bytes_processed: usize,
            direction: enum { ListenerToForward, ForwardToListener },
        };

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

