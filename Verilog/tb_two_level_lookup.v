`timescale 1ns / 1ps
//=============================================================================
// Testbench for Two-Level Auto Lookup
//=============================================================================

module tb_two_level_lookup;

//=============================================================================
// Parameters
//=============================================================================
parameter CLK_PERIOD = 10;
parameter MAX_HOSTS = 64;
parameter MAX_SWITCHES = 16;
parameter ADDR_WIDTH = 32;
parameter DATA_WIDTH = 32;
parameter BIN_FILE = "fpga_config_routing.bin";
parameter ROM_DEPTH = 4096;
parameter HOST_ENTRY_WIDTH = 192;
parameter PATH_ENTRY_WIDTH = 192;

//=============================================================================
// Signals
//=============================================================================
reg                         clk;
reg                         rst_n;
wire [ADDR_WIDTH-1:0]       mem_addr;
reg  [DATA_WIDTH-1:0]       mem_data;
reg                         start_init;
wire                        init_busy;
wire                        system_ready;

// Port A signals (Auto two-level lookup)
reg                         req_a_valid;
reg  [3:0]                  req_a_src_sw;
reg  [5:0]                  req_a_dst_host;

wire                        resp_a_valid;
wire                        resp_a_path_valid;
wire [15:0]                 resp_a_path_out_port;
wire [15:0]                 resp_a_path_out_qp;
wire [31:0]                 resp_a_path_next_hop_ip;
wire [15:0]                 resp_a_path_next_hop_port;
wire [15:0]                 resp_a_path_next_hop_qp;
wire [47:0]                 resp_a_path_next_hop_mac;

// Port B signals (原有功能，保留用于对比测试)
reg                         req_b_valid;
reg                         req_b_type;
reg  [5:0]                  req_b_host_idx;
reg  [3:0]                  req_b_src_sw;
reg  [3:0]                  req_b_dst_sw;

wire                        resp_b_valid;
wire                        resp_b_type;
wire [31:0]                 resp_b_host_ip;
wire [31:0]                 resp_b_host_switch_id;
wire [15:0]                 resp_b_host_port;
wire [15:0]                 resp_b_host_qp;
wire [47:0]                 resp_b_host_mac;
wire                        resp_b_path_valid;
wire [15:0]                 resp_b_path_out_port;
wire [15:0]                 resp_b_path_out_qp;
wire [31:0]                 resp_b_path_next_hop_ip;
wire [15:0]                 resp_b_path_next_hop_port;
wire [15:0]                 resp_b_path_next_hop_qp;
wire [47:0]                 resp_b_path_next_hop_mac;

//=============================================================================
// ROM and File Loading
//=============================================================================
reg [7:0] file_data [0:ROM_DEPTH-1];
reg [31:0] actual_file_size;
reg file_loaded;
integer i, fd, bytes_read, byte_val;

initial begin
    file_loaded = 1'b0;
    actual_file_size = 32'h0;
    #(CLK_PERIOD * 2);

    fd = $fopen(BIN_FILE, "rb");
    if (fd == 0) begin
        $display("[TB] ERROR: Cannot open file %s", BIN_FILE);
        $finish;
    end

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
    $display("[TB] Loaded %d bytes from %s", bytes_read, BIN_FILE);
end

// Memory interface
assign mem_addr_word = mem_addr[ADDR_WIDTH-1:2];
wire [ADDR_WIDTH-3:0] mem_addr_word;

always @(*) begin
    if (mem_addr < actual_file_size) begin
        mem_data = {file_data[mem_addr_word*4 + 3],
                    file_data[mem_addr_word*4 + 2],
                    file_data[mem_addr_word*4 + 1],
                    file_data[mem_addr_word*4]};
    end else begin
        mem_data = 32'h0;
    end
end

//=============================================================================
// DUT Instantiation
//=============================================================================
routing_system_top #(
    .MAX_HOSTS          (MAX_HOSTS),
    .MAX_SWITCHES       (MAX_SWITCHES),
    .ADDR_WIDTH         (ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH),
    .HOST_ENTRY_WIDTH   (HOST_ENTRY_WIDTH),
    .PATH_ENTRY_WIDTH   (PATH_ENTRY_WIDTH)
) dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .mem_addr                   (mem_addr),
    .mem_data                   (mem_data),
    .start_init                 (start_init),
    .init_busy                  (init_busy),
    .system_ready               (system_ready),

    .req_a_valid                (req_a_valid),
    .req_a_src_sw               (req_a_src_sw),
    .req_a_dst_host             (req_a_dst_host),
    .resp_a_valid               (resp_a_valid),
    .resp_a_path_valid          (resp_a_path_valid),
    .resp_a_path_out_port       (resp_a_path_out_port),
    .resp_a_path_out_qp         (resp_a_path_out_qp),
    .resp_a_path_next_hop_ip    (resp_a_path_next_hop_ip),
    .resp_a_path_next_hop_port  (resp_a_path_next_hop_port),
    .resp_a_path_next_hop_qp    (resp_a_path_next_hop_qp),
    .resp_a_path_next_hop_mac   (resp_a_path_next_hop_mac),

    .req_b_valid                (req_b_valid),
    .req_b_type                 (req_b_type),
    .req_b_host_idx             (req_b_host_idx),
    .req_b_src_sw               (req_b_src_sw),
    .req_b_dst_sw               (req_b_dst_sw),
    .resp_b_valid               (resp_b_valid),
    .resp_b_type                (resp_b_type),
    .resp_b_host_ip             (resp_b_host_ip),
    .resp_b_host_switch_id      (resp_b_host_switch_id),
    .resp_b_host_port           (resp_b_host_port),
    .resp_b_host_qp             (resp_b_host_qp),
    .resp_b_host_mac            (resp_b_host_mac),
    .resp_b_path_valid          (resp_b_path_valid),
    .resp_b_path_out_port       (resp_b_path_out_port),
    .resp_b_path_out_qp         (resp_b_path_out_qp),
    .resp_b_path_next_hop_ip    (resp_b_path_next_hop_ip),
    .resp_b_path_next_hop_port  (resp_b_path_next_hop_port),
    .resp_b_path_next_hop_qp    (resp_b_path_next_hop_qp),
    .resp_b_path_next_hop_mac   (resp_b_path_next_hop_mac)
);

//=============================================================================
// Clock Generation
//=============================================================================
always #(CLK_PERIOD/2) clk = ~clk;

//=============================================================================
// Test Sequence
//=============================================================================
initial begin
    // Initialize
    clk = 0;
    rst_n = 0;
    start_init = 0;
    req_a_valid = 0;
    req_a_src_sw = 0;
    req_a_dst_host = 0;
    req_b_valid = 0;
    req_b_type = 0;
    req_b_host_idx = 0;
    req_b_src_sw = 0;
    req_b_dst_sw = 0;

    wait(file_loaded);

    // Reset
    #(CLK_PERIOD * 5);
    rst_n = 1;
    $display("\n[TB] ========== 自动两级查表测试 ==========");

    // Start initialization
    #(CLK_PERIOD * 2);
    start_init = 1;
    $display("[TB] 开始初始化...");
    #CLK_PERIOD;
    start_init = 0;

    // Wait for initialization
    wait(system_ready);
    #(CLK_PERIOD * 10);
    $display("[TB] 初始化完成\n");

    // ========== 测试1：Switch 1 → Host 0 ==========
    $display("[TB] ========== 测试1：Switch 1 发送到 Host 0 ==========");
    $display("[TB] 预期：Host 0在Switch 2上，应该返回路径1→2的转发信息");
    #(CLK_PERIOD * 5);
    req_a_valid = 1;
    req_a_src_sw = 1;     // 当前在Switch 1
    req_a_dst_host = 0;   // 目标是Host 0
    #CLK_PERIOD;
    req_a_valid = 0;

    // 等待5个周期pipeline（Stage 0-4）
    #(CLK_PERIOD * 5);
    $display("[TB] 结果：");
    $display("     响应有效: %d, 路径有效: %d", resp_a_valid, resp_a_path_valid);
    $display("     输出端口: %d, 输出QP: %d", resp_a_path_out_port, resp_a_path_out_qp);
    $display("     下一跳IP: 0x%08x, 端口: %d, QP: %d",
             resp_a_path_next_hop_ip, resp_a_path_next_hop_port, resp_a_path_next_hop_qp);
    $display("     下一跳MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             resp_a_path_next_hop_mac[47:40], resp_a_path_next_hop_mac[39:32],
             resp_a_path_next_hop_mac[31:24], resp_a_path_next_hop_mac[23:16],
             resp_a_path_next_hop_mac[15:8], resp_a_path_next_hop_mac[7:0]);

    // ========== 测试2：Switch 2 → Host 2 ==========
    $display("\n[TB] ========== 测试2：Switch 2 发送到 Host 2 ==========");
    $display("[TB] 预期：Host 2在Switch 3上，应该返回路径2→3的转发信息");
    #(CLK_PERIOD * 5);
    req_a_valid = 1;
    req_a_src_sw = 2;
    req_a_dst_host = 2;
    #CLK_PERIOD;
    req_a_valid = 0;

    #(CLK_PERIOD * 5);
    $display("[TB] 结果：");
    $display("     响应有效: %d, 路径有效: %d", resp_a_valid, resp_a_path_valid);
    $display("     输出端口: %d, 输出QP: %d", resp_a_path_out_port, resp_a_path_out_qp);
    $display("     下一跳MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             resp_a_path_next_hop_mac[47:40], resp_a_path_next_hop_mac[39:32],
             resp_a_path_next_hop_mac[31:24], resp_a_path_next_hop_mac[23:16],
             resp_a_path_next_hop_mac[15:8], resp_a_path_next_hop_mac[7:0]);

    // ========== 测试3：Switch 3 → Host 1 ==========
    $display("\n[TB] ========== 测试3：Switch 3 发送到 Host 1 ==========");
    $display("[TB] 预期：Host 1在Switch 2上，应该返回路径3→2的转发信息");
    #(CLK_PERIOD * 5);
    req_a_valid = 1;
    req_a_src_sw = 3;
    req_a_dst_host = 1;
    #CLK_PERIOD;
    req_a_valid = 0;

    #(CLK_PERIOD * 5);
    $display("[TB] 结果：");
    $display("     响应有效: %d, 路径有效: %d", resp_a_valid, resp_a_path_valid);
    $display("     输出端口: %d, 输出QP: %d", resp_a_path_out_port, resp_a_path_out_qp);

    // ========== 完成 ==========
    #(CLK_PERIOD * 10);
    $display("\n[TB] ========== 所有测试完成 ==========\n");
    $finish;
end

endmodule
