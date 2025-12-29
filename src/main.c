#include "../include/yaml2fpga.h"
#include <getopt.h>

void print_usage(const char* program_name) {
    printf("用法: %s [选项] YAML文件 [输出文件]\n\n", program_name);
    printf("YAML到FPGA配置转换器\n\n");
    printf("参数:\n");
    printf("  YAML文件    YAML拓扑配置文件路径\n");
    printf("  输出文件    FPGA二进制输出文件 (默认: fpga_routing.bin)\n\n");
    printf("选项:\n");
    printf("  -s, --summary   只显示拓扑摘要\n");
    printf("  -h, --help      显示此帮助信息\n\n");
    printf("示例:\n");
    printf("  %s topology-tree.yaml\n", program_name);
    printf("  %s topology-tree.yaml my_routing.bin\n", program_name);
    printf("  %s --summary topology-tree.yaml\n", program_name);
}

// 基本拓扑验证
static int validate_basic_topology(const topology_config_t* config) {
    if (!config || config->switch_count == 0) {
        return ERR_INVALID_CONFIG;
    }

    int root_count = 0;
    for (uint32_t i = 0; i < config->switch_count; i++) {
        if (config->switches[i].is_root) {
            root_count++;
        }
    }

    if (root_count != 1) {
        printf("错误: 必须有且仅有一个根交换机 (找到 %d 个)\n", root_count);
        return ERR_INVALID_CONFIG;
    }

    return SUCCESS;
}

int main(int argc, char* argv[]) {
    char* yaml_file = NULL;
    char* output_file = "fpga_routing.bin";
    bool summary_only = false;
    bool show_help = false;

    // 解析命令行参数
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"summary", no_argument, 0, 's'},
        {0, 0, 0, 0}
    };

    int option_index = 0;
    int c;

    while ((c = getopt_long(argc, argv, "hs", long_options, &option_index)) != -1) {
        switch (c) {
            case 'h':
                show_help = true;
                break;
            case 's':
                summary_only = true;
                break;
            case '?':
                fprintf(stderr, "使用 --help 查看帮助信息。\n");
                return 1;
        }
    }

    if (show_help) {
        print_usage(argv[0]);
        return 0;
    }

    if (optind >= argc) {
        fprintf(stderr, "错误: 未指定YAML文件\n\n");
        print_usage(argv[0]);
        return 1;
    }

    yaml_file = argv[optind];
    if (optind + 1 < argc) {
        output_file = argv[optind + 1];
    }

    printf("=== YAML到FPGA配置转换器 ===\n");
    printf("输入: %s\n", yaml_file);
    if (!summary_only) {
        printf("输出: %s\n", output_file);
    }
    printf("\n");

    // 步骤1: 解析YAML
    printf("解析YAML文件...\n");
    topology_config_t config;
    int result = parse_yaml_topology(yaml_file, &config);
    if (result != SUCCESS) {
        fprintf(stderr, "错误: YAML解析失败 (错误码: %d)\n", result);
        return 1;
    }

    // 步骤2: 显示摘要
    print_topology_summary(&config);

    if (summary_only) {
        cleanup_topology(&config);
        return 0;
    }

    // 步骤3: 基本验证
    printf("\n验证拓扑...\n");
    result = validate_basic_topology(&config);
    if (result != SUCCESS) {
        fprintf(stderr, "错误: 验证失败 (错误码: %d)\n", result);
        cleanup_topology(&config);
        return 1;
    }

    printf("验证通过\n\n");

    // 步骤4: 生成统一路由表
    printf("生成统一路由表...\n");
    result = generate_unified_routing_binary(&config, output_file);
    if (result != SUCCESS) {
        fprintf(stderr, "错误: 生成统一路由表失败 (错误码: %d)\n", result);
        cleanup_topology(&config);
        return 1;
    }

    printf("统一路由表已生成: %s\n\n", output_file);

    // 清理
    cleanup_topology(&config);

    printf("=== 转换完成 ===\n");
    printf("生成的文件:\n");
    printf("  - %s - 统一路由表\n", output_file);

    return 0;
}
