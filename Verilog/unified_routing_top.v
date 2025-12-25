// 统一路由系统顶层模块（方案3优化版 - 使用Memory接口）
// 集成ROM、table reader和routing engine

`timescale 1ns / 1ps

module unified_routing_top #(
    parameter ROUTING_TABLE_FILE = "fpga_config_routing.hex",  // hex格式文件
    parameter MAX_ENTRIES = 64,
    parameter MY_SWITCH_ID = 1,  // 本交换机ID
    parameter MEM_SIZE = 1024    // ROM大小（字数）
)(
    input  wire         clk,
    input  wire         rst_n,

    // 查找接口
    input  wire         lookup_valid,
    input  wire [31:0]  lookup_dst_ip,

    // 响应接口（2 cycle延迟）
    output wire         resp_valid,
    output wire         resp_found,
    output wire [15:0]  resp_out_port,
    output wire [15:0]  resp_out_qp,
    output wire [31:0]  resp_next_hop_ip,
    output wire [15:0]  resp_next_hop_port,
    output wire [15:0]  resp_next_hop_qp,
    output wire [47:0]  resp_next_hop_mac,
    output wire         resp_is_direct_host,
    output wire         resp_is_broadcast,

    // 状态输出
    output wire         init_done,
    output wire         init_error
);

// ============ ROM模块（存储二进制文件） ============
reg [31:0] routing_table_rom [0:MEM_SIZE-1];

// 使用$readmemh加载二进制文件（hex格式）
integer rom_i;
initial begin
    // 初始化ROM为0（防止X/Z）
    for (rom_i = 0; rom_i < MEM_SIZE; rom_i = rom_i + 1) begin
        routing_table_rom[rom_i] = 32'h0;
    end

    $readmemh(ROUTING_TABLE_FILE, routing_table_rom);
end

// Memory读取接口
wire [31:0] mem_addr;
wire [31:0] mem_data;

// ROM读取逻辑（同步读取）
reg [31:0] mem_data_reg;
reg [31:0] last_mem_addr;

always @(posedge clk) begin
    last_mem_addr <= mem_addr;

    if (mem_addr[31:2] < MEM_SIZE) begin
        mem_data_reg <= routing_table_rom[mem_addr[31:2]];  // 字地址
    end else begin
        mem_data_reg <= 32'h0;
        if (mem_addr != last_mem_addr) begin
            $display("[ROM WARNING] 地址超出范围: 0x%h (字地址=%d, MEM_SIZE=%d)",
                     mem_addr, mem_addr[31:2], MEM_SIZE);
        end
    end
end

assign mem_data = mem_data_reg;

// ============ 初始化状态机 ============
localparam INIT_IDLE      = 3'd0;
localparam INIT_START     = 3'd1;
localparam INIT_LOADING   = 3'd2;
localparam INIT_WAIT      = 3'd3;
localparam INIT_DONE      = 3'd4;
localparam INIT_ERROR     = 3'd5;

reg [2:0]  init_state;
reg        init_mode;
reg        start_read;

// Table reader信号
wire        reader_done;
wire        reader_error;
wire [255:0] reader_entry_data;
wire [5:0]   reader_entry_addr;
wire         reader_entry_valid;

// Routing engine初始化信号
reg [255:0] engine_init_data;
reg [5:0]   engine_init_addr;
reg         engine_init_wr;

// 初始化延迟计数器
reg [7:0] init_delay_cnt;

// 状态输出
assign init_done = (init_state == INIT_DONE);
assign init_error = (init_state == INIT_ERROR);

// 初始化状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        init_state <= INIT_IDLE;
        init_mode <= 1'b1;
        start_read <= 1'b0;
        engine_init_wr <= 1'b0;
        init_delay_cnt <= 8'd0;
    end else begin
        case (init_state)
            INIT_IDLE: begin
                init_mode <= 1'b1;
                init_delay_cnt <= init_delay_cnt + 1;
                if (init_delay_cnt >= 8'd10) begin
                    init_state <= INIT_START;
                end
            end

            INIT_START: begin
                start_read <= 1'b1;
                init_state <= INIT_LOADING;
            end

            INIT_LOADING: begin
                start_read <= 1'b0;

                // 接收reader的输出并写入engine
                if (reader_entry_valid) begin
                    engine_init_data <= reader_entry_data;
                    engine_init_addr <= reader_entry_addr;
                    engine_init_wr <= 1'b1;
                end else begin
                    engine_init_wr <= 1'b0;
                end

                // 检查reader完成状态
                if (reader_done) begin
                    init_state <= INIT_WAIT;
                    init_delay_cnt <= 8'd0;
                end else if (reader_error) begin
                    $display("[ERROR] 路由表加载失败!");
                    init_state <= INIT_ERROR;
                end
            end

            INIT_WAIT: begin
                engine_init_wr <= 1'b0;
                init_delay_cnt <= init_delay_cnt + 1;
                if (init_delay_cnt >= 8'd5) begin
                    init_state <= INIT_DONE;
                end
            end

            INIT_DONE: begin
                init_mode <= 1'b0;  // 切换到运行模式
                // 状态保持在INIT_DONE，不再转移
            end

            INIT_ERROR: begin
                init_mode <= 1'b1;
            end

            default: init_state <= INIT_IDLE;
        endcase
    end
end

// ============ 实例化Table Reader ============
unified_table_reader #(
    .MAX_ENTRIES(MAX_ENTRIES)
) table_reader_inst (
    .clk(clk),
    .rst_n(rst_n),

    // Memory接口
    .mem_addr(mem_addr),
    .mem_data(mem_data),

    // 控制接口
    .start_read(start_read),
    .target_switch_id(MY_SWITCH_ID[3:0]),
    .read_done(reader_done),
    .read_error(reader_error),

    // 输出接口
    .entry_data(reader_entry_data),
    .entry_addr(reader_entry_addr),
    .entry_valid(reader_entry_valid)
);

// ============ 实例化Routing Engine ============
unified_routing_engine #(
    .MAX_ENTRIES(MAX_ENTRIES),
    .ENTRY_WIDTH(256),
    .IP_WIDTH(32)
) routing_engine_inst (
    .clk(clk),
    .rst_n(rst_n),

    // 初始化接口
    .init_mode(init_mode),
    .init_entry_data(engine_init_data),
    .init_entry_addr(engine_init_addr),
    .init_entry_wr(engine_init_wr),

    // 查找接口
    .lookup_valid(lookup_valid),
    .lookup_dst_ip(lookup_dst_ip),

    // 响应接口
    .resp_valid(resp_valid),
    .resp_found(resp_found),
    .resp_out_port(resp_out_port),
    .resp_out_qp(resp_out_qp),
    .resp_next_hop_ip(resp_next_hop_ip),
    .resp_next_hop_port(resp_next_hop_port),
    .resp_next_hop_qp(resp_next_hop_qp),
    .resp_next_hop_mac(resp_next_hop_mac),
    .resp_is_direct_host(resp_is_direct_host),
    .resp_is_broadcast(resp_is_broadcast)
);

endmodule
