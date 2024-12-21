# UDP Proxy Server in Zig

This is a simple UDP proxy server written in Zig that listens for incoming UDP packets on one socket and forwards them to another address and port. The proxy also receives data from the forward socket and sends it back to the listener socket.

The server utilizes the standard Zig library for networking and system-level operations. It includes basic functionality for creating UDP sockets, binding them to addresses, and forwarding data between sockets.

## Features

- **UDP Packet Forwarding**: Listens on one UDP socket and forwards packets to another.
- **Socket Management**: Manages two UDP sockets: one for listening and another for forwarding data.
- **Polling**: Uses `poll` system calls to wait for data on either socket with a 5-second timeout.
- **Custom Packet Processing**: Placeholder functionality for processing UDP packets before forwarding.

## Installation

1. Ensure you have the Zig compiler installed. You can download it from [https://ziglang.org/download](https://ziglang.org/download).
2. Clone this repository or copy the code into your project.

```bash
git clone https://github.com/your-username/udp-proxy-zig.git
cd udp-proxy-zig
```

## Usage

### Running the Proxy

To run the proxy, you need to initialize it with the listener's and forwarder's IP addresses and ports. Here's an example:

```zig
pub fn main() !void {
    const proxyLib = @import("proxy.zig");

    const proxy = try proxyLib.ProxySocketPair.init(
        "127.0.0.1", 8080, // Listener IP and port
        "127.0.0.1", 9090 // Forwarder IP and port
    );

    try proxy.start(5000);
}

```

You can also run the proxy with custom callback functions to process the data being proxied. Here's an example:

```zig
const proxy = @import("proxy.zig");

fn processPacketFunction(data: []u8, dataLen: usize) usize {
    if (data.len > 10 and data[7] == 0x4f) {
        data[5] = 0xff;
    }
    return dataLen;
}

pub fn main() !void {
    const processPacketFuncCBListenerToForward: proxy.CBFunction = &processPacketFunction;
    const processPacketFuncCBForwardToListener: proxy.CBFunction = &processPacketFunction;

    const udpProxy = try proxy.ProxySocketPair.initWithCB(
        "127.0.0.1",
        8080,
        "127.0.0.1",
        9090,
        processPacketFuncCBListenerToForward,
        processPacketFuncCBForwardToListener,
    );

    try udpProxy.start(5000);
}
```

Callback functions have the type, `proxy.CBFunction` which is defined as `*const fn ([]u8, usize) usize`.

This code sets up a UDP proxy server that listens on `127.0.0.1:8080` and forwards packets to `127.0.0.1:9090`. In the second example, it also modifies the fifth byte to `0xff` if the seventh byte equals `0x4f`.

### Code Explanation

- **Socket Struct**: Represents a socket with its associated address and socket descriptor.
- **ProxySocketPair**: A struct that holds two sockets — one for the listener and one for forwarding. It provides methods to initialize, bind, poll, and handle socket events.
- **Packet Processing**: Two simple placeholder functions, `processPacketListenerToForward` and `processPacketForwardToListener`, allow you to inspect or modify the packet contents before forwarding.

### Functions

- `init(listen_ip, listen_port, forward_ip, forward_port)`: Initializes the proxy sockets for listening and forwarding.
- `getPollFds()`: Returns the file descriptors for the listener and forward sockets, which are used for polling.
- `receiveBuffer(sock, buffer)`: Receives a UDP packet into the provided buffer.
- `sendBuffer(toSock, buffer)`: Sends the contents of the buffer to the specified socket.
- `processPacketListenerToForward(buffer, dataLen)`: Processes data received on the listener socket before forwarding it.
- `processPacketForwardToListener(buffer, dataLen)`: Processes data received on the forward socket before sending it back to the listener.
- `start()`: Starts the proxy loop, binding the listener socket and handling incoming data with a polling mechanism.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues and pull requests. Contributions are welcome!
