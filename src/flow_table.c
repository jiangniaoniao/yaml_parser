#define _DEFAULT_SOURCE
#include "../include/yaml2fpga.h"
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>

// ============ 辅助函数 ============

// IP字符串转uint32（网络字节序）
static uint32_t ip_str_to_uint32(const char* ip_str) {
    struct in_addr addr;
    if (inet_aton(ip_str, &addr) == 0) {
        return 0;
    }
    return ntohl(addr.s_addr);
}

// MAC字符串转字节数组
static int mac_str_to_bytes(const char* mac_str, uint8_t* mac_bytes) {
    return sscanf(mac_str, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
                  &mac_bytes[0], &mac_bytes[1], &mac_bytes[2],
                  &mac_bytes[3], &mac_bytes[4], &mac_bytes[5]) == 6;
}

// 检查IP是否为交换机IP
static bool is_switch_ip(const topology_config_t* config, const char* ip) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
            if (strcmp(config->switches[i].connections[j].my_ip, ip) == 0) {
                return true;
            }
        }
    }
    return false;
}

// 根据IP查找交换机ID
static int find_switch_id_by_ip(const topology_config_t* config, const char* ip) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
            if (strcmp(config->switches[i].connections[j].my_ip, ip) == 0) {
                return config->switches[i].id;
            }
        }
    }
    return -1;
}

// 根据交换机ID查找索引
static int find_switch_index_by_id(const topology_config_t* config, uint32_t switch_id) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == switch_id) {
            return i;
        }
    }
    return -1;
}

// 查找两个交换机之间的连接
static network_connection_t* find_connection_between_switches(
    const topology_config_t* config, uint32_t from_switch_id, uint32_t to_switch_id) {

    int from_idx = find_switch_index_by_id(config, from_switch_id);
    if (from_idx < 0) return NULL;

    const switch_config_t* sw = &config->switches[from_idx];

    for (uint32_t j = 0; j < sw->connection_count; j++) {
        int peer_switch_id = find_switch_id_by_ip(config, sw->connections[j].peer_ip);
        if (peer_switch_id == (int)to_switch_id) {
            return (network_connection_t*)&sw->connections[j];
        }
    }
    return NULL;
}

// ============ 拓扑图构建 ============

// 构建交换机拓扑邻接矩阵
static void build_switch_topology(const topology_config_t* config,
                                  uint8_t adjacency[MAX_SWITCHES][MAX_SWITCHES]) {
    // 初始化邻接矩阵
    memset(adjacency, 0, MAX_SWITCHES * MAX_SWITCHES);

    // 创建ID到索引的映射
    int id_to_idx[MAX_SWITCHES];
    for (uint32_t i = 0; i < config->switch_count; i++) {
        id_to_idx[config->switches[i].id] = i;
    }

    // 构建邻接关系
    for (uint32_t i = 0; i < config->switch_count; i++) {
        const switch_config_t* sw = &config->switches[i];

        for (uint32_t j = 0; j < sw->connection_count; j++) {
            int peer_id = find_switch_id_by_ip(config, sw->connections[j].peer_ip);

            if (peer_id >= 0 && (uint32_t)peer_id != sw->id) {
                int from_idx = id_to_idx[sw->id];
                int to_idx = id_to_idx[peer_id];
                adjacency[from_idx][to_idx] = 1;
                adjacency[to_idx][from_idx] = 1;  // 无向图
            }
        }
    }
}

// ============ BFS最短路径算法 ============

static void bfs_shortest_paths(const topology_config_t* config,
                               int start_idx,
                               const uint8_t adjacency[MAX_SWITCHES][MAX_SWITCHES],
                               int distances[MAX_SWITCHES],
                               int next_hops[MAX_SWITCHES]) {
    int visited[MAX_SWITCHES] = {0};
    int queue[MAX_SWITCHES];
    int front = 0, rear = 0;

    // 初始化
    for (uint32_t i = 0; i < config->switch_count; i++) {
        distances[i] = -1;
        next_hops[i] = -1;
    }

    // 从起点开始
    visited[start_idx] = 1;
    distances[start_idx] = 0;
    next_hops[start_idx] = start_idx;
    queue[rear++] = start_idx;

    while (front < rear) {
        int current = queue[front++];

        for (uint32_t neighbor = 0; neighbor < config->switch_count; neighbor++) {
            if (adjacency[current][neighbor] && !visited[neighbor]) {
                visited[neighbor] = 1;
                distances[neighbor] = distances[current] + 1;

                // 记录下一跳
                if (distances[neighbor] == 1) {
                    next_hops[neighbor] = neighbor;  // 直接邻居
                } else {
                    next_hops[neighbor] = next_hops[current];  // 继承下一跳
                }

                queue[rear++] = neighbor;
            }
        }
    }
}

// ============ 主要函数实现 ============

// 构建服务器接入表
static int build_host_table(const topology_config_t* config,
                            fpga_host_entry_t** host_table,
                            uint32_t* host_count) {
    // 统计主机数量
    uint32_t count = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
            if (!is_switch_ip(config, config->switches[i].connections[j].peer_ip)) {
                count++;
            }
        }
    }

    if (count == 0) {
        *host_table = NULL;
        *host_count = 0;
        return SUCCESS;
    }

    // 分配内存
    *host_table = (fpga_host_entry_t*)calloc(count, sizeof(fpga_host_entry_t));
    if (!*host_table) {
        return ERR_INVALID_CONFIG;
    }

    // 填充数据
    uint32_t idx = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        const switch_config_t* sw = &config->switches[i];

        for (uint32_t j = 0; j < sw->connection_count; j++) {
            const network_connection_t* conn = &sw->connections[j];

            if (!is_switch_ip(config, conn->peer_ip)) {
                fpga_host_entry_t* entry = &(*host_table)[idx++];

                // 直接存储为主机字节序，便于Verilog硬件直接读取
                entry->host_ip = ip_str_to_uint32(conn->peer_ip);
                entry->switch_id = sw->id;
                entry->port = conn->my_port;
                entry->qp = conn->my_qp;
                mac_str_to_bytes(conn->peer_mac, entry->host_mac);
                memset(entry->padding, 0, sizeof(entry->padding));
            }
        }
    }

    *host_count = count;
    return SUCCESS;
}

// 构建交换机路径表（二维数组）
static int build_switch_path_table(const topology_config_t* config,
                                   fpga_switch_path_entry_t** switch_path_table,
                                   uint32_t* switch_count,
                                   uint32_t* max_switch_id) {
    if (config->switch_count == 0) {
        *switch_path_table = NULL;
        *switch_count = 0;
        *max_switch_id = 0;
        return SUCCESS;
    }

    // 找到最大交换机ID
    uint32_t max_id = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id > max_id) {
            max_id = config->switches[i].id;
        }
    }

    // 分配二维数组（扁平化）
    uint32_t array_size = (max_id + 1) * (max_id + 1);
    *switch_path_table = (fpga_switch_path_entry_t*)calloc(array_size, sizeof(fpga_switch_path_entry_t));
    if (!*switch_path_table) {
        return ERR_INVALID_CONFIG;
    }

    // 构建拓扑图
    uint8_t adjacency[MAX_SWITCHES][MAX_SWITCHES];
    build_switch_topology(config, adjacency);

    // 为每个交换机计算路径
    for (uint32_t i = 0; i < config->switch_count; i++) {
        const switch_config_t* src_sw = &config->switches[i];

        int distances[MAX_SWITCHES];
        int next_hops[MAX_SWITCHES];

        bfs_shortest_paths(config, i, adjacency, distances, next_hops);

        // 填充路径表
        for (uint32_t j = 0; j < config->switch_count; j++) {
            if (i == j) continue;  // 跳过到自己的路径

            const switch_config_t* dst_sw = &config->switches[j];

            if (distances[j] > 0 && next_hops[j] >= 0) {
                // 计算在二维数组中的位置
                uint32_t offset = src_sw->id * (max_id + 1) + dst_sw->id;
                fpga_switch_path_entry_t* entry = &(*switch_path_table)[offset];

                uint32_t next_hop_id = config->switches[next_hops[j]].id;

                // 查找到下一跳的连接信息
                network_connection_t* conn = find_connection_between_switches(config, src_sw->id, next_hop_id);

                if (conn) {
                    entry->valid = 1;
                    memset(entry->padding, 0, sizeof(entry->padding));
                    // 直接存储为主机字节序，便于Verilog硬件直接读取
                    entry->out_port = conn->my_port;
                    entry->out_qp = conn->my_qp;
                    entry->next_hop_ip = ip_str_to_uint32(conn->peer_ip);
                    entry->next_hop_port = conn->peer_port;
                    entry->next_hop_qp = conn->peer_qp;
                    mac_str_to_bytes(conn->peer_mac, entry->next_hop_mac);
                    memset(entry->padding2, 0, sizeof(entry->padding2));
                }
            }
        }
    }

    *switch_count = config->switch_count;
    *max_switch_id = max_id;
    return SUCCESS;
}

// ============ 导出函数 ============

// 构建两级路由表
int build_routing_tables(const topology_config_t* config,
                         fpga_host_entry_t** host_table, uint32_t* host_count,
                         fpga_switch_path_entry_t** switch_path_table,
                         uint32_t* switch_count, uint32_t* max_switch_id) {
    int result;

    // 构建服务器接入表
    result = build_host_table(config, host_table, host_count);
    if (result != SUCCESS) {
        return result;
    }

    // 构建交换机路径表
    result = build_switch_path_table(config, switch_path_table, switch_count, max_switch_id);
    if (result != SUCCESS) {
        if (*host_table) free(*host_table);
        return result;
    }

    return SUCCESS;
}

// 生成独立的路由表二进制数据
int generate_routing_table_binary(uint8_t** routing_data, size_t* routing_size,
                                   const fpga_host_entry_t* host_table, uint32_t host_count,
                                   const fpga_switch_path_entry_t* switch_path_table,
                                   uint32_t switch_count, uint32_t max_switch_id) {
    // 计算总大小
    size_t host_table_size = sizeof(fpga_host_table_header_t) + host_count * sizeof(fpga_host_entry_t);
    size_t switch_table_size = sizeof(fpga_switch_path_header_t) +
                               (max_switch_id + 1) * (max_switch_id + 1) * sizeof(fpga_switch_path_entry_t);

    size_t total_size = host_table_size + switch_table_size;

    // 分配内存
    uint8_t* data = (uint8_t*)malloc(total_size);
    if (!data) {
        return ERR_INVALID_CONFIG;
    }

    uint8_t* write_ptr = data;

    // 写入服务器接入表头 (直接使用主机字节序，便于Verilog读取)
    fpga_host_table_header_t host_header;
    host_header.magic = 0x484F5354;  // "HOST"
    host_header.host_count = host_count;
    host_header.reserved[0] = 0;
    host_header.reserved[1] = 0;

    memcpy(write_ptr, &host_header, sizeof(host_header));
    write_ptr += sizeof(host_header);

    // 写入服务器接入表数据
    if (host_count > 0) {
        memcpy(write_ptr, host_table, host_count * sizeof(fpga_host_entry_t));
        write_ptr += host_count * sizeof(fpga_host_entry_t);
    }

    // 写入交换机路径表头 (直接使用主机字节序，便于Verilog读取)
    fpga_switch_path_header_t switch_header;
    switch_header.magic = 0x53574348;  // "SWCH"
    switch_header.switch_count = switch_count;
    switch_header.max_switch_id = max_switch_id;
    switch_header.reserved = 0;

    memcpy(write_ptr, &switch_header, sizeof(switch_header));
    write_ptr += sizeof(switch_header);

    // 写入交换机路径表数据
    uint32_t array_size = (max_switch_id + 1) * (max_switch_id + 1);
    memcpy(write_ptr, switch_path_table, array_size * sizeof(fpga_switch_path_entry_t));

    *routing_data = data;
    *routing_size = total_size;
    return SUCCESS;
}

// 写入路由表二进制文件
int write_routing_table_binary(const char* filename, const uint8_t* data, size_t size) {
    FILE* file = fopen(filename, "wb");
    if (!file) {
        return ERR_FILE_NOT_FOUND;
    }

    size_t written = fwrite(data, 1, size, file);
    fclose(file);

    if (written != size) {
        return ERR_INVALID_CONFIG;
    }

    return SUCCESS;
}

// 打印路由表
void print_routing_tables(const fpga_host_entry_t* host_table, uint32_t host_count,
                          const fpga_switch_path_entry_t* switch_path_table,
                          uint32_t switch_count, uint32_t max_switch_id) {
    printf("\n=== 两级路由表 ===\n");

    // 打印服务器接入表
    printf("\n📋 服务器接入表 (%u 条记录):\n", host_count);
    printf("%-20s %-12s %-8s %-6s\n", "主机IP", "交换机ID", "端口", "QP");
    printf("----------------------------------------------\n");

    for (uint32_t i = 0; i < host_count; i++) {
        struct in_addr addr;
        addr.s_addr = htonl(host_table[i].host_ip);  // 转换为网络字节序供inet_ntoa使用
        printf("%-20s %-12u %-8u %-6u\n",
               inet_ntoa(addr),
               host_table[i].switch_id,
               host_table[i].port,
               host_table[i].qp);
    }

    // 打印交换机路径表统计
    printf("\n🔀 交换机路径表:\n");
    printf("交换机数量: %u\n", switch_count);
    printf("最大交换机ID: %u\n", max_switch_id);
    printf("二维数组大小: %u × %u = %u 条目\n",
           max_switch_id + 1, max_switch_id + 1, (max_switch_id + 1) * (max_switch_id + 1));

    uint32_t valid_count = 0;
    for (uint32_t i = 0; i <= max_switch_id; i++) {
        for (uint32_t j = 0; j <= max_switch_id; j++) {
            uint32_t offset = i * (max_switch_id + 1) + j;
            if (switch_path_table[offset].valid) {
                valid_count++;
            }
        }
    }
    printf("有效路径条目: %u\n", valid_count);

    printf("\n有效路径详情:\n");
    printf("%-8s %-8s %-8s %-6s %-20s\n",
           "源交换机", "目标", "端口", "QP", "下一跳MAC");
    printf("--------------------------------------------------------\n");

    for (uint32_t i = 0; i <= max_switch_id; i++) {
        for (uint32_t j = 0; j <= max_switch_id; j++) {
            uint32_t offset = i * (max_switch_id + 1) + j;
            const fpga_switch_path_entry_t* entry = &switch_path_table[offset];

            if (entry->valid) {
                printf("%-8u %-8u %-8u %-6u %02x:%02x:%02x:%02x:%02x:%02x\n",
                       i, j,
                       entry->out_port,
                       entry->out_qp,
                       entry->next_hop_mac[0], entry->next_hop_mac[1],
                       entry->next_hop_mac[2], entry->next_hop_mac[3],
                       entry->next_hop_mac[4], entry->next_hop_mac[5]);
            }
        }
    }

    printf("\n内存占用:\n");
    printf("  服务器接入表: %zu 字节\n", host_count * sizeof(fpga_host_entry_t));
    printf("  交换机路径表: %zu 字节\n",
           (max_switch_id + 1) * (max_switch_id + 1) * sizeof(fpga_switch_path_entry_t));
    printf("  总计: %zu 字节\n",
           host_count * sizeof(fpga_host_entry_t) +
           (max_switch_id + 1) * (max_switch_id + 1) * sizeof(fpga_switch_path_entry_t));
}
