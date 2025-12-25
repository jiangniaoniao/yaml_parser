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
    parameter HOST_ENTRY_WIDTH = 192,    // 24 bytes = 192 bits
    parameter PATH_ENTRY_WIDTH = 192     // 24 bytes = 192 bits
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

    // ========== Runtime Lookup Interface - Port A (Auto Two-Level Lookup) ==========
    // Port A automatically performs: Host lookup → Path lookup → Output forwarding info
    input  wire                         req_a_valid,
    input  wire [3:0]                   req_a_src_sw,    // Current switch ID
    input  wire [5:0]                   req_a_dst_host,  // Destination host index

    output reg                          resp_a_valid,
    output reg                          resp_a_path_valid,
    output reg [15:0]                   resp_a_path_out_port,
    output reg [15:0]                   resp_a_path_out_qp,
    output reg [31:0]                   resp_a_path_next_hop_ip,
    output reg [15:0]                   resp_a_path_next_hop_port,
    output reg [15:0]                   resp_a_path_next_hop_qp,
    output reg [47:0]                   resp_a_path_next_hop_mac,

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
    output reg [15:0]                   resp_b_host_port,
    output reg [15:0]                   resp_b_host_qp,
    output reg [47:0]                   resp_b_host_mac,
    output reg                          resp_b_path_valid,
    output reg [15:0]                   resp_b_path_out_port,
    output reg [15:0]                   resp_b_path_out_qp,
    output reg [31:0]                   resp_b_path_next_hop_ip,
    output reg [15:0]                   resp_b_path_next_hop_port,
    output reg [15:0]                   resp_b_path_next_hop_qp,
    output reg [47:0]                   resp_b_path_next_hop_mac
);

//=============================================================================
// BRAM Storage Declaration
//=============================================================================
(* ram_style = "block" *)
reg [HOST_ENTRY_WIDTH-1:0] host_table_bram [0:MAX_HOSTS-1];

(* ram_style = "block" *)
reg [PATH_ENTRY_WIDTH-1:0] path_table_bram [0:MAX_SWITCHES*MAX_SWITCHES-1];

//=============================================================================
// Pipeline Registers for Two-Level Lookup (Port A)
//=============================================================================
// Port A: 5-stage pipeline for automatic two-level lookup
// Stage 0: Request capture
// Stage 1: Host BRAM read
// Stage 2: Parse host entry + Path address calculation
// Stage 3: Path BRAM read
// Stage 4: Parse path entry + Output

reg         valid_a_s0, valid_a_s1, valid_a_s2, valid_a_s3;
reg [3:0]   src_sw_a_s0, src_sw_a_s1, src_sw_a_s2;
reg [5:0]   dst_host_a_s0;
reg [7:0]   host_addr_a_s1;
reg [31:0]  dst_sw_id_a_s2;  // Extracted from host entry
reg [7:0]   path_addr_a_s2;

// Port B: Original 2-stage pipeline (kept for compatibility)
reg         valid_b_stage1;
reg         type_b_stage1;

//=============================================================================
// BRAM Read Data Registers
//=============================================================================
reg [HOST_ENTRY_WIDTH-1:0] host_read_data_a, host_read_data_b;
reg [PATH_ENTRY_WIDTH-1:0] path_read_data_a, path_read_data_b;

//=============================================================================
// Address Calculation (Combinational Logic)
//=============================================================================
wire [7:0] array_dim_plus1;
assign array_dim_plus1 = max_switch_id_cfg[7:0] + 1;

// Port A: Host table address (first level lookup)
wire [7:0] host_lookup_addr_a = {2'b0, req_a_dst_host};

// Port B address calculation (original dual-mode)
wire [7:0] lookup_addr_b = req_b_type ?
                           (req_b_src_sw * array_dim_plus1 + req_b_dst_sw) :
                           {2'b0, req_b_host_idx};

//=============================================================================
// Port A: Five-Stage Pipeline for Auto Two-Level Lookup
//=============================================================================

// Stage 0 → Stage 1: Capture request and start host lookup
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_s0 <= 1'b0;
        src_sw_a_s0 <= 4'h0;
        dst_host_a_s0 <= 6'h0;
    end else if (!init_mode) begin
        valid_a_s0 <= req_a_valid;
        src_sw_a_s0 <= req_a_src_sw;
        dst_host_a_s0 <= req_a_dst_host;
        if (req_a_valid) begin
            $display("[Lookup Engine] Port A Stage0: Captured request, src_sw=%d, dst_host=%d",
                     req_a_src_sw, req_a_dst_host);
        end
    end else begin
        valid_a_s0 <= 1'b0;
    end
end

// Stage 1: Host BRAM read (using host_read_data_a)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_s1 <= 1'b0;
        src_sw_a_s1 <= 4'h0;
        host_addr_a_s1 <= 8'h0;
    end else if (!init_mode) begin
        valid_a_s1 <= valid_a_s0;
        src_sw_a_s1 <= src_sw_a_s0;
        host_addr_a_s1 <= host_lookup_addr_a;
    end else begin
        valid_a_s1 <= 1'b0;
    end
end

// Stage 2: Parse host entry and calculate path address
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_s2 <= 1'b0;
        src_sw_a_s2 <= 4'h0;
        dst_sw_id_a_s2 <= 32'h0;
        path_addr_a_s2 <= 8'h0;
    end else if (!init_mode) begin
        valid_a_s2 <= valid_a_s1;
        src_sw_a_s2 <= src_sw_a_s1;

        // Parse host entry to get dst_switch_id
        // Host Entry format: [63:32] = switch_id
        dst_sw_id_a_s2 <= host_read_data_a[63:32];

        // Calculate path table address
        path_addr_a_s2 <= src_sw_a_s1 * array_dim_plus1 + host_read_data_a[35:32];

        if (valid_a_s1) begin
            $display("[Lookup Engine] Port A Stage2: valid_a_s1=%d, dst_sw_id=%d, path_addr=%d",
                     valid_a_s1, host_read_data_a[35:32],
                     src_sw_a_s1 * array_dim_plus1 + host_read_data_a[35:32]);
        end
    end else begin
        valid_a_s2 <= 1'b0;
    end
end

// Stage 3: Path BRAM read (using path_read_data_a)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_a_s3 <= 1'b0;
    end else if (!init_mode) begin
        valid_a_s3 <= valid_a_s2;
        if (valid_a_s2) begin
            $display("[Lookup Engine] Port A Stage3: valid_a_s2=%d, propagating to valid_a_s3",
                     valid_a_s2);
        end
    end else begin
        valid_a_s3 <= 1'b0;
    end
end

// Stage 4: Parse path entry and output
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_a_valid <= 1'b0;
        resp_a_path_valid <= 1'b0;
        resp_a_path_out_port <= 16'h0;
        resp_a_path_out_qp <= 16'h0;
        resp_a_path_next_hop_ip <= 32'h0;
        resp_a_path_next_hop_port <= 16'h0;
        resp_a_path_next_hop_qp <= 16'h0;
        resp_a_path_next_hop_mac <= 48'h0;
    end else if (!init_mode) begin
        resp_a_valid <= valid_a_s3;

        $display("[Lookup Engine] Port A Stage4: valid_a_s3=%d, setting resp_a_valid=%d",
                 valid_a_s3, valid_a_s3);

        if (valid_a_s3) begin
            // Parse Path Entry (192 bits)
            // [7:0]: valid
            // [47:32]: out_port
            // [63:48]: out_qp
            // [95:64]: next_hop_ip
            // [111:96]: next_hop_port
            // [127:112]: next_hop_qp
            // [175:128]: next_hop_mac (48 bits)
            resp_a_path_valid <= (path_read_data_a[7:0] != 0);
            resp_a_path_out_port <= path_read_data_a[47:32];
            resp_a_path_out_qp <= path_read_data_a[63:48];
            resp_a_path_next_hop_ip <= path_read_data_a[95:64];
            resp_a_path_next_hop_port <= path_read_data_a[111:96];
            resp_a_path_next_hop_qp <= path_read_data_a[127:112];
            resp_a_path_next_hop_mac <= path_read_data_a[175:128];

            $display("[Lookup Engine] Port A Stage4: Parsed path entry, valid=%d, MAC=%02x:%02x:%02x:%02x:%02x:%02x",
                     (path_read_data_a[7:0] != 0),
                     path_read_data_a[135:128], path_read_data_a[143:136],
                     path_read_data_a[151:144], path_read_data_a[159:152],
                     path_read_data_a[167:160], path_read_data_a[175:168]);
        end
    end else begin
        resp_a_valid <= 1'b0;
    end
end

//=============================================================================
// BRAM Read Logic (Combined for all stages)
//=============================================================================
// Port B临时寄存器
reg valid_b_stage0;
reg [7:0] addr_b_stage0;
reg type_b_stage0;

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
            $display("[Lookup Engine] Init: Write Path[%0d]", init_addr);
        end
    end

    // Runtime reads - Port A (Two-level lookup)
    // Stage 1: Read Host table
    if (!init_mode && valid_a_s0) begin
        host_read_data_a <= host_table_bram[host_lookup_addr_a[5:0]];
        $display("[Lookup Engine] Port A Stage1: Read Host[%0d]", host_lookup_addr_a[5:0]);
    end

    // Stage 3: Read Path table
    if (!init_mode && valid_a_s2) begin
        path_read_data_a <= path_table_bram[path_addr_a_s2];
        $display("[Lookup Engine] Port A Stage3: Read Path[%0d] (src=%d, dst=%d)",
                 path_addr_a_s2, src_sw_a_s2, dst_sw_id_a_s2[3:0]);
    end

    // Runtime reads - Port B (Original single lookup)
    if (!init_mode && valid_b_stage0) begin
        if (type_b_stage0 == 0) begin
            // Host lookup
            host_read_data_b <= host_table_bram[addr_b_stage0[5:0]];
            $display("[Lookup Engine] Port B: Read Host[%0d]", addr_b_stage0[5:0]);
        end else begin
            // Path lookup
            path_read_data_b <= path_table_bram[addr_b_stage0];
            $display("[Lookup Engine] Port B: Read Path[%0d]", addr_b_stage0);
        end
    end
end

// Port B Stage 0 register
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_b_stage0 <= 1'b0;
        addr_b_stage0 <= 8'h0;
        type_b_stage0 <= 1'b0;
    end else if (!init_mode) begin
        valid_b_stage0 <= req_b_valid;
        addr_b_stage0 <= lookup_addr_b;
        type_b_stage0 <= req_b_type;
    end else begin
        valid_b_stage0 <= 1'b0;
    end
end

// Port B Stage 1 register
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_b_stage1 <= 1'b0;
        type_b_stage1 <= 1'b0;
    end else begin
        valid_b_stage1 <= valid_b_stage0 && !init_mode;
        type_b_stage1 <= type_b_stage0;
    end
end

//=============================================================================
// Port B: Parse and Output (Original 2-stage pipeline)
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_b_valid <= 1'b0;
        resp_b_type <= 1'b0;
        resp_b_host_ip <= 32'h0;
        resp_b_host_switch_id <= 32'h0;
        resp_b_host_port <= 16'h0;
        resp_b_host_qp <= 16'h0;
        resp_b_host_mac <= 48'h0;
        resp_b_path_valid <= 1'b0;
        resp_b_path_out_port <= 16'h0;
        resp_b_path_out_qp <= 16'h0;
        resp_b_path_next_hop_ip <= 32'h0;
        resp_b_path_next_hop_port <= 16'h0;
        resp_b_path_next_hop_qp <= 16'h0;
        resp_b_path_next_hop_mac <= 48'h0;
    end else begin
        resp_b_valid <= valid_b_stage1;
        resp_b_type <= type_b_stage1;

        if (valid_b_stage1) begin
            if (type_b_stage1 == 0) begin
                // Parse Host Entry (192 bits)
                // [31:0]: host_ip
                // [63:32]: switch_id
                // [79:64]: port
                // [95:80]: qp
                // [143:96]: host_mac (48 bits)
                // [191:144]: padding
                resp_b_host_ip <= host_read_data_b[31:0];
                resp_b_host_switch_id <= host_read_data_b[63:32];
                resp_b_host_port <= host_read_data_b[79:64];
                resp_b_host_qp <= host_read_data_b[95:80];
                resp_b_host_mac <= host_read_data_b[143:96];
            end else begin
                // Parse Path Entry (192 bits)
                // [7:0]: valid
                // [31:8]: padding
                // [47:32]: out_port
                // [63:48]: out_qp
                // [95:64]: next_hop_ip
                // [111:96]: next_hop_port
                // [127:112]: next_hop_qp
                // [175:128]: next_hop_mac (48 bits)
                // [191:176]: padding2
                resp_b_path_valid <= (path_read_data_b[7:0] != 0);
                resp_b_path_out_port <= path_read_data_b[47:32];
                resp_b_path_out_qp <= path_read_data_b[63:48];
                resp_b_path_next_hop_ip <= path_read_data_b[95:64];
                resp_b_path_next_hop_port <= path_read_data_b[111:96];
                resp_b_path_next_hop_qp <= path_read_data_b[127:112];
                resp_b_path_next_hop_mac <= path_read_data_b[175:128];
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
