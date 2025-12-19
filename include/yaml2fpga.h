#ifndef YAML2FPGA_H
#define YAML2FPGA_H

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <yaml.h>
#include <arpa/inet.h>

// Configuration limits
#define MAX_SWITCHES 64
#define MAX_CONNECTIONS_PER_SWITCH 32
#define MAX_IP_ADDR_LEN 16
#define MAX_MAC_ADDR_LEN 18


// Network connection configuration
typedef struct {
    char my_ip[MAX_IP_ADDR_LEN];
    char my_mac[MAX_MAC_ADDR_LEN];
    uint16_t my_port;
    char peer_ip[MAX_IP_ADDR_LEN];
    char peer_mac[MAX_MAC_ADDR_LEN];
    uint16_t peer_port;
} network_connection_t;

// Switch configuration
typedef struct {
    uint32_t id;
    bool is_root;
    uint32_t connection_count;
    network_connection_t connections[MAX_CONNECTIONS_PER_SWITCH];
} switch_config_t;

// Topology configuration
typedef struct {
    uint32_t switch_count;
    switch_config_t switches[MAX_SWITCHES];
} topology_config_t;

// FPGA configuration structure
typedef struct {
    uint32_t magic;           // 0x46475441 ("ATGF")
    uint32_t version;         // Format version
    uint32_t total_connections;// Total number of connections
    uint32_t timestamp;       // Generation timestamp
    uint8_t data[];          // Connection data follows
} __attribute__((packed)) fpga_config_header_t;

// Individual connection entry for FPGA
typedef struct {
    uint32_t switch_id;
    uint32_t local_ip;
    uint32_t peer_ip;
    uint16_t local_port;
    uint16_t peer_port;
    uint8_t local_mac[6];
    uint8_t peer_mac[6];
} __attribute__((packed)) fpga_connection_entry_t;

// Error codes
#define SUCCESS 0
#define ERR_FILE_NOT_FOUND -1
#define ERR_YAML_PARSE -2
#define ERR_INVALID_CONFIG -3

// Function declarations
int parse_yaml_topology(const char* filename, topology_config_t* config);
int convert_to_fpga_format(const topology_config_t* config, uint8_t** output_data, size_t* output_size);
int write_fpga_binary(const char* filename, const uint8_t* data, size_t size);
void cleanup_topology(topology_config_t* config);
void print_topology_summary(const topology_config_t* config);

#endif // YAML2FPGA_H