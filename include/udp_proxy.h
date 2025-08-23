#ifndef UDP_PROXY_H
#define UDP_PROXY_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle for UDP proxy instance
typedef struct UdpProxy UdpProxy;

// Built-in processor types
typedef enum {
    UDP_PROXY_PROCESSOR_PASS_THROUGH = 0,
    UDP_PROXY_PROCESSOR_LOGGING,
    UDP_PROXY_PROCESSOR_FILTERING,
    UDP_PROXY_PROCESSOR_CUSTOM,
    UDP_PROXY_PROCESSOR_SRT_NAK_MALFORMER,
    UDP_PROXY_PROCESSOR_SRT_NAK_MALFORMER_BIDIRECTIONAL,
    UDP_PROXY_PROCESSOR_PACKET_DROPPER,
    UDP_PROXY_PROCESSOR_USER_DEFINED
} UdpProxyProcessorType;

// Packet processing callback function type
// Parameters:
//   data: Packet data buffer (can be modified in-place)
//   size: Current packet size in bytes
//   user_data: User-provided context data
// Returns: Number of bytes to forward (0 to drop packet)
// Note: This C API uses the legacy callback interface. The core Zig library
//       uses a modern slice-based interface for better performance and safety.
typedef size_t (*PacketProcessor)(uint8_t* data, size_t size, void* user_data);

// Direction enumeration
typedef enum {
    UDP_PROXY_LISTENER_TO_FORWARD = 0,
    UDP_PROXY_FORWARD_TO_LISTENER = 1
} UdpProxyDirection;

// Event structure for advanced API
typedef struct {
    size_t bytes_processed;
    UdpProxyDirection direction;
} UdpProxyEvent;

// Configuration structure for built-in processors
typedef struct {
    UdpProxyProcessorType type;
    union {
        struct {
            const char* pattern;  // For filtering processor
        } filtering;
        struct {
            int packet_limit;     // For packet dropper processor
        } dropper;
        struct {
            PacketProcessor listener_to_forward;
            PacketProcessor forward_to_listener;
            void* user_data;
        } user_defined;
    } config;
} UdpProxyProcessorConfig;

// Simple API functions
UdpProxy* udp_proxy_create_builtin(
    const char* listen_ip, 
    uint16_t listen_port,
    const char* forward_ip, 
    uint16_t forward_port,
    const UdpProxyProcessorConfig* processor_config
);

UdpProxy* udp_proxy_create_custom(
    const char* listen_ip, 
    uint16_t listen_port,
    const char* forward_ip, 
    uint16_t forward_port,
    PacketProcessor listener_to_forward_processor,
    PacketProcessor forward_to_listener_processor,
    void* user_data
);

int udp_proxy_start(UdpProxy* proxy, int timeout_ms);
void udp_proxy_destroy(UdpProxy* proxy);

// Advanced API functions
int udp_proxy_bind(UdpProxy* proxy);
int udp_proxy_poll(UdpProxy* proxy, int timeout_ms);
int udp_proxy_process_events(UdpProxy* proxy, UdpProxyEvent* events, size_t max_events);

// Utility functions for built-in processors
void udp_proxy_processor_config_init(UdpProxyProcessorConfig* config, UdpProxyProcessorType type);

#ifdef __cplusplus
}
#endif

#endif // UDP_PROXY_H