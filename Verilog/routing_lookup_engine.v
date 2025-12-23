`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/22 23:29:55
// Design Name: 
// Module Name: routing_lookup_table_engine
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


module routing_lookup_engine #(
    parameter MAX_HOSTS = 64,
    parameter MAX_SWITCHES = 16,
    parameter HOST_ENTRY_WIDTH = 256,    // 32 bytes = 256 bits
    parameter PATH_ENTRY_WIDTH = 128     // 16 bytes = 128 bits
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // ========== Initialization Interface (One-time at startup) ==========
    input  wire                         init_mode,       // 1=init, 0=runtime
    input  wire                         init_wr_en,      // Write enable
    input  wire                         init_table_sel,  // 0=host table, 1=path table
    input  wire [7:0]                   init_addr,       // Write address
    input  wire [HOST_ENTRY_WIDTH-1:0]  init_data,       // Write data (max width)
    output reg                          init_done,       // Init complete flag

    // ========== Configuration Registers ==========
    input  wire [31:0]                  host_count_cfg,      // Number of hosts
    input  wire [31:0]                  switch_count_cfg,    // Number of switches
    input  wire [31:0]                  max_switch_id_cfg,   // Max switch ID

    // ========== Runtime Lookup Interface - Port A ==========
    input  wire                         req_a_valid,
    input  wire                         req_a_type,      // 0=host lookup, 1=path lookup
    input  wire [5:0]                   req_a_host_idx,  // For host lookup
    input  wire [3:0]                   req_a_src_sw,    // For path lookup
    input  wire [3:0]                   req_a_dst_sw,    // For path lookup

    output reg                          resp_a_valid,
    output reg                          resp_a_type,
    output reg [31:0]                   resp_a_host_ip,
    output reg [31:0]                   resp_a_host_switch_id,
    output reg [31:0]                   resp_a_host_switch_ip,
    output reg [15:0]                   resp_a_host_port,
    output reg [15:0]                   resp_a_host_qp,
    output reg [47:0]                   resp_a_host_mac,
    output reg                          resp_a_path_valid,
    output reg [7:0]                    resp_a_path_next_hop,
    output reg [15:0]                   resp_a_path_out_port,
    output reg [15:0]                   resp_a_path_out_qp,
    output reg [15:0]                   resp_a_path_distance,
    output reg [31:0]                   resp_a_path_next_hop_ip,
    output reg [15:0]                   resp_a_path_next_hop_port,
    output reg [15:0]                   resp_a_path_next_hop_qp,

    // ========== Runtime Lookup Interface - Port B (Optional Concurrent) ==========
    input  wire                         req_b_valid,
    input  wire                         req_b_type,
    input  wire [5:0]                   req_b_host_idx,
    input  wire [3:0]                   req_b_src_sw,
    input  wire [3:0]                   req_b_dst_sw,

    output reg                          resp_b_valid,
    output reg                          resp_b_type,
    output reg [31:0]                   resp_b_host_ip,
    output reg [31:0]                   resp_b_host_switch_id,
    output reg [31:0]                   resp_b_host_switch_ip,
    output reg [15:0]                   resp_b_host_port,
    output reg [15:0]                   resp_b_host_qp,
    output reg [47:0]                   resp_b_host_mac,
    output reg                          resp_b_path_valid,
    output reg [7:0]                    resp_b_path_next_hop,
    output reg [15:0]                   resp_b_path_out_port,
    output reg [15:0]                   resp_b_path_out_qp,
    output reg [15:0]                   resp_b_path_distance,
    output reg [31:0]                   resp_b_path_next_hop_ip,
    output reg [15:0]                   resp_b_path_next_hop_port,
    output reg [15:0]                   resp_b_path_next_hop_qp
);

//=============================================================================
// BRAM Storage Declaration
//=============================================================================
(* ram_style = "block" *)
reg [HOST_ENTRY_WIDTH-1:0] host_table_bram [0:MAX_HOSTS-1];

(* ram_style = "block" *)
reg [PATH_ENTRY_WIDTH-1:0] path_table_bram [0:MAX_SWITCHES*MAX_SWITCHES-1];

//=============================================================================
// Pipeline Registers for Address Calculation
//=============================================================================
reg [7:0]   addr_a_stage0, addr_b_stage0;
reg         type_a_stage0, type_b_stage0;
reg         valid_a_stage0, valid_b_stage0;

// Pipeline registers between Stage 1 and Stage 2
reg         valid_a_stage1, valid_b_stage1;
reg         type_a_stage1, type_b_stage1;

//=============================================================================
// BRAM Read Data Registers
//=============================================================================
reg [HOST_ENTRY_WIDTH-1:0] host_read_data_a, host_read_data_b;
reg [PATH_ENTRY_WIDTH-1:0] path_read_data_a, path_read_data_b;

//=============================================================================
// Address Calculation (Combinational Logic)
//=============================================================================
wire [7:0] lookup_addr_a, lookup_addr_b;
wire [7:0] array_dim_plus1;

assign array_dim_plus1 = max_switch_id_cfg[7:0] + 1;

// Port A address calculation
assign lookup_addr_a = req_a_type ?
                       (req_a_src_sw * array_dim_plus1 + req_a_dst_sw) :
                       {2'b0, req_a_host_idx};

// Port B address calculation
assign lookup_addr_b = req_b_type ?
                       (req_b_src_sw * array_dim_plus1 + req_b_dst_sw) :
                       {2'b0, req_b_host_idx};

//=============================================================================
// Stage 0: Address Calculation Pipeline Register
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_stage0 <= 1'b0;
        valid_b_stage0 <= 1'b0;
        addr_a_stage0 <= 8'h0;
        addr_b_stage0 <= 8'h0;
        type_a_stage0 <= 1'b0;
        type_b_stage0 <= 1'b0;
    end else if (!init_mode) begin
        // Runtime mode: capture request
        valid_a_stage0 <= req_a_valid;
        valid_b_stage0 <= req_b_valid;
        addr_a_stage0 <= lookup_addr_a;
        addr_b_stage0 <= lookup_addr_b;
        type_a_stage0 <= req_a_type;
        type_b_stage0 <= req_b_type;
    end else begin
        valid_a_stage0 <= 1'b0;
        valid_b_stage0 <= 1'b0;
    end
end

//=============================================================================
// Stage 1: Dual-Port BRAM Read
//=============================================================================
always @(posedge clk) begin
    // Initialization writes (Port A only)
    if (init_mode && init_wr_en) begin
        if (init_table_sel == 0) begin
            // Write to host table
            host_table_bram[init_addr[5:0]] <= init_data;
            $display("[Lookup Engine] Init: Write Host[%0d] = IP:0x%08x",
                     init_addr[5:0], init_data[31:0]);
        end else begin
            // Write to path table
            path_table_bram[init_addr] <= init_data[PATH_ENTRY_WIDTH-1:0];
            $display("[Lookup Engine] Init: Write Path[%0d] = valid:%d, next:%d",
                     init_addr, init_data[0], init_data[15:8]);
        end
    end

    // Runtime reads - Port A
    if (!init_mode && valid_a_stage0) begin
        if (type_a_stage0 == 0) begin
            // Host lookup
            host_read_data_a <= host_table_bram[addr_a_stage0[5:0]];
            $display("[Lookup Engine] Read Host[%0d]", addr_a_stage0[5:0]);
        end else begin
            // Path lookup
            path_read_data_a <= path_table_bram[addr_a_stage0];
            $display("[Lookup Engine] Read Path[%0d]", addr_a_stage0);
        end
    end

    // Runtime reads - Port B
    if (!init_mode && valid_b_stage0) begin
        if (type_b_stage0 == 0) begin
            // Host lookup
            host_read_data_b <= host_table_bram[addr_b_stage0[5:0]];
        end else begin
            // Path lookup
            path_read_data_b <= path_table_bram[addr_b_stage0];
        end
    end
end

//=============================================================================
// Stage 1.5: Pipeline register between BRAM read and parse
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_stage1 <= 1'b0;
        valid_b_stage1 <= 1'b0;
        type_a_stage1 <= 1'b0;
        type_b_stage1 <= 1'b0;
    end else begin
        valid_a_stage1 <= valid_a_stage0 && !init_mode;
        valid_b_stage1 <= valid_b_stage0 && !init_mode;
        type_a_stage1 <= type_a_stage0;
        type_b_stage1 <= type_b_stage0;
    end
end

//=============================================================================
// Stage 2: Parse and Output (Port A)
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_a_valid <= 1'b0;
        resp_a_type <= 1'b0;
        resp_a_host_ip <= 32'h0;
        resp_a_host_switch_id <= 32'h0;
        resp_a_host_switch_ip <= 32'h0;
        resp_a_host_port <= 16'h0;
        resp_a_host_qp <= 16'h0;
        resp_a_host_mac <= 48'h0;
        resp_a_path_valid <= 1'b0;
        resp_a_path_next_hop <= 8'h0;
        resp_a_path_out_port <= 16'h0;
        resp_a_path_out_qp <= 16'h0;
        resp_a_path_distance <= 16'h0;
        resp_a_path_next_hop_ip <= 32'h0;
        resp_a_path_next_hop_port <= 16'h0;
        resp_a_path_next_hop_qp <= 16'h0;
    end else begin
        resp_a_valid <= valid_a_stage1;
        resp_a_type <= type_a_stage1;

        if (valid_a_stage1) begin
            if (type_a_stage1 == 0) begin
                // Parse Host Entry
                resp_a_host_ip <= host_read_data_a[31:0];
                resp_a_host_switch_id <= host_read_data_a[63:32];
                resp_a_host_switch_ip <= host_read_data_a[95:64];
                resp_a_host_port <= host_read_data_a[111:96];
                resp_a_host_qp <= host_read_data_a[127:112];
                resp_a_host_mac <= host_read_data_a[175:128];
            end else begin
                // Parse Path Entry
                resp_a_path_valid <= (path_read_data_a[7:0] != 0);
                resp_a_path_next_hop <= path_read_data_a[15:8];
                resp_a_path_out_port <= path_read_data_a[31:16];
                resp_a_path_out_qp <= path_read_data_a[47:32];
                resp_a_path_distance <= path_read_data_a[63:48];
                resp_a_path_next_hop_ip <= path_read_data_a[95:64];
                resp_a_path_next_hop_port <= path_read_data_a[111:96];
                resp_a_path_next_hop_qp <= path_read_data_a[127:112];
            end
        end
    end
end

//=============================================================================
// Stage 2: Parse and Output (Port B)
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_b_valid <= 1'b0;
        resp_b_type <= 1'b0;
        resp_b_host_ip <= 32'h0;
        resp_b_host_switch_id <= 32'h0;
        resp_b_host_switch_ip <= 32'h0;
        resp_b_host_port <= 16'h0;
        resp_b_host_qp <= 16'h0;
        resp_b_host_mac <= 48'h0;
        resp_b_path_valid <= 1'b0;
        resp_b_path_next_hop <= 8'h0;
        resp_b_path_out_port <= 16'h0;
        resp_b_path_out_qp <= 16'h0;
        resp_b_path_distance <= 16'h0;
        resp_b_path_next_hop_ip <= 32'h0;
        resp_b_path_next_hop_port <= 16'h0;
        resp_b_path_next_hop_qp <= 16'h0;
    end else begin
        resp_b_valid <= valid_b_stage1;
        resp_b_type <= type_b_stage1;

        if (valid_b_stage1) begin
            if (type_b_stage1 == 0) begin
                // Parse Host Entry
                resp_b_host_ip <= host_read_data_b[31:0];
                resp_b_host_switch_id <= host_read_data_b[63:32];
                resp_b_host_switch_ip <= host_read_data_b[95:64];
                resp_b_host_port <= host_read_data_b[111:96];
                resp_b_host_qp <= host_read_data_b[127:112];
                resp_b_host_mac <= host_read_data_b[175:128];
            end else begin
                // Parse Path Entry
                resp_b_path_valid <= (path_read_data_b[7:0] != 0);
                resp_b_path_next_hop <= path_read_data_b[15:8];
                resp_b_path_out_port <= path_read_data_b[31:16];
                resp_b_path_out_qp <= path_read_data_b[47:32];
                resp_b_path_distance <= path_read_data_b[63:48];
                resp_b_path_next_hop_ip <= path_read_data_b[95:64];
                resp_b_path_next_hop_port <= path_read_data_b[111:96];
                resp_b_path_next_hop_qp <= path_read_data_b[127:112];
            end
        end
    end
end

//=============================================================================
// Init Done Flag
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        init_done <= 1'b0;
    end else if (init_mode && !init_wr_en) begin
        // Init mode but no write -> assume init complete
        init_done <= 1'b1;
    end
end

endmodule
