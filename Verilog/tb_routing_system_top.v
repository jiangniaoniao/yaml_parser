`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/22 23:33:13
// Design Name: 
// Module Name: tb_routing_system_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_routing_system_top;

//=============================================================================
// Parameters
//=============================================================================
parameter CLK_PERIOD = 10;  // 100MHz clock
parameter MAX_HOSTS = 64;
parameter MAX_SWITCHES = 16;
parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter BIN_FILE = "fpga_config_routing.bin";
parameter ROM_DEPTH = 4096;  // 16KB

//=============================================================================
// Signals
//=============================================================================
reg                         clk;
reg                         rst_n;

wire [ADDR_WIDTH-1:0]       mem_addr;
wire [DATA_WIDTH-1:0]       mem_data;

reg                         start_init;
wire                        init_busy;
wire                        system_ready;

// Port A signals
reg                         req_a_valid;
reg                         req_a_type;
reg  [5:0]                  req_a_host_idx;
reg  [3:0]                  req_a_src_sw;
reg  [3:0]                  req_a_dst_sw;

wire                        resp_a_valid;
wire                        resp_a_type;
wire [31:0]                 resp_a_host_ip;
wire [31:0]                 resp_a_host_switch_id;
wire [31:0]                 resp_a_host_switch_ip;
wire [15:0]                 resp_a_host_port;
wire [15:0]                 resp_a_host_qp;
wire [47:0]                 resp_a_host_mac;
wire                        resp_a_path_valid;
wire [7:0]                  resp_a_path_next_hop;
wire [15:0]                 resp_a_path_out_port;
wire [15:0]                 resp_a_path_out_qp;
wire [15:0]                 resp_a_path_distance;
wire [31:0]                 resp_a_path_next_hop_ip;
wire [15:0]                 resp_a_path_next_hop_port;
wire [15:0]                 resp_a_path_next_hop_qp;

// Port B signals
reg                         req_b_valid;
reg                         req_b_type;
reg  [5:0]                  req_b_host_idx;
reg  [3:0]                  req_b_src_sw;
reg  [3:0]                  req_b_dst_sw;

wire                        resp_b_valid;
wire                        resp_b_type;
wire [31:0]                 resp_b_host_ip;
wire [31:0]                 resp_b_host_switch_id;
wire [31:0]                 resp_b_host_switch_ip;
wire [15:0]                 resp_b_host_port;
wire [15:0]                 resp_b_host_qp;
wire [47:0]                 resp_b_host_mac;
wire                        resp_b_path_valid;
wire [7:0]                  resp_b_path_next_hop;
wire [15:0]                 resp_b_path_out_port;
wire [15:0]                 resp_b_path_out_qp;
wire [15:0]                 resp_b_path_distance;
wire [31:0]                 resp_b_path_next_hop_ip;
wire [15:0]                 resp_b_path_next_hop_port;
wire [15:0]                 resp_b_path_next_hop_qp;

//=============================================================================
// Simulated ROM containing routing table binary data
//=============================================================================
reg [7:0] file_data [0:ROM_DEPTH-1];  // Byte-addressed storage
reg [31:0] actual_file_size;
reg file_loaded;

// Integer variables for file loading
integer i, fd, bytes_read, byte_val;

//=============================================================================
// Load binary file from fpga_config_routing.bin
//=============================================================================
initial begin
    // Initialize
    file_loaded = 1'b0;
    actual_file_size = 32'h0;

    // Wait a bit for reset
    #(CLK_PERIOD * 2);

    // Open binary file
    fd = $fopen(BIN_FILE, "rb");
    if (fd == 0) begin
        $display("[TB] ERROR: Cannot open file %s", BIN_FILE);
        $display("[TB] Please make sure fpga_config_routing.bin exists in the simulation directory");
        $finish;
    end

    // Read file byte by byte
    bytes_read = 0;
    while (!$feof(fd) && bytes_read < ROM_DEPTH) begin
        byte_val = $fgetc(fd);
        if (byte_val != -1) begin
            file_data[bytes_read] = byte_val[7:0];
            bytes_read = bytes_read + 1;
        end
    end
    $fclose(fd);

    actual_file_size = bytes_read;
    file_loaded = 1'b1;

    $display("[TB] ========== Binary File Loaded ==========");
    $display("[TB] File: %s", BIN_FILE);
    $display("[TB] Size: %0d bytes", actual_file_size);

    // Display first 32 bytes for debugging
    $display("[TB] First 32 bytes (Host Table Header + partial entry):");
    for (i = 0; i < 32; i = i + 4) begin
        if (i + 3 < actual_file_size) begin
            $display("[TB]   [%0d] 0x%08x", i,
                    {file_data[i+3], file_data[i+2], file_data[i+1], file_data[i]});
        end
    end
    $display("[TB] ============================================");
end

//=============================================================================
// Memory read logic - converts byte array to word data
//=============================================================================
reg [DATA_WIDTH-1:0] mem_data_reg;
always @(*) begin
    if (!rst_n) begin
        mem_data_reg = 32'h0;
    end else if (file_loaded && mem_addr < actual_file_size) begin
        if ((mem_addr + 3) < actual_file_size) begin
            // Read 4 bytes and form a 32-bit word (little-endian)
            mem_data_reg = {file_data[mem_addr+3], file_data[mem_addr+2],
                           file_data[mem_addr+1], file_data[mem_addr]};
        end else begin
            mem_data_reg = 32'h0;
        end
    end else begin
        mem_data_reg = 32'h0;
    end
end

assign mem_data = mem_data_reg;

//=============================================================================
// DUT Instantiation
//=============================================================================
routing_system_top #(
    .MAX_HOSTS          (MAX_HOSTS),
    .MAX_SWITCHES       (MAX_SWITCHES),
    .ADDR_WIDTH         (ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH),
    .HOST_ENTRY_WIDTH   (256),
    .PATH_ENTRY_WIDTH   (128)
) dut (
    .clk                        (clk),
    .rst_n                      (rst_n),

    .mem_addr                   (mem_addr),
    .mem_data                   (mem_data),

    .start_init                 (start_init),
    .init_busy                  (init_busy),
    .system_ready               (system_ready),

    .req_a_valid                (req_a_valid),
    .req_a_type                 (req_a_type),
    .req_a_host_idx             (req_a_host_idx),
    .req_a_src_sw               (req_a_src_sw),
    .req_a_dst_sw               (req_a_dst_sw),
    .resp_a_valid               (resp_a_valid),
    .resp_a_type                (resp_a_type),
    .resp_a_host_ip             (resp_a_host_ip),
    .resp_a_host_switch_id      (resp_a_host_switch_id),
    .resp_a_host_switch_ip      (resp_a_host_switch_ip),
    .resp_a_host_port           (resp_a_host_port),
    .resp_a_host_qp             (resp_a_host_qp),
    .resp_a_host_mac            (resp_a_host_mac),
    .resp_a_path_valid          (resp_a_path_valid),
    .resp_a_path_next_hop       (resp_a_path_next_hop),
    .resp_a_path_out_port       (resp_a_path_out_port),
    .resp_a_path_out_qp         (resp_a_path_out_qp),
    .resp_a_path_distance       (resp_a_path_distance),
    .resp_a_path_next_hop_ip    (resp_a_path_next_hop_ip),
    .resp_a_path_next_hop_port  (resp_a_path_next_hop_port),
    .resp_a_path_next_hop_qp    (resp_a_path_next_hop_qp),

    .req_b_valid                (req_b_valid),
    .req_b_type                 (req_b_type),
    .req_b_host_idx             (req_b_host_idx),
    .req_b_src_sw               (req_b_src_sw),
    .req_b_dst_sw               (req_b_dst_sw),
    .resp_b_valid               (resp_b_valid),
    .resp_b_type                (resp_b_type),
    .resp_b_host_ip             (resp_b_host_ip),
    .resp_b_host_switch_id      (resp_b_host_switch_id),
    .resp_b_host_switch_ip      (resp_b_host_switch_ip),
    .resp_b_host_port           (resp_b_host_port),
    .resp_b_host_qp             (resp_b_host_qp),
    .resp_b_host_mac            (resp_b_host_mac),
    .resp_b_path_valid          (resp_b_path_valid),
    .resp_b_path_next_hop       (resp_b_path_next_hop),
    .resp_b_path_out_port       (resp_b_path_out_port),
    .resp_b_path_out_qp         (resp_b_path_out_qp),
    .resp_b_path_distance       (resp_b_path_distance),
    .resp_b_path_next_hop_ip    (resp_b_path_next_hop_ip),
    .resp_b_path_next_hop_port  (resp_b_path_next_hop_port),
    .resp_b_path_next_hop_qp    (resp_b_path_next_hop_qp)
);

//=============================================================================
// Clock Generation
//=============================================================================
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

//=============================================================================
// Test Stimulus
//=============================================================================
initial begin
    // Initialize signals
    rst_n = 0;
    start_init = 0;
    req_a_valid = 0;
    req_a_type = 0;
    req_a_host_idx = 0;
    req_a_src_sw = 0;
    req_a_dst_sw = 0;
    req_b_valid = 0;
    req_b_type = 0;
    req_b_host_idx = 0;
    req_b_src_sw = 0;
    req_b_dst_sw = 0;

    // Wait for file to load
    wait(file_loaded);

    // Reset
    #(CLK_PERIOD * 5);
    rst_n = 1;
    $display("\n[TB] ========== Test Start ==========");

    // Start initialization
    #(CLK_PERIOD * 2);
    start_init = 1;
    $display("[TB] Starting initialization at time %0t", $time);
    #CLK_PERIOD;
    start_init = 0;

    // Wait for initialization to complete
    wait(system_ready);
    #(CLK_PERIOD * 10);  // Increase wait time after initialization
    $display("[TB] Initialization complete at time %0t\n", $time);

    // ========== Test Host Lookups ==========
    $display("[TB] ========== Testing Host Lookups ==========");

    // Lookup Host 0
    #(CLK_PERIOD * 5);
    $display("[TB] Sending Host 0 lookup request at time %0t", $time);
    req_a_valid = 1;
    req_a_type = 0;  // Host lookup
    req_a_host_idx = 0;
    #CLK_PERIOD;
    req_a_valid = 0;

    // Wait for response (3 cycles pipeline + 1 cycle to sample)
    #(CLK_PERIOD * 4);
    $display("[TB] Host 0 Lookup Result:");
    $display("     IP: %d.%d.%d.%d (0x%08x)",
             resp_a_host_ip[31:24], resp_a_host_ip[23:16],
             resp_a_host_ip[15:8], resp_a_host_ip[7:0], resp_a_host_ip);
    $display("     Switch ID: %d", resp_a_host_switch_id);
    $display("     Port: %d, QP: %d", resp_a_host_port, resp_a_host_qp);
    $display("     MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             resp_a_host_mac[47:40], resp_a_host_mac[39:32],
             resp_a_host_mac[31:24], resp_a_host_mac[23:16],
             resp_a_host_mac[15:8], resp_a_host_mac[7:0]);

    // Lookup Host 2
    #(CLK_PERIOD * 5);
    $display("[TB] Sending Host 2 lookup request at time %0t", $time);
    req_a_valid = 1;
    req_a_type = 0;
    req_a_host_idx = 2;
    #CLK_PERIOD;
    req_a_valid = 0;

    #(CLK_PERIOD * 4);
    $display("[TB] Host 2 Lookup Result:");
    $display("     IP: %d.%d.%d.%d (0x%08x)",
             resp_a_host_ip[31:24], resp_a_host_ip[23:16],
             resp_a_host_ip[15:8], resp_a_host_ip[7:0], resp_a_host_ip);
    $display("     Switch ID: %d, Port: %d, QP: %d",
             resp_a_host_switch_id, resp_a_host_port, resp_a_host_qp);

    // ========== Test Path Lookups ==========
    $display("\n[TB] ========== Testing Path Lookups ==========");

    // Lookup Path 1→2
    #(CLK_PERIOD * 5);
    $display("[TB] Sending Path [1→2] lookup request at time %0t", $time);
    req_a_valid = 1;
    req_a_type = 1;  // Path lookup
    req_a_src_sw = 1;
    req_a_dst_sw = 2;
    #CLK_PERIOD;
    req_a_valid = 0;

    #(CLK_PERIOD * 4);
    $display("[TB] Path [1→2] Lookup Result:");
    $display("     Valid: %d", resp_a_path_valid);
    $display("     Next Hop: %d", resp_a_path_next_hop);
    $display("     Out Port: %d, Out QP: %d", resp_a_path_out_port, resp_a_path_out_qp);
    $display("     Distance: %d", resp_a_path_distance);
    $display("     Next Hop IP: 0x%08x", resp_a_path_next_hop_ip);

    // Lookup Path 2→3
    #(CLK_PERIOD * 5);
    $display("[TB] Sending Path [2→3] lookup request at time %0t", $time);
    req_a_valid = 1;
    req_a_type = 1;
    req_a_src_sw = 2;
    req_a_dst_sw = 3;
    #CLK_PERIOD;
    req_a_valid = 0;

    #(CLK_PERIOD * 4);
    $display("[TB] Path [2→3] Lookup Result:");
    $display("     Valid: %d, Next Hop: %d", resp_a_path_valid, resp_a_path_next_hop);
    $display("     Distance: %d", resp_a_path_distance);

    // ========== Test Dual-Port Concurrent Lookups ==========
    $display("\n[TB] ========== Testing Dual-Port Concurrent Lookups ==========");

    #(CLK_PERIOD * 5);
    $display("[TB] Sending concurrent lookups at time %0t", $time);
    // Port A: Host lookup
    req_a_valid = 1;
    req_a_type = 0;
    req_a_host_idx = 1;

    // Port B: Path lookup (concurrent)
    req_b_valid = 1;
    req_b_type = 1;
    req_b_src_sw = 3;
    req_b_dst_sw = 1;

    #CLK_PERIOD;
    req_a_valid = 0;
    req_b_valid = 0;

    // Wait for both responses (3 cycles pipeline + 1 cycle to sample)
    #(CLK_PERIOD * 4);
    $display("[TB] Concurrent Lookup Results:");
    $display("     Port A (Host 1): IP=0x%08x, Switch=%d",
             resp_a_host_ip, resp_a_host_switch_id);
    $display("     Port B (Path 3→1): Next Hop=%d, Distance=%d",
             resp_b_path_next_hop, resp_b_path_distance);

    // ========== Test Complete ==========
    #(CLK_PERIOD * 10);
    $display("\n[TB] ========== All Tests Passed ==========\n");
    $finish;
end

//=============================================================================
// Timeout Watchdog
//=============================================================================
initial begin
    #(CLK_PERIOD * 10000);
    $display("[TB] ERROR: Simulation timeout!");
    $finish;
end

//=============================================================================
// Optional: Waveform Dump
//=============================================================================
initial begin
    $dumpfile("tb_routing_system_top.vcd");
    $dumpvars(0, tb_routing_system_top);
end

endmodule


