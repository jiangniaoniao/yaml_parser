#define _DEFAULT_SOURCE
#include "../include/yaml2fpga.h"
#include <arpa/inet.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>

// Convert MAC string to bytes
static int mac_to_bytes(const char* mac_str, uint8_t* mac_bytes) {
    return sscanf(mac_str, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
               &mac_bytes[0], &mac_bytes[1], &mac_bytes[2],
               &mac_bytes[3], &mac_bytes[4], &mac_bytes[5]) == 6;
}

// Convert IP string to network order bytes
static uint32_t ip_to_uint32(const char* ip_str) {
    struct in_addr addr;
    if (inet_aton(ip_str, &addr) == 0) {
        return 0;
    }
    return addr.s_addr;
}

// Count total connections across all switches
static uint32_t count_total_connections(const topology_config_t* config) {
    uint32_t total = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        total += config->switches[i].connection_count;
    }
    return total;
}

// Calculate total size needed for FPGA configuration
static size_t calculate_fpga_config_size(const topology_config_t* config) {
    return sizeof(fpga_config_header_t) + 
           sizeof(fpga_connection_entry_t) * count_total_connections(config);
}

// Convert YAML topology to FPGA binary format
int convert_to_fpga_format(const topology_config_t* config, uint8_t** output_data, size_t* output_size) {
    if (!config || !output_data || !output_size) {
        return ERR_INVALID_CONFIG;
    }
    
    size_t total_size = calculate_fpga_config_size(config);
    uint8_t* buffer = malloc(total_size);
    
    if (!buffer) {
        return ERR_INVALID_CONFIG;
    }
    
    *output_data = buffer;
    *output_size = total_size;
    
    // Build header
    fpga_config_header_t* header = (fpga_config_header_t*)buffer;
    header->magic = 0x46475441;  // "ATGF" - FPGA ATG
    header->version = 1;
    header->total_connections = count_total_connections(config);
    header->timestamp = (uint32_t)time(NULL);
    
    uint8_t* data_ptr = buffer + sizeof(fpga_config_header_t);
    
    // Convert each connection to FPGA format
    for (uint32_t switch_idx = 0; switch_idx < config->switch_count; switch_idx++) {
        const switch_config_t* sw = &config->switches[switch_idx];
        
        for (uint32_t conn_idx = 0; conn_idx < sw->connection_count; conn_idx++) {
            const network_connection_t* conn = &sw->connections[conn_idx];
            
            fpga_connection_entry_t* fpga_conn = (fpga_connection_entry_t*)data_ptr;
            
            // Fill FPGA connection entry
            fpga_conn->switch_id = htonl(sw->id);
            fpga_conn->host_id = htonl(conn->host_id);
            fpga_conn->local_ip = ip_to_uint32(conn->my_ip);
            fpga_conn->peer_ip = ip_to_uint32(conn->peer_ip);
            fpga_conn->local_port = htons(conn->my_port);
            fpga_conn->peer_port = htons(conn->peer_port);
            fpga_conn->local_qp = htons(conn->my_qp);
            fpga_conn->peer_qp = htons(conn->peer_qp);
            fpga_conn->up = (conn->up == CONN_UP) ? 1 : 0;
            memset(fpga_conn->reserved, 0, sizeof(fpga_conn->reserved));
            
            // Convert MAC addresses
            if (!mac_to_bytes(conn->my_mac, fpga_conn->local_mac)) {
                printf("Error parsing local MAC: %s\n", conn->my_mac);
                return ERR_INVALID_CONFIG;
            }
            
            if (!mac_to_bytes(conn->peer_mac, fpga_conn->peer_mac)) {
                printf("Error parsing peer MAC: %s\n", conn->peer_mac);
                return ERR_INVALID_CONFIG;
            }
            
            data_ptr += sizeof(fpga_connection_entry_t);
        }
    }
    
    return SUCCESS;
}

// Write binary data to file
int write_fpga_binary(const char* filename, const uint8_t* data, size_t size) {
    FILE* file = fopen(filename, "wb");
    if (!file) {
        return ERR_FILE_NOT_FOUND;
    }
    
    size_t written = fwrite(data, 1, size, file);
    fclose(file);
    
    return (written == size) ? SUCCESS : ERR_FILE_NOT_FOUND;
}

// Print topology summary
void print_topology_summary(const topology_config_t* config) {
    printf("=== Topology Summary ===\n");
    printf("Switches: %u\n", config->switch_count);
    
    int root_count = 0;
    uint32_t total_connections = 0;
    
    for (uint32_t i = 0; i < config->switch_count; i++) {
        const switch_config_t* sw = &config->switches[i];
        
        if (sw->is_root) {
            root_count++;
        }
        
        total_connections += sw->connection_count;
        
        printf("  Switch %u (Root: %s): %u connections\n", 
               sw->id, sw->is_root ? "Yes" : "No", sw->connection_count);
    }
    
    printf("Total connections: %u\n", total_connections);
    printf("Root switches: %d\n", root_count);
    printf("======================\n");
}

// Cleanup function
void cleanup_topology(topology_config_t* config) {
    if (config) {
        memset(config, 0, sizeof(topology_config_t));
    }
}