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

To run the proxy, you need to initialize the proxy with the listener and forward IP addresses and ports. Example:

```zig
const ProxySocketPair = @import("proxy_socket_pair.zig");

const proxy = try ProxySocketPair.init(
    "127.0.0.1", 8080, // listener IP and port
    "127.0.0.1", 9090  // forward IP and port
);

try proxy.start();
```

The above code will set up a UDP proxy server that listens on `127.0.0.1:8080` and forwards the packets to `127.0.0.1:9090`.

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
