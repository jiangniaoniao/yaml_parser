#include "../include/yaml2fpga.h"
#include <getopt.h>

void print_usage(const char* program_name) {
    printf("Usage: %s [OPTIONS] YAML_FILE [OUTPUT_FILE]\n\n", program_name);
    printf("YAML to FPGA Configuration Converter\n\n");
    printf("Arguments:\n");
    printf("  YAML_FILE    Path to YAML topology configuration file\n");
    printf("  OUTPUT_FILE  Output binary file for FPGA (default: fpga_config.bin)\n\n");
    printf("Options:\n");
    printf("  -s, --summary   Show topology summary only\n");
    printf("  -h, --help     Show this help message\n\n");
    printf("Examples:\n");
    printf("  %s topology-tree.yaml\n", program_name);
    printf("  %s topology-tree.yaml my_config.bin\n", program_name);
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
    
    // Parse arguments
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
    
    printf("=== YAML to FPGA Configuration Converter ===\n");
    printf("Input: %s\n", yaml_file);
    if (!summary_only) {
        printf("Output: %s\n", output_file);
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
    
    // Step 5: Write to file
    printf("Writing FPGA binary file...\n");
    result = write_fpga_binary(output_file, fpga_data, fpga_size);
    if (result != SUCCESS) {
        fprintf(stderr, "Error: Failed to write output file (code: %d)\n", result);
        free(fpga_data);
        cleanup_topology(&config);
        return 1;
    }
    
    printf("FPGA configuration written to: %s\n", output_file);
    
    // Cleanup
    free(fpga_data);
    cleanup_topology(&config);
    
    printf("\n=== Conversion Complete ===\n");
    return 0;
}