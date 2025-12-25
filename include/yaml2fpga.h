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
    uint32_t host_id;
    uint32_t local_ip;
    uint32_t peer_ip;
    uint16_t local_port;
    uint16_t peer_port;
    uint16_t local_qp;
    uint16_t peer_qp;
    uint8_t local_mac[6];
    uint8_t peer_mac[6];
    uint8_t up;
    uint8_t reserved[7];
} __attribute__((packed)) fpga_connection_entry_t;

// ============ 统一目的地路由表结构 (方案3: 树形拓扑优化) ============

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

// 广播配置表 (可选，用于AllReduce)
typedef struct {
    uint8_t  child_count;        // 子节点数量
    uint8_t  padding[3];
    uint16_t child_ports[4];     // 子节点端口号（最多4个）
    uint16_t child_qps[4];       // 子节点QP号
} __attribute__((packed)) fpga_broadcast_config_t;

// ============ 兼容旧结构（保留用于对比测试）============

// 服务器接入表头 (16字节)
typedef struct {
    uint32_t magic;              // 0x484F5354 ("HOST")
    uint32_t host_count;         // 主机数量
    uint32_t reserved[2];
} __attribute__((packed)) fpga_host_table_header_t;

// 服务器接入表条目 (24字节 - 优化版本)
typedef struct {
    uint32_t host_ip;            // 主机IP地址
    uint32_t switch_id;          // 接入交换机ID
    uint16_t port;               // 接入端口
    uint16_t qp;                 // 队列对编号
    uint8_t host_mac[6];         // 主机MAC地址
    uint8_t padding[6];          // 对齐填充
} __attribute__((packed)) fpga_host_entry_t;

// 交换机路径表头 (16字节)
typedef struct {
    uint32_t magic;              // 0x53574348 ("SWCH")
    uint32_t switch_count;       // 交换机数量
    uint32_t max_switch_id;      // 最大交换机ID（用于计算数组大小）
    uint32_t reserved;
} __attribute__((packed)) fpga_switch_path_header_t;

// 交换机路径表条目 (24字节 - 增强版本)
typedef struct {
    uint8_t valid;               // 是否有效 (1=有路径, 0=无路径或到自己)
    uint8_t padding[3];          // 对齐填充
    uint16_t out_port;           // 出端口
    uint16_t out_qp;             // 出QP
    uint32_t next_hop_ip;        // 下一跳IP地址
    uint16_t next_hop_port;      // 下一跳端口
    uint16_t next_hop_qp;        // 下一跳QP
    uint8_t next_hop_mac[6];     // 下一跳MAC地址
    uint8_t padding2[2];         // 对齐到24字节
} __attribute__((packed)) fpga_switch_path_entry_t;

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

// ============ 统一路由表函数声明（方案3）============
int build_unified_routing_table(const topology_config_t* config,
                                 uint32_t switch_id,
                                 fpga_dest_entry_t** dest_table,
                                 uint32_t* entry_count);
int generate_unified_routing_binary(const topology_config_t* config,
                                     const char* output_filename);
void print_dest_table(const fpga_dest_entry_t* dest_table, uint32_t entry_count, uint32_t switch_id);

// ============ 旧版两级路由表函数声明（兼容）============
int build_routing_tables(const topology_config_t* config,
                         fpga_host_entry_t** host_table, uint32_t* host_count,
                         fpga_switch_path_entry_t** switch_path_table,
                         uint32_t* switch_count, uint32_t* max_switch_id);
int generate_routing_table_binary(uint8_t** routing_data, size_t* routing_size,
                                   const fpga_host_entry_t* host_table, uint32_t host_count,
                                   const fpga_switch_path_entry_t* switch_path_table,
                                   uint32_t switch_count, uint32_t max_switch_id);
int write_routing_table_binary(const char* filename, const uint8_t* data, size_t size);
void print_routing_tables(const fpga_host_entry_t* host_table, uint32_t host_count,
                          const fpga_switch_path_entry_t* switch_path_table,
                          uint32_t switch_count, uint32_t max_switch_id);

#endif // YAML2FPGA_H