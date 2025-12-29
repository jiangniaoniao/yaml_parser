#include "yaml2fpga.h"
#include <time.h>

// ============ 辅助函数声明 ============
static uint32_t ip_str_to_uint32(const char* ip_str);
static void mac_str_to_bytes(const char* mac_str, uint8_t* mac_bytes);
static network_connection_t* find_uplink_connection(const topology_config_t* config, uint32_t switch_id);
static network_connection_t* find_host_connection(const topology_config_t* config, uint32_t switch_id, uint32_t host_ip);
static uint32_t find_host_attached_switch(const topology_config_t* config, uint32_t host_ip);
static bool is_root_switch(const topology_config_t* config, uint32_t switch_id);
static uint32_t find_subtree_switch(const topology_config_t* config, uint32_t root_id, uint32_t target_switch_id);
static network_connection_t* find_downlink_to_switch(const topology_config_t* config, uint32_t from_switch, uint32_t to_switch);
static int collect_all_hosts(const topology_config_t* config, uint32_t** host_ips, uint32_t* host_count);

// ============ IP和MAC转换函数 ============
static uint32_t ip_str_to_uint32(const char* ip_str) {
    uint32_t a, b, c, d;
    if (sscanf(ip_str, "%u.%u.%u.%u", &a, &b, &c, &d) != 4) {
        fprintf(stderr, "错误: 无效的IP地址格式: %s\n", ip_str);
        return 0;
    }
    return (a << 24) | (b << 16) | (c << 8) | d;
}

static void mac_str_to_bytes(const char* mac_str, uint8_t* mac_bytes) {
    unsigned int m[6];
    if (sscanf(mac_str, "%x:%x:%x:%x:%x:%x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]) != 6) {
        fprintf(stderr, "错误: 无效的MAC地址格式: %s\n", mac_str);
        memset(mac_bytes, 0, 6);
        return;
    }
    // 反向存储以适应Verilog的48位读取（小端序）
    // 例如 "52:54:00:c2:11:88" 存储为 [88,11,c2,00,54,52]
    // 这样在Verilog中读取48位时会得到正确的 0x525400c21188
    for (int i = 0; i < 6; i++) {
        mac_bytes[5 - i] = (uint8_t)m[i];
    }
}

// ============ 拓扑查询辅助函数 ============

// 查找交换机的上行连接（连接到父交换机）
static network_connection_t* find_uplink_connection(const topology_config_t* config, uint32_t switch_id) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == switch_id) {
            for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
                if (config->switches[i].connections[j].up == CONN_UP) {
                    return &config->switches[i].connections[j];
                }
            }
        }
    }
    return NULL;
}

// 查找交换机到某个Host的直连连接
static network_connection_t* find_host_connection(const topology_config_t* config,
                                                   uint32_t switch_id, uint32_t host_ip) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == switch_id) {
            for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
                network_connection_t* conn = &config->switches[i].connections[j];
                if (ip_str_to_uint32(conn->peer_ip) == host_ip && conn->up == CONN_DOWN) {
                    return conn;
                }
            }
        }
    }
    return NULL;
}

// 查找Host连接到哪个交换机
static uint32_t find_host_attached_switch(const topology_config_t* config, uint32_t host_ip) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
            network_connection_t* conn = &config->switches[i].connections[j];
            if (ip_str_to_uint32(conn->peer_ip) == host_ip && conn->up == CONN_DOWN) {
                return config->switches[i].id;
            }
        }
    }
    return 0;  // 未找到
}

// 判断是否为根交换机
static bool is_root_switch(const topology_config_t* config, uint32_t switch_id) {
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == switch_id) {
            return config->switches[i].is_root;
        }
    }
    return false;
}

// 查找目标交换机在根交换机的哪个子树下（用于根交换机路由决策）
static uint32_t find_subtree_switch(const topology_config_t* config,
                                      uint32_t root_id, uint32_t target_switch_id) {
    if (target_switch_id == root_id) {
        return root_id;
    }

    // 从目标交换机向上回溯，直到找到根的直接子节点
    uint32_t current = target_switch_id;

    while (current != 0) {
        // 查找current的父交换机
        network_connection_t* uplink = find_uplink_connection(config, current);
        if (!uplink) {
            break;  // 已经到达根
        }

        // 解析父交换机的IP找到其ID
        uint32_t parent_ip = ip_str_to_uint32(uplink->peer_ip);
        uint32_t parent_id = 0;
        for (uint32_t i = 0; i < config->switch_count; i++) {
            if (ip_str_to_uint32(config->switches[i].connections[0].my_ip) == parent_ip) {
                parent_id = config->switches[i].id;
                break;
            }
        }

        if (parent_id == root_id) {
            return current;  // current是根的直接子节点
        }

        current = parent_id;
    }

    return target_switch_id;  // 默认返回自己
}

// 查找从一个交换机到另一个交换机的下行连接
static network_connection_t* find_downlink_to_switch(const topology_config_t* config,
                                                       uint32_t from_switch, uint32_t to_switch) {
    // 先获取目标交换机的IP地址
    uint32_t to_switch_ip = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == to_switch) {
            to_switch_ip = ip_str_to_uint32(config->switches[i].connections[0].my_ip);
            break;
        }
    }

    if (to_switch_ip == 0) {
        return NULL;
    }

    // 在from_switch的连接中查找peer_ip等于to_switch_ip的下行连接
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].id == from_switch) {
            for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
                network_connection_t* conn = &config->switches[i].connections[j];
                if (conn->up == CONN_DOWN &&
                    ip_str_to_uint32(conn->peer_ip) == to_switch_ip) {
                    return conn;
                }
            }
        }
    }

    return NULL;
}

// 收集拓扑中所有Host的IP地址
static int collect_all_hosts(const topology_config_t* config, uint32_t** host_ips, uint32_t* host_count) {
    *host_count = 0;
    *host_ips = malloc(sizeof(uint32_t) * 256);  // 最多256个Host

    if (!*host_ips) {
        fprintf(stderr, "错误: 内存分配失败\n");
        return -1;
    }

    // 遍历所有交换机的下行连接，收集Host IP
    for (uint32_t i = 0; i < config->switch_count; i++) {
        for (uint32_t j = 0; j < config->switches[i].connection_count; j++) {
            network_connection_t* conn = &config->switches[i].connections[j];
            if (conn->up == CONN_DOWN) {
                uint32_t ip = ip_str_to_uint32(conn->peer_ip);

                // 检查是否已经添加过（去重）
                bool exists = false;
                for (uint32_t k = 0; k < *host_count; k++) {
                    if ((*host_ips)[k] == ip) {
                        exists = true;
                        break;
                    }
                }

                if (!exists) {
                    (*host_ips)[*host_count] = ip;
                    (*host_count)++;
                }
            }
        }
    }

    printf("收集到 %u 个Host\n", *host_count);
    return 0;
}

// ============ 核心函数：为指定交换机构建统一路由表 ============
int build_unified_routing_table(const topology_config_t* config,
                                 uint32_t switch_id,
                                 fpga_dest_entry_t** dest_table,
                                 uint32_t* entry_count) {
    printf("\n构建Switch %u的统一路由表...\n", switch_id);

    // 收集所有Host
    uint32_t* all_host_ips = NULL;
    uint32_t total_hosts = 0;
    if (collect_all_hosts(config, &all_host_ips, &total_hosts) != 0) {
        return -1;
    }

    // 分配路由表内存
    *dest_table = malloc(sizeof(fpga_dest_entry_t) * total_hosts);
    if (!*dest_table) {
        fprintf(stderr, "错误: 内存分配失败\n");
        free(all_host_ips);
        return -1;
    }
    memset(*dest_table, 0, sizeof(fpga_dest_entry_t) * total_hosts);

    *entry_count = 0;
    bool is_root = is_root_switch(config, switch_id);

    // 为每个Host生成路由条目
    for (uint32_t i = 0; i < total_hosts; i++) {
        uint32_t host_ip = all_host_ips[i];
        fpga_dest_entry_t* entry = &(*dest_table)[*entry_count];

        entry->dst_ip = host_ip;
        entry->valid = 1;

        // 判断Host相对于当前交换机的位置
        uint32_t host_switch_id = find_host_attached_switch(config, host_ip);

        if (host_switch_id == 0) {
            fprintf(stderr, "警告: Host IP %08x 未找到所属交换机\n", host_ip);
            continue;
        }

        if (host_switch_id == switch_id) {
            // 情况1：直连Host
            entry->is_direct_host = 1;
            network_connection_t* conn = find_host_connection(config, switch_id, host_ip);

            if (conn) {
                entry->out_port = conn->my_port;
                entry->out_qp = conn->my_qp;
                entry->next_hop_ip = ip_str_to_uint32(conn->peer_ip);
                entry->next_hop_port = conn->peer_port;
                entry->next_hop_qp = conn->peer_qp;
                mac_str_to_bytes(conn->peer_mac, entry->next_hop_mac);

                printf("  [Entry %u] 直连Host: %s -> port=%u, QP=%u\n",
                       *entry_count, conn->peer_ip, entry->out_port, entry->out_qp);
            }

        } else {
            // 情况2：非直连Host，需要路由
            entry->is_direct_host = 0;

            if (is_root) {
                // 根交换机：需要判断目标在哪个子树
                uint32_t subtree_switch = find_subtree_switch(config, switch_id, host_switch_id);
                network_connection_t* conn = find_downlink_to_switch(config, switch_id, subtree_switch);

                if (conn) {
                    entry->out_port = conn->my_port;
                    entry->out_qp = conn->my_qp;
                    entry->next_hop_ip = ip_str_to_uint32(conn->peer_ip);
                    entry->next_hop_port = conn->peer_port;
                    entry->next_hop_qp = conn->peer_qp;
                    mac_str_to_bytes(conn->peer_mac, entry->next_hop_mac);

                    printf("  [Entry %u] 路由到子树Switch %u: host_ip=%08x -> next_hop=%s, port=%u, QP=%u\n",
                           *entry_count, subtree_switch, host_ip, conn->peer_ip, entry->out_port, entry->out_qp);
                }

            } else {
                // 中间交换机：默认路由（向上转发）
                network_connection_t* uplink = find_uplink_connection(config, switch_id);

                if (uplink) {
                    entry->out_port = uplink->my_port;
                    entry->out_qp = uplink->my_qp;
                    entry->next_hop_ip = ip_str_to_uint32(uplink->peer_ip);
                    entry->next_hop_port = uplink->peer_port;
                    entry->next_hop_qp = uplink->peer_qp;
                    mac_str_to_bytes(uplink->peer_mac, entry->next_hop_mac);

                    printf("  [Entry %u] 默认路由(向上): host_ip=%08x -> next_hop=%s, port=%u, QP=%u\n",
                           *entry_count, host_ip, uplink->peer_ip, entry->out_port, entry->out_qp);
                }
            }
        }

        (*entry_count)++;
    }

    free(all_host_ips);
    printf("Switch %u 路由表构建完成，共 %u 条目\n", switch_id, *entry_count);
    return 0;
}

// ============ 生成二进制文件（包含所有交换机的路由表）============
int generate_unified_routing_binary(const topology_config_t* config,
                                     const char* output_filename) {
    FILE* fp = fopen(output_filename, "wb");
    if (!fp) {
        fprintf(stderr, "错误: 无法创建文件 %s\n", output_filename);
        return -1;
    }

    printf("\n开始生成统一路由表二进制文件...\n");

    // 为每个交换机生成并写入路由表
    for (uint32_t sw_id = 1; sw_id <= config->switch_count; sw_id++) {
        fpga_dest_entry_t* dest_table = NULL;
        uint32_t entry_count = 0;

        // 构建路由表
        if (build_unified_routing_table(config, sw_id, &dest_table, &entry_count) != 0) {
            fprintf(stderr, "错误: 构建Switch %u路由表失败\n", sw_id);
            fclose(fp);
            return -1;
        }

        // 写入表头
        fpga_dest_table_header_t header;
        header.magic = 0x44455354;  // "DEST"
        header.entry_count = entry_count;
        header.switch_id = sw_id;
        header.reserved = 0;

        fwrite(&header, sizeof(fpga_dest_table_header_t), 1, fp);

        // 写入表条目
        fwrite(dest_table, sizeof(fpga_dest_entry_t), entry_count, fp);

        printf("已写入Switch %u的路由表: %u条目, %zu字节\n",
               sw_id, entry_count, sizeof(header) + entry_count * sizeof(fpga_dest_entry_t));

        free(dest_table);
    }

    fclose(fp);
    printf("\n统一路由表二进制文件生成完成: %s\n", output_filename);
    return 0;
}

// ============ 打印路由表（用于调试）============
void print_dest_table(const fpga_dest_entry_t* dest_table, uint32_t entry_count, uint32_t switch_id) {
    printf("\n========== Switch %u 目的地路由表 ==========\n", switch_id);
    printf("条目数量: %u\n\n", entry_count);

    for (uint32_t i = 0; i < entry_count; i++) {
        const fpga_dest_entry_t* e = &dest_table[i];

        if (!e->valid) continue;

        printf("[Entry %u]\n", i);
        printf("  dst_ip:         %u.%u.%u.%u\n",
               (e->dst_ip >> 24) & 0xFF, (e->dst_ip >> 16) & 0xFF,
               (e->dst_ip >> 8) & 0xFF, e->dst_ip & 0xFF);
        printf("  is_direct_host: %u\n", e->is_direct_host);
        printf("  is_broadcast:   %u\n", e->is_broadcast);
        printf("  out_port:       %u\n", e->out_port);
        printf("  out_qp:         %u\n", e->out_qp);
        printf("  next_hop_ip:    %u.%u.%u.%u\n",
               (e->next_hop_ip >> 24) & 0xFF, (e->next_hop_ip >> 16) & 0xFF,
               (e->next_hop_ip >> 8) & 0xFF, e->next_hop_ip & 0xFF);
        printf("  next_hop_port:  %u\n", e->next_hop_port);
        printf("  next_hop_qp:    %u\n", e->next_hop_qp);
        printf("  next_hop_mac:   %02x:%02x:%02x:%02x:%02x:%02x\n",
               e->next_hop_mac[0], e->next_hop_mac[1], e->next_hop_mac[2],
               e->next_hop_mac[3], e->next_hop_mac[4], e->next_hop_mac[5]);
        printf("\n");
    }
}
