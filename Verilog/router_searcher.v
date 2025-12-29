`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/26 15:32:37
// Design Name: 
// Module Name: router_searcher
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


module router_searcher #(
    parameter MAX_ENTRIES = 64,        // 最大路由表条目数
    parameter ENTRY_WIDTH = 256,       // Entry宽度（32字节=256位）
    parameter IP_WIDTH = 32            // IP地址宽度
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // 初始化接口
    input  wire                     init_mode,
    input  wire [ENTRY_WIDTH-1:0]   init_entry_data,
    input  wire [5:0]               init_entry_addr,
    input  wire                     init_entry_wr,

    // 查找接口
    input  wire                     lookup_valid,
    input  wire [IP_WIDTH-1:0]      lookup_dst_ip,

    // 响应接口（3 cycle延迟）
    output reg                      resp_valid,
    output reg                      resp_found,
    output reg [15:0]               resp_out_port,
    output reg [15:0]               resp_out_qp,
    output reg [31:0]               resp_next_hop_ip,
    output reg [15:0]               resp_next_hop_port,
    output reg [15:0]               resp_next_hop_qp,
    output reg [47:0]               resp_next_hop_mac,
    output reg                      resp_is_direct_host,
    output reg                      resp_is_broadcast
);

// ============ 存储模块 ============

// IP键数组
(* ram_style = "distributed" *)
reg [IP_WIDTH-1:0] ip_keys [0:MAX_ENTRIES-1];
reg                key_valid [0:MAX_ENTRIES-1];

// 完整Entry数组
(* ram_style = "block" *)
reg [ENTRY_WIDTH-1:0] dest_table [0:MAX_ENTRIES-1];

// 初始化逻辑
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < MAX_ENTRIES; i = i + 1) begin
            key_valid[i] <= 1'b0;
            ip_keys[i] <= 32'h0;
            dest_table[i] <= {ENTRY_WIDTH{1'b0}};
        end
    end else if (init_mode && init_entry_wr) begin
        // 写入IP键和完整Entry
        ip_keys[init_entry_addr] <= init_entry_data[31:0];  // dst_ip在[31:0]
        key_valid[init_entry_addr] <= init_entry_data[32];  // valid位在[32]
        dest_table[init_entry_addr] <= init_entry_data;
    end
end

// ============ Stage 1: CAM并行查找 ============

// 并行比较器阵列
wire [MAX_ENTRIES-1:0] match_vector;
genvar g;
generate
    for (g = 0; g < MAX_ENTRIES; g = g + 1) begin: cam_comparators
        assign match_vector[g] = key_valid[g] && (ip_keys[g] == lookup_dst_ip);
    end
endgenerate

// 优先编码器（One-hot → Binary index）
reg [5:0] match_idx;
reg       match_found;
integer j;
always @(*) begin
    match_found = 1'b0;
    match_idx = 6'd0;

    for (j = 0; j < MAX_ENTRIES; j = j + 1) begin
        if (match_vector[j]) begin
            match_found = 1'b1;
            match_idx = j[5:0];
        end
    end
end

// Stage 1寄存器
reg        lookup_valid_s1;
reg [5:0]  match_idx_s1;
reg        match_found_s1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lookup_valid_s1 <= 1'b0;
        match_idx_s1 <= 6'd0;
        match_found_s1 <= 1'b0;
    end else begin
        // 只在非初始化模式时接受新查询
        lookup_valid_s1 <= (!init_mode) ? lookup_valid : 1'b0;
        match_idx_s1 <= match_idx;
        match_found_s1 <= match_found;
    end
end

// ============ Stage 2: BRAM读取 ============

// BRAM读取
reg [ENTRY_WIDTH-1:0] entry_data_s2;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        entry_data_s2 <= {ENTRY_WIDTH{1'b0}};
    end else if (lookup_valid_s1 && match_found_s1) begin
        entry_data_s2 <= dest_table[match_idx_s1];
    end
end

// Stage 2 流水线寄存器（传递valid和found信号）
reg        lookup_valid_s2;
reg        match_found_s2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lookup_valid_s2 <= 1'b0;
        match_found_s2 <= 1'b0;
    end else begin
        // 流水线传递，不受init_mode影响
        lookup_valid_s2 <= lookup_valid_s1;
        match_found_s2 <= match_found_s1;
    end
end

// ============ Stage 3: 解析并输出 ============

// Stage 3输出寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_valid <= 1'b0;
        resp_found <= 1'b0;
        resp_out_port <= 16'h0;
        resp_out_qp <= 16'h0;
        resp_next_hop_ip <= 32'h0;
        resp_next_hop_port <= 16'h0;
        resp_next_hop_qp <= 16'h0;
        resp_next_hop_mac <= 48'h0;
        resp_is_direct_host <= 1'b0;
        resp_is_broadcast <= 1'b0;
    end else begin
        // 只在非初始化模式时输出有效结果
        resp_valid <= lookup_valid_s2 && !init_mode;
        resp_found <= match_found_s2;

        if (match_found_s2) begin
            // 解析Entry字段（根据fpga_dest_entry_t结构，小端序）
            resp_out_port       <= entry_data_s2[79:64];
            resp_out_qp         <= entry_data_s2[95:80];
            resp_next_hop_ip    <= entry_data_s2[127:96];
            resp_next_hop_port  <= entry_data_s2[143:128];
            resp_next_hop_qp    <= entry_data_s2[159:144];
            resp_next_hop_mac   <= entry_data_s2[207:160];
            resp_is_direct_host <= entry_data_s2[40];
            resp_is_broadcast   <= entry_data_s2[48];
        end else begin
            resp_out_port       <= 16'h0;
            resp_out_qp         <= 16'h0;
            resp_next_hop_ip    <= 32'h0;
            resp_next_hop_port  <= 16'h0;
            resp_next_hop_qp    <= 16'h0;
            resp_next_hop_mac   <= 48'h0;
            resp_is_direct_host <= 1'b0;
            resp_is_broadcast   <= 1'b0;
        end
    end
end

endmodule
