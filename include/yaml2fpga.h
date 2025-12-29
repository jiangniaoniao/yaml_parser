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

// Connection status
typedef enum {
    CONN_DOWN = 0,
    CONN_UP = 1
} connection_status_t;

// Network connection configuration
typedef struct {
    connection_status_t up;
    uint32_t host_id;
    char my_ip[MAX_IP_ADDR_LEN];
    char my_mac[MAX_MAC_ADDR_LEN];
    uint16_t my_port;
    uint16_t my_qp;
    char peer_ip[MAX_IP_ADDR_LEN];
    char peer_mac[MAX_MAC_ADDR_LEN];
    uint16_t peer_port;
    uint16_t peer_qp;
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

// ============ 统一目的地路由表结构 ============

// 目的地路由表头 (16字节)
typedef struct {
    uint32_t magic;              // 0x44455354 ("DEST")
    uint32_t entry_count;        // 路由表条目数量
    uint32_t switch_id;          // 本交换机ID
    uint32_t reserved;
} __attribute__((packed)) fpga_dest_table_header_t;

// 目的地路由表条目 (32字节)
// 每个Switch存储到所有目标（Host/Switch）的路由信息
typedef struct {
    // 匹配字段
    uint32_t dst_ip;             // 目标IP地址（匹配键）
    uint8_t  valid;              // 有效位

    // 特殊标志
    uint8_t  is_direct_host;     // 是否直连Host (1=直连, 0=需转发)
    uint8_t  is_broadcast;       // AllReduce下行时是否广播
    uint8_t  padding1;

    // 转发动作
    uint16_t out_port;           // 输出端口
    uint16_t out_qp;             // 输出QP
    uint32_t next_hop_ip;        // 下一跳IP地址
    uint16_t next_hop_port;      // 下一跳端口
    uint16_t next_hop_qp;        // 下一跳QP
    uint8_t  next_hop_mac[6];    // 下一跳MAC地址

    uint8_t  padding2[6];        // 对齐到32字节
} __attribute__((packed)) fpga_dest_entry_t;

// 广播配置表 预留
typedef struct {
    uint8_t  child_count;        // 子节点数量
    uint8_t  padding[3];
    uint16_t child_ports[4];     // 子节点端口号（最多4个）
    uint16_t child_qps[4];       // 子节点QP号
} __attribute__((packed)) fpga_broadcast_config_t;

// Error codes
#define SUCCESS 0
#define ERR_FILE_NOT_FOUND -1
#define ERR_YAML_PARSE -2
#define ERR_INVALID_CONFIG -3

// Function declarations
int parse_yaml_topology(const char* filename, topology_config_t* config);
void cleanup_topology(topology_config_t* config);
void print_topology_summary(const topology_config_t* config);

// 统一路由表函数声明
int build_unified_routing_table(const topology_config_t* config,
                                 uint32_t switch_id,
                                 fpga_dest_entry_t** dest_table,
                                 uint32_t* entry_count);
int generate_unified_routing_binary(const topology_config_t* config,
                                     const char* output_filename);
void print_dest_table(const fpga_dest_entry_t* dest_table, uint32_t entry_count, uint32_t switch_id);

#endif // YAML2FPGA_H