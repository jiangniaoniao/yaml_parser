#include "../include/yaml2fpga.h"
#include <getopt.h>

// 生成路由表文件名
// 例如：fpga_config.bin -> fpga_routing.bin
//      my_config.bin -> my_routing.bin
static void generate_routing_filename(const char* config_filename, char* routing_filename, size_t size) {
    const char* dot = strrchr(config_filename, '.');
    const char* slash = strrchr(config_filename, '/');

    if (dot && (!slash || dot > slash)) {
        // 有扩展名
        size_t prefix_len = dot - config_filename;
        snprintf(routing_filename, size, "%.*s_routing%s", (int)prefix_len, config_filename, dot);
    } else {
        // 没有扩展名
        snprintf(routing_filename, size, "%s_routing.bin", config_filename);
    }
}

void print_usage(const char* program_name) {
    printf("Usage: %s [OPTIONS] YAML_FILE [OUTPUT_FILE]\n\n", program_name);
    printf("YAML to FPGA Configuration Converter\n\n");
    printf("Arguments:\n");
    printf("  YAML_FILE    Path to YAML topology configuration file\n");
    printf("  OUTPUT_FILE  Output binary file for FPGA (default: fpga_config.bin)\n\n");
    printf("Options:\n");
    printf("  -u, --unified   Use unified routing table (方案3优化) [NEW!]\n");
    printf("  -s, --summary   Show topology summary only\n");
    printf("  -h, --help      Show this help message\n\n");
    printf("Examples:\n");
    printf("  %s topology-tree.yaml                    # 传统两级路由表\n", program_name);
    printf("  %s --unified topology-tree.yaml          # 统一路由表（推荐）\n", program_name);
    printf("  %s -u topology-tree.yaml my_config.bin   # 统一路由表+自定义输出\n", program_name);
    printf("  %s --summary topology-tree.yaml\n", program_name);
}

// Simple validation
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
        printf("Error: Must have exactly one root switch (found %d)\n", root_count);
        return ERR_INVALID_CONFIG;
    }
    
    return SUCCESS;
}

int main(int argc, char* argv[]) {
    char* yaml_file = NULL;
    char* output_file = "fpga_config.bin";
    bool summary_only = false;
    bool show_help = false;
    bool use_unified = false;  // 新增：是否使用统一路由表

    // Parse arguments
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"summary", no_argument, 0, 's'},
        {"unified", no_argument, 0, 'u'},  // 新增选项
        {0, 0, 0, 0}
    };

    int option_index = 0;
    int c;

    while ((c = getopt_long(argc, argv, "hsu", long_options, &option_index)) != -1) {
        switch (c) {
            case 'h':
                show_help = true;
                break;
            case 's':
                summary_only = true;
                break;
            case 'u':
                use_unified = true;  // 启用统一路由表
                break;
            case '?':
                fprintf(stderr, "Use --help for usage information.\n");
                return 1;
        }
    }
    
    if (show_help) {
        print_usage(argv[0]);
        return 0;
    }
    
    if (optind >= argc) {
        fprintf(stderr, "Error: YAML file not specified\n\n");
        print_usage(argv[0]);
        return 1;
    }
    
    yaml_file = argv[optind];
    if (optind + 1 < argc) {
        output_file = argv[optind + 1];
    }

    // 生成路由表文件名
    char routing_file[256];
    generate_routing_filename(output_file, routing_file, sizeof(routing_file));

    printf("=== YAML to FPGA Configuration Converter ===\n");
    printf("Mode: %s\n", use_unified ? "统一路由表 (Unified Routing Table)" : "传统两级路由表 (Legacy Two-Level)");
    printf("Input: %s\n", yaml_file);
    if (!summary_only) {
        printf("Output (Connections): %s\n", output_file);
        printf("Output (Routing Table): %s\n", routing_file);
    }
    printf("\n");
    
    // Step 1: Parse YAML
    printf("Parsing YAML file...\n");
    topology_config_t config;
    int result = parse_yaml_topology(yaml_file, &config);
    if (result != SUCCESS) {
        fprintf(stderr, "Error: Failed to parse YAML (code: %d)\n", result);
        return 1;
    }
    
    // Step 2: Show summary
    print_topology_summary(&config);
    
    if (summary_only) {
        cleanup_topology(&config);
        return 0;
    }
    
    // Step 3: Basic validation
    printf("\nValidating topology...\n");
    result = validate_basic_topology(&config);
    if (result != SUCCESS) {
        fprintf(stderr, "Error: Validation failed (code: %d)\n", result);
        cleanup_topology(&config);
        return 1;
    }
    
    printf("Validation passed\n\n");
    
    // Step 4: Convert to FPGA format
    printf("Converting to FPGA format...\n");
    uint8_t* fpga_data = NULL;
    size_t fpga_size = 0;
    
    result = convert_to_fpga_format(&config, &fpga_data, &fpga_size);
    if (result != SUCCESS) {
        fprintf(stderr, "Error: Conversion failed (code: %d)\n", result);
        cleanup_topology(&config);
        return 1;
    }
    
    printf("Conversion completed (%zu bytes)\n\n", fpga_size);

    // Step 5: Build routing tables
    if (use_unified) {
        // ========== 新版：统一路由表 ==========
        printf("Building unified routing tables (方案3优化)...\n");
        result = generate_unified_routing_binary(&config, routing_file);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to generate unified routing table (code: %d)\n", result);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }
        printf("Unified routing table generated: %s\n\n", routing_file);

        // Step 6: Write connection config file
        printf("Writing connection configuration file...\n");
        result = write_fpga_binary(output_file, fpga_data, fpga_size);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to write connection config file (code: %d)\n", result);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }
        printf("Connection configuration written to: %s\n", output_file);

    } else {
        // ========== 旧版：两级路由表 ==========
        printf("Building routing tables...\n");
        fpga_host_entry_t* host_table = NULL;
        fpga_switch_path_entry_t* switch_path_table = NULL;
        uint32_t host_count = 0;
        uint32_t switch_count = 0;
        uint32_t max_switch_id = 0;

        result = build_routing_tables(&config, &host_table, &host_count,
                                       &switch_path_table, &switch_count, &max_switch_id);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to build routing tables (code: %d)\n", result);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }

        printf("Routing tables built successfully\n");
        printf("  - Host entries: %u\n", host_count);
        printf("  - Switch path table: %u × %u entries\n", max_switch_id + 1, max_switch_id + 1);

        // Print routing tables
        print_routing_tables(host_table, host_count, switch_path_table, switch_count, max_switch_id);

        // Step 6: Generate routing table binary
        printf("\nGenerating routing table binary...\n");
        uint8_t* routing_data = NULL;
        size_t routing_size = 0;

        result = generate_routing_table_binary(&routing_data, &routing_size,
                                               host_table, host_count,
                                               switch_path_table, switch_count, max_switch_id);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to generate routing table binary (code: %d)\n", result);
            free(host_table);
            free(switch_path_table);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }

        printf("Routing table binary size: %zu bytes\n\n", routing_size);

        // Step 7: Write connection config file
        printf("Writing connection configuration file...\n");
        result = write_fpga_binary(output_file, fpga_data, fpga_size);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to write connection config file (code: %d)\n", result);
            free(routing_data);
            free(host_table);
            free(switch_path_table);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }

        printf("Connection configuration written to: %s\n", output_file);

        // Step 8: Write routing table file
        printf("Writing routing table file...\n");
        result = write_routing_table_binary(routing_file, routing_data, routing_size);
        if (result != SUCCESS) {
            fprintf(stderr, "Error: Failed to write routing table file (code: %d)\n", result);
            free(routing_data);
            free(host_table);
            free(switch_path_table);
            free(fpga_data);
            cleanup_topology(&config);
            return 1;
        }

        printf("Routing table written to: %s\n", routing_file);

        // Cleanup
        free(routing_data);
        free(host_table);
        free(switch_path_table);
    }
    free(fpga_data);
    cleanup_topology(&config);

    printf("\n=== Conversion Complete ===\n");
    printf("Generated files:\n");
    printf("  - %s (%zu bytes) - Connection configuration\n", output_file, fpga_size);
    if (use_unified) {
        printf("  - %s - Unified routing table (方案3优化)\n", routing_file);
    } else {
        printf("  - %s - Legacy two-level routing table\n", routing_file);
    }
    return 0;
}