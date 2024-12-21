const std = @import("std");

pub const CBFunction: type = *const fn ([]u8, usize) usize;
const BUFFERSIZE = 4096;

const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,
    processPacketCallback: CBFunction,
};

pub const ProxySocketPair = struct {
    listener: Socket,
    forward: Socket,

    pub fn init(listenIP: []const u8, listenPort: u16, forwardIP: []const u8, forwardPort: u16) !ProxySocketPair {
        initWithCB(listenIP, listenPort, forwardIP, forwardPort, &defaultProcessPacketFunction, &defaultProcessPacketFunction);
    }

    pub fn initWithCB(
        listenIP: []const u8,
        listenPort: u16,
        forwardIP: []const u8,
        forwardPort: u16,
        processPacketFuncListenerToForward: CBFunction,
        processPacketFuncForwardToListener: CBFunction,
    ) !ProxySocketPair {
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

        //On error call close
        errdefer std.posix.close(listenSock);
        errdefer std.posix.close(forwardsock);

        return ProxySocketPair{
            .listener = Socket{
                .address = try std.net.Address.parseIp4(listenIP, listenPort),
                .socket = listenSock,
                .processPacketCallback = processPacketFuncListenerToForward,
            },
            .forward = Socket{
                .address = try std.net.Address.parseIp4(forwardIP, forwardPort),
                .socket = forwardsock,
                .processPacketCallback = processPacketFuncForwardToListener,
            },
        };
    }

    fn defaultProcessPacketFunction(_: []u8, dataLen: usize) usize {
        return dataLen;
    }

    fn getPollFds(self: *const ProxySocketPair) [2]std.posix.pollfd {
        return [_]std.posix.pollfd{
            .{
                .fd = self.listener.socket,
                .events = std.posix.POLL.IN,
                .revents = 0, // Is filled in by poll function
            },
            .{
                .fd = self.forward.socket,
                .events = std.posix.POLL.IN,
                .revents = 0, // Is filled in by poll function
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
            std.debug.print("WARNING: Not all bytes sent!", .{});
        }
    }

    pub fn start(self: *const ProxySocketPair, timeoutMs: i32) !void {

        //Bind to listener
        try std.posix.bind(
            self.listener.socket,
            &self.listener.address.any,
            self.listener.address.getOsSockLen(),
        );

        //File descriptors to enable polling
        var pollfds = self.getPollFds();
        // Wait for events with a 5-second timeout
        var buffer: [BUFFERSIZE]u8 = undefined;
        std.debug.print("Starting proxy loop\n", .{});

        //Main proxy loop
        while (true) {
            const readyCount: usize = try std.posix.poll(&pollfds, timeoutMs);

            //Break on no use
            if (readyCount == 0) {
                std.debug.print(
                    "No packets recived in {d}s, exiting\n",
                    .{@as(f32, @floatFromInt(timeoutMs)) / 1000},
                );
                return;
            }

            // Check which socket has data ready
            for (pollfds) |fd| {
                if ((fd.revents & std.posix.POLL.IN) != 0) {
                    //std.debug.print("Socket {d} is ready for reading\n", .{fd.fd});

                    // Define direction
                    const condition = (fd.fd == self.listener.socket);
                    const from = if (condition) self.listener else self.forward;
                    const to = if (!condition) self.forward else self.listener;

                    //Read process and send packet
                    const receivedBytes: usize = try reciveBuffer(from, buffer[0..]);
                    const processedBytes: usize = from.processPacketCallback(buffer[0..], receivedBytes);
                    if (processedBytes > 0) {
                        try sendBuffer(to, buffer[0..processedBytes]);
                    }
                }
            }
        }
    }
};
