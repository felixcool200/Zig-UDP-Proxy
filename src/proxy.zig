const std = @import("std");
//const testing = std.testing;
//
//export fn add(a: i32, b: i32) i32 {
//    return a + b;
//}
//
//test "basic add functionality" {
//    try testing.expect(add(3, 7) == 10);
//}
//
//test "adding negative numbers" {
//    try testing.expect(add(-100, -51) == -151);
//}

const READ_BUF_SIZE = 4096;

const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,
    processPacketCallback: *const fn ([]u8, usize) usize,
};

pub const ProxySocketPair = struct {
    listener: Socket,
    forward: Socket,

    pub fn init(listen_ip: []const u8, listen_port: u16, forward_ip: []const u8, forward_port: u16) !ProxySocketPair {
        initWithCB(listen_ip, listen_port, forward_ip, forward_port, &defaultProcessPacketFunction, &defaultProcessPacketFunction);
    }

    pub fn initWithCB(listen_ip: []const u8, listen_port: u16, forward_ip: []const u8, forward_port: u16, processPacketFuncListenerToForward: *const fn ([]u8, usize) usize, processPacketFuncForwardToListener: *const fn ([]u8, usize) usize) !ProxySocketPair {
        const listenSock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
        const forwardsock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);

        //On error call close
        errdefer std.posix.close(listenSock);
        errdefer std.posix.close(forwardsock);

        return ProxySocketPair{
            .listener = Socket{
                .address = try std.net.Address.parseIp4(listen_ip, listen_port),
                .socket = listenSock,
                .processPacketCallback = processPacketFuncListenerToForward,
            },
            .forward = Socket{
                .address = try std.net.Address.parseIp4(forward_ip, forward_port),
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
        const sentBytes = try std.posix.sendto(toSock.socket, buffer[0..], 0, &toSock.address.any, toSock.address.getOsSockLen());
        if (sentBytes != buffer.len) {
            std.debug.print("WARNING: Not all bytes sent!", .{});
        }
    }

    pub fn start(self: *const ProxySocketPair, timeout_ms: i32) !void {

        //Bind to listener
        try std.posix.bind(self.listener.socket, &self.listener.address.any, self.listener.address.getOsSockLen());

        //File descriptors to enable polling
        var pollfds = self.getPollFds();
        // Wait for events with a 5-second timeout
        var buffer: [READ_BUF_SIZE]u8 = undefined;
        std.debug.print("Starting proxy loop\n", .{});

        //Main proxy loop
        while (true) {
            const ready_count: usize = try std.posix.poll(&pollfds, timeout_ms);

            //Break on no use
            if (ready_count == 0) {
                std.debug.print("No packets recived in {d}s, exiting\n", .{@as(f32, @floatFromInt(timeout_ms)) / 1000});
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
