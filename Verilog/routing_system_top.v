`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/22 23:31:54
// Design Name: 
// Module Name: routing_system_top
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


module routing_system_top #(
    parameter MAX_HOSTS = 64,
    parameter MAX_SWITCHES = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter HOST_ENTRY_WIDTH = 256,
    parameter PATH_ENTRY_WIDTH = 128
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // ========== Memory Interface (for initialization) ==========
    output wire [ADDR_WIDTH-1:0]        mem_addr,
    input  wire [DATA_WIDTH-1:0]        mem_data,

    // ========== Control Interface ==========
    input  wire                         start_init,      // Start loading tables
    output wire                         init_busy,       // Initialization in progress
    output wire                         system_ready,    // System ready for lookup

    // ========== Runtime Lookup Interface - Port A ==========
    input  wire                         req_a_valid,
    input  wire                         req_a_type,      // 0=host lookup, 1=path lookup
    input  wire [5:0]                   req_a_host_idx,  // For host lookup
    input  wire [3:0]                   req_a_src_sw,    // For path lookup
    input  wire [3:0]                   req_a_dst_sw,    // For path lookup

    output wire                         resp_a_valid,
    output wire                         resp_a_type,
    // Host lookup results
    output wire [31:0]                  resp_a_host_ip,
    output wire [31:0]                  resp_a_host_switch_id,
    output wire [31:0]                  resp_a_host_switch_ip,
    output wire [15:0]                  resp_a_host_port,
    output wire [15:0]                  resp_a_host_qp,
    output wire [47:0]                  resp_a_host_mac,
    // Path lookup results
    output wire                         resp_a_path_valid,
    output wire [7:0]                   resp_a_path_next_hop,
    output wire [15:0]                  resp_a_path_out_port,
    output wire [15:0]                  resp_a_path_out_qp,
    output wire [15:0]                  resp_a_path_distance,
    output wire [31:0]                  resp_a_path_next_hop_ip,
    output wire [15:0]                  resp_a_path_next_hop_port,
    output wire [15:0]                  resp_a_path_next_hop_qp,

    // ========== Runtime Lookup Interface - Port B ==========
    input  wire                         req_b_valid,
    input  wire                         req_b_type,
    input  wire [5:0]                   req_b_host_idx,
    input  wire [3:0]                   req_b_src_sw,
    input  wire [3:0]                   req_b_dst_sw,

    output wire                         resp_b_valid,
    output wire                         resp_b_type,
    output wire [31:0]                  resp_b_host_ip,
    output wire [31:0]                  resp_b_host_switch_id,
    output wire [31:0]                  resp_b_host_switch_ip,
    output wire [15:0]                  resp_b_host_port,
    output wire [15:0]                  resp_b_host_qp,
    output wire [47:0]                  resp_b_host_mac,
    output wire                         resp_b_path_valid,
    output wire [7:0]                   resp_b_path_next_hop,
    output wire [15:0]                  resp_b_path_out_port,
    output wire [15:0]                  resp_b_path_out_qp,
    output wire [15:0]                  resp_b_path_distance,
    output wire [31:0]                  resp_b_path_next_hop_ip,
    output wire [15:0]                  resp_b_path_next_hop_port,
    output wire [15:0]                  resp_b_path_next_hop_qp
);

//=============================================================================
// Internal Signals
//=============================================================================

// Initialization state machine
localparam INIT_IDLE           = 3'd0;
localparam INIT_WAIT_HEADER    = 3'd1;
localparam INIT_LOAD_HOSTS     = 3'd2;
localparam INIT_LOAD_PATHS     = 3'd3;
localparam INIT_FINISHING      = 3'd4;
localparam INIT_DONE           = 3'd5;

reg [2:0] init_state;
reg [7:0] init_entry_cnt;
reg [7:0] total_hosts;
reg [7:0] total_switches;
reg [7:0] max_sw_id;
reg       host_req_sent;       // Flag to track if host read request was sent
reg       path_req_sent;       // Flag to track if path read request was sent
reg [3:0] finish_wait_cnt;     // Counter to wait before switching to runtime mode

// Table reader interface
wire        reader_busy;
wire        reader_tables_valid;
wire        reader_parse_error;
wire [31:0] reader_host_count;
wire [31:0] reader_switch_count;
wire [31:0] reader_max_switch_id;

reg         reader_start;
reg         reader_read_host;
reg  [5:0]  reader_host_idx;
reg         reader_read_path;
reg  [3:0]  reader_src_sw;
reg  [3:0]  reader_dst_sw;

wire [31:0] reader_host_ip;
wire [31:0] reader_host_switch_id;
wire [31:0] reader_host_switch_ip;
wire [15:0] reader_host_port;
wire [15:0] reader_host_qp;
wire [47:0] reader_host_mac;
wire        reader_host_valid;

wire        reader_path_valid_flag;
wire [7:0]  reader_path_next_hop;
wire [15:0] reader_path_out_port;
wire [15:0] reader_path_out_qp;
wire [15:0] reader_path_distance;
wire [31:0] reader_path_next_hop_ip;
wire [15:0] reader_path_next_hop_port;
wire [15:0] reader_path_next_hop_qp;
wire        reader_path_data_valid;

// Lookup engine interface
reg                          engine_init_mode;
reg                          engine_init_wr_en;
reg                          engine_init_table_sel;
reg  [7:0]                   engine_init_addr;
reg  [HOST_ENTRY_WIDTH-1:0]  engine_init_data;
wire                         engine_init_done;

//=============================================================================
// Routing Table Reader Instance
//=============================================================================
routing_table_reader #(
    .MAX_HOSTS      (MAX_HOSTS),
    .MAX_SWITCHES   (MAX_SWITCHES),
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH)
) u_table_reader (
    .clk                    (clk),
    .rst_n                  (rst_n),

    .mem_addr               (mem_addr),
    .mem_data               (mem_data),

    .start_read             (reader_start),
    .busy                   (reader_busy),
    .tables_valid           (reader_tables_valid),
    .parse_error            (reader_parse_error),

    .host_magic             (),
    .host_count             (reader_host_count),

    .host_index             (reader_host_idx),
    .read_host              (reader_read_host),
    .host_ip                (reader_host_ip),
    .host_switch_id         (reader_host_switch_id),
    .host_switch_ip         (reader_host_switch_ip),
    .host_port              (reader_host_port),
    .host_qp                (reader_host_qp),
    .host_mac               (reader_host_mac),
    .host_valid             (reader_host_valid),

    .switch_magic           (),
    .switch_count           (reader_switch_count),
    .max_switch_id          (reader_max_switch_id),

    .src_switch_id          (reader_src_sw),
    .dst_switch_id          (reader_dst_sw),
    .read_path              (reader_read_path),
    .path_valid_flag        (reader_path_valid_flag),
    .path_next_hop_switch   (reader_path_next_hop),
    .path_out_port          (reader_path_out_port),
    .path_out_qp            (reader_path_out_qp),
    .path_distance          (reader_path_distance),
    .path_next_hop_ip       (reader_path_next_hop_ip),
    .path_next_hop_port     (reader_path_next_hop_port),
    .path_next_hop_qp       (reader_path_next_hop_qp),
    .path_data_valid        (reader_path_data_valid)
);

//=============================================================================
// Routing Lookup Engine Instance
//=============================================================================
routing_lookup_engine #(
    .MAX_HOSTS          (MAX_HOSTS),
    .MAX_SWITCHES       (MAX_SWITCHES),
    .HOST_ENTRY_WIDTH   (HOST_ENTRY_WIDTH),
    .PATH_ENTRY_WIDTH   (PATH_ENTRY_WIDTH)
) u_lookup_engine (
    .clk                        (clk),
    .rst_n                      (rst_n),

    // Initialization interface
    .init_mode                  (engine_init_mode),
    .init_wr_en                 (engine_init_wr_en),
    .init_table_sel             (engine_init_table_sel),
    .init_addr                  (engine_init_addr),
    .init_data                  (engine_init_data),
    .init_done                  (engine_init_done),

    // Configuration
    .host_count_cfg             ({24'h0, total_hosts}),
    .switch_count_cfg           ({24'h0, total_switches}),
    .max_switch_id_cfg          ({24'h0, max_sw_id}),

    // Port A lookup interface
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

    // Port B lookup interface
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
// Initialization State Machine
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        init_state <= INIT_IDLE;
        init_entry_cnt <= 8'h0;
        total_hosts <= 8'h0;
        total_switches <= 8'h0;
        max_sw_id <= 8'h0;
        host_req_sent <= 1'b0;
        path_req_sent <= 1'b0;
        finish_wait_cnt <= 4'h0;

        reader_start <= 1'b0;
        reader_read_host <= 1'b0;
        reader_read_path <= 1'b0;
        reader_host_idx <= 6'h0;
        reader_src_sw <= 4'h0;
        reader_dst_sw <= 4'h0;

        engine_init_mode <= 1'b0;
        engine_init_wr_en <= 1'b0;
        engine_init_table_sel <= 1'b0;
        engine_init_addr <= 8'h0;
        engine_init_data <= {HOST_ENTRY_WIDTH{1'b0}};

    end else begin
        // Default: clear single-cycle pulses
        reader_start <= 1'b0;
        reader_read_host <= 1'b0;
        reader_read_path <= 1'b0;
        engine_init_wr_en <= 1'b0;

        case (init_state)
            INIT_IDLE: begin
                engine_init_mode <= 1'b0;
                init_entry_cnt <= 8'h0;

                if (start_init) begin
                    reader_start <= 1'b1;
                    init_state <= INIT_WAIT_HEADER;
                    engine_init_mode <= 1'b1;
                    $display("[Init] Starting initialization...");
                end
            end

            INIT_WAIT_HEADER: begin
                // Wait for table reader to parse headers
                if (reader_tables_valid) begin
                    total_hosts <= reader_host_count[7:0];
                    total_switches <= reader_switch_count[7:0];
                    max_sw_id <= reader_max_switch_id[7:0];
                    init_entry_cnt <= 8'h0;
                    host_req_sent <= 1'b0;
                    init_state <= INIT_LOAD_HOSTS;
                    $display("[Init] Headers loaded: hosts=%d, switches=%d, max_id=%d",
                             reader_host_count, reader_switch_count, reader_max_switch_id);
                end else if (reader_parse_error) begin
                    init_state <= INIT_IDLE;
                    $display("[Init] ERROR: Parse error during header read");
                end
            end

            INIT_LOAD_HOSTS: begin
                if (init_entry_cnt < total_hosts) begin
                    // Send read request only if not already sent
                    if (!host_req_sent && !reader_busy) begin
                        reader_host_idx <= init_entry_cnt[5:0];
                        reader_read_host <= 1'b1;
                        host_req_sent <= 1'b1;
                        $display("[Init] Requesting Host[%d]...", init_entry_cnt);
                    end

                    // When data is valid, write to BRAM and move to next entry
                    if (reader_host_valid) begin
                        // Write host entry to BRAM
                        engine_init_table_sel <= 1'b0;  // Host table
                        engine_init_addr <= init_entry_cnt;
                        engine_init_wr_en <= 1'b1;

                        // Pack host entry data (256 bits)
                        engine_init_data <= {
                            80'h0,                      // [255:176] padding
                            reader_host_mac,            // [175:128] MAC (48 bits)
                            reader_host_qp,             // [127:112] QP (16 bits)
                            reader_host_port,           // [111:96]  Port (16 bits)
                            reader_host_switch_ip,      // [95:64]   Switch IP (32 bits)
                            reader_host_switch_id,      // [63:32]   Switch ID (32 bits)
                            reader_host_ip              // [31:0]    Host IP (32 bits)
                        };

                        init_entry_cnt <= init_entry_cnt + 1;
                        host_req_sent <= 1'b0;  // Clear flag for next entry
                        $display("[Init] Loaded Host[%d]: IP=0x%08x, Switch=%d",
                                 init_entry_cnt, reader_host_ip, reader_host_switch_id);
                    end
                end else begin
                    // All hosts loaded, move to path table
                    init_entry_cnt <= 8'h0;
                    reader_src_sw <= 4'h1;  // Start from switch ID 1, not 0
                    reader_dst_sw <= 4'h1;  // Start from switch ID 1, not 0
                    path_req_sent <= 1'b0;
                    init_state <= INIT_LOAD_PATHS;
                    $display("[Init] All %d hosts loaded, loading path table...", total_hosts);
                end
            end

            INIT_LOAD_PATHS: begin
                // Load all path entries: only valid switch IDs (1 to max_sw_id)
                if (reader_src_sw <= max_sw_id) begin
                    // Send read request only if not already sent
                    if (!path_req_sent && !reader_busy) begin
                        reader_read_path <= 1'b1;
                        path_req_sent <= 1'b1;
                        $display("[Init] Requesting Path[%d→%d]...", reader_src_sw, reader_dst_sw);
                    end

                    // When data is valid, write to BRAM and move to next entry
                    if (reader_path_data_valid) begin
                        // Write path entry to BRAM
                        engine_init_table_sel <= 1'b1;  // Path table
                        engine_init_addr <= reader_src_sw * (max_sw_id + 1) + reader_dst_sw;
                        engine_init_wr_en <= 1'b1;

                        // Pack path entry data (128 bits, padded to 256)
                        engine_init_data <= {
                            128'h0,                          // [255:128] padding
                            reader_path_next_hop_qp,         // [127:112]
                            reader_path_next_hop_port,       // [111:96]
                            reader_path_next_hop_ip,         // [95:64]
                            reader_path_distance,            // [63:48]
                            reader_path_out_qp,              // [47:32]
                            reader_path_out_port,            // [31:16]
                            reader_path_next_hop,            // [15:8]
                            (reader_path_valid_flag ? 8'h01 : 8'h00)  // [7:0]
                        };

                        path_req_sent <= 1'b0;  // Clear flag for next entry
                        $display("[Init] Loaded Path[%d→%d]: next_hop=%d, valid=%d, BRAM_addr=%d",
                                 reader_src_sw, reader_dst_sw, reader_path_next_hop, reader_path_valid_flag,
                                 reader_src_sw * (max_sw_id + 1) + reader_dst_sw);

                        // Move to next entry (only iterate through valid switch IDs: 1 to max_sw_id)
                        if (reader_dst_sw == max_sw_id) begin
                            reader_src_sw <= reader_src_sw + 1;
                            reader_dst_sw <= 4'h1;  // Reset to 1, not 0
                        end else begin
                            reader_dst_sw <= reader_dst_sw + 1;
                        end
                    end
                end else begin
                    // All paths loaded, wait a few cycles before switching mode
                    init_state <= INIT_FINISHING;
                    finish_wait_cnt <= 4'h0;
                    $display("[Init] All path entries loaded. Finishing up...");
                end
            end

            INIT_FINISHING: begin
                // Wait a few cycles to ensure all BRAM writes complete
                finish_wait_cnt <= finish_wait_cnt + 1;
                if (finish_wait_cnt >= 4'd5) begin
                    init_state <= INIT_DONE;
                    engine_init_mode <= 1'b0;
                    $display("[Init] Switching to runtime mode. System ready!");
                end
            end

            INIT_DONE: begin
                // Stay in done state until reset
                engine_init_mode <= 1'b0;
            end

            default: begin
                init_state <= INIT_IDLE;
            end
        endcase
    end
end

//=============================================================================
// Output Assignments
//=============================================================================
assign init_busy = (init_state != INIT_IDLE) && (init_state != INIT_DONE);
assign system_ready = (init_state == INIT_DONE);

endmodule
