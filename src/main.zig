const std = @import("std");
const proxy = @import("proxy.zig");
const srt = @import("srt.zig");

pub fn main() !void {
    //Create the UDP Proxy with two callback functions.

    const processPacketFuncCBListenerToForward: proxy.CBFunction = srt.discardThreePacketsAfter(1000);
    const processPacketFuncCBForwardToListener: proxy.CBFunction = &srt.createSRTMalformedNAK;
    const udpProxy = try proxy.ProxySocketPair.initWithCB(
        "127.0.0.1",
        3000,
        "127.0.0.1",
        4000,
        processPacketFuncCBListenerToForward,
        processPacketFuncCBForwardToListener,
    );

    //Start the proxy
    try udpProxy.start(5000);
}
