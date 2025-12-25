`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/20 12:43:50
// Design Name: 
// Module Name: routing_table_reader
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


module routing_table_reader #(
    parameter MAX_HOSTS = 64,
    parameter MAX_SWITCHES = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // 存储器接口 (连接到包含二进制数据的ROM)
    output reg [ADDR_WIDTH-1:0]    mem_addr,
    input  wire [DATA_WIDTH-1:0]   mem_data,

    // 控制接口
    input  wire                     start_read,
    output reg                      busy,
    output reg                      tables_valid,
    output reg                      parse_error,

    // ===== 服务器接入表头部 =====
    output reg [31:0]              host_magic,
    output reg [31:0]              host_count,

    // 主机条目查询接口
    input  wire [5:0]              host_index,
    input  wire                     read_host,

    // 主机条目输出
    output reg [31:0]              host_ip,
    output reg [31:0]              host_switch_id,
    output reg [15:0]              host_port,
    output reg [15:0]              host_qp,
    output reg [47:0]              host_mac,
    output reg                     host_valid,

    // ===== 交换机路径表头部 =====
    output reg [31:0]              switch_magic,
    output reg [31:0]              switch_count,
    output reg [31:0]              max_switch_id,

    // 交换机路径查询接口
    input  wire [3:0]              src_switch_id,
    input  wire [3:0]              dst_switch_id,
    input  wire                     read_path,

    // 交换机路径输出
    output reg                     path_valid_flag,
    output reg [15:0]              path_out_port,
    output reg [15:0]              path_out_qp,
    output reg [31:0]              path_next_hop_ip,
    output reg [15:0]              path_next_hop_port,
    output reg [15:0]              path_next_hop_qp,
    output reg [47:0]              path_next_hop_mac,
    output reg                     path_data_valid
);

// 状态机定义
localparam STATE_IDLE             = 4'd0;
localparam STATE_READ_HOST_HEADER = 4'd1;
localparam STATE_PARSE_HOST_HEADER= 4'd2;
localparam STATE_READ_SW_HEADER   = 4'd3;
localparam STATE_PARSE_SW_HEADER  = 4'd4;
localparam STATE_READY            = 4'd5;
localparam STATE_READ_HOST_ENTRY  = 4'd6;
localparam STATE_PARSE_HOST_ENTRY = 4'd7;
localparam STATE_READ_PATH_ENTRY  = 4'd8;
localparam STATE_PARSE_PATH_ENTRY = 4'd9;
localparam STATE_ERROR            = 4'd10;

reg [3:0]                       state, next_state;

// 条目大小常量（字节和字数）
localparam HOST_ENTRY_SIZE = 24;          // Host条目24字节
localparam SWITCH_ENTRY_SIZE = 24;        // Switch Path条目24字节
localparam HOST_ENTRY_WORDS = 6;          // 24字节 = 6个32位字
localparam SWITCH_ENTRY_WORDS = 6;        // 24字节 = 6个32位字

// 内部寄存器
reg [31:0]                      host_header_buffer [0:3];     // 16字节 = 4个word
reg [31:0]                      switch_header_buffer [0:3];   // 16字节 = 4个word
reg [31:0]                      host_entry_buffer [0:5];      // 24字节 = 6个word
reg [31:0]                      path_entry_buffer [0:5];      // 24字节 = 6个word

reg [2:0]                       header_read_cnt;
reg [3:0]                       entry_read_cnt;

reg [5:0]                       target_host_index;
reg [3:0]                       target_src_switch;
reg [3:0]                       target_dst_switch;

reg                             read_host_reg;
reg                             read_path_reg;

reg [31:0]                      host_table_offset;  // Host Table在文件中的起始偏移 (总是0)
reg [31:0]                      switch_table_offset; // Switch Path Table的起始偏移

// 常数定义
localparam HOST_HEADER_SIZE = 16;       // Host Table Header 16字节
localparam HOST_ENTRY_SIZE = 32;        // 每个Host Entry 32字节
localparam SWITCH_HEADER_SIZE = 16;     // Switch Path Table Header 16字节
localparam SWITCH_ENTRY_SIZE = 16;      // 每个Switch Path Entry 16字节

localparam HOST_HEADER_WORDS = 4;       // Header 4个word
localparam HOST_ENTRY_WORDS = 8;        // Host Entry 8个word
localparam SWITCH_HEADER_WORDS = 4;     // Header 4个word
localparam SWITCH_ENTRY_WORDS = 4;      // Path Entry 4个word

//=============================================================================
// 状态机 - 组合逻辑
//=============================================================================
always @(*) begin
    next_state = state;
    case (state)
        STATE_IDLE:
            if (start_read)
                next_state = STATE_READ_HOST_HEADER;

        STATE_READ_HOST_HEADER:
            if (header_read_cnt == HOST_HEADER_WORDS)
                next_state = STATE_PARSE_HOST_HEADER;

        STATE_PARSE_HOST_HEADER:
            // 延迟一个周期，确保switch_table_offset计算完成
            next_state = STATE_READ_SW_HEADER;

        STATE_READ_SW_HEADER:
            // 需要读取5次：第0次不读取（只等待offset计算），1-4次读取4个words
            if (header_read_cnt >= SWITCH_HEADER_WORDS + 1)
                next_state = STATE_PARSE_SW_HEADER;

        STATE_PARSE_SW_HEADER:
            next_state = STATE_READY;

        STATE_READY: begin
            if (read_host_reg && host_index < host_count)
                next_state = STATE_READ_HOST_ENTRY;
            else if (read_path_reg)
                next_state = STATE_READ_PATH_ENTRY;
        end

        STATE_READ_HOST_ENTRY:
            if (entry_read_cnt == HOST_ENTRY_WORDS)
                next_state = STATE_PARSE_HOST_ENTRY;

        STATE_PARSE_HOST_ENTRY:
            next_state = STATE_READY;

        STATE_READ_PATH_ENTRY:
            if (entry_read_cnt == SWITCH_ENTRY_WORDS)
                next_state = STATE_PARSE_PATH_ENTRY;

        STATE_PARSE_PATH_ENTRY:
            next_state = STATE_READY;

        STATE_ERROR:
            next_state = STATE_IDLE;

        default:
            next_state = STATE_IDLE;
    endcase
end

//=============================================================================
// 输入信号寄存
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        read_host_reg <= 1'b0;
        read_path_reg <= 1'b0;
    end else begin
        read_host_reg <= read_host;
        read_path_reg <= read_path;
    end
end

//=============================================================================
// 状态机 - 时序逻辑
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        mem_addr <= 32'h0;
        header_read_cnt <= 3'b0;
        entry_read_cnt <= 4'h0;
        target_host_index <= 6'h0;
        target_src_switch <= 4'h0;
        target_dst_switch <= 4'h0;
        host_table_offset <= 32'h0;
        switch_table_offset <= 32'h0;
    end else begin
        state <= next_state;

        case (next_state)
            STATE_IDLE: begin
                mem_addr <= 32'h0;
                header_read_cnt <= 3'b0;
                entry_read_cnt <= 4'h0;
                host_table_offset <= 32'h0;
                switch_table_offset <= 32'h0;
            end

            STATE_READ_HOST_HEADER: begin
                // Host Table从偏移0开始
                mem_addr <= host_table_offset + (header_read_cnt * 4);
                if (header_read_cnt < HOST_HEADER_WORDS) begin
                    header_read_cnt <= header_read_cnt + 1;
                end
            end

            STATE_PARSE_HOST_HEADER: begin
                // 重置计数器
                header_read_cnt <= 3'b0;
                // 直接使用buffer值计算offset，避免非阻塞赋值延迟
                switch_table_offset <= HOST_HEADER_SIZE + (host_header_buffer[1] * HOST_ENTRY_SIZE);
            end

            STATE_READ_SW_HEADER: begin
                // Switch Table Header
                // 第一个周期(header_read_cnt==0)只等待offset计算，不读取
                if (header_read_cnt > 0) begin
                    mem_addr <= switch_table_offset + ((header_read_cnt - 1) * 4);
                end
                if (header_read_cnt <= SWITCH_HEADER_WORDS) begin
                    header_read_cnt <= header_read_cnt + 1;
                end
            end

            STATE_PARSE_SW_HEADER: begin
                mem_addr <= mem_addr;
            end

            STATE_READY: begin
                mem_addr <= 32'h0;
                entry_read_cnt <= 4'h0;

                // 捕获查询索引
                if (read_host && host_index < host_count) begin
                    target_host_index <= host_index;
                end else if (read_path) begin
                    target_src_switch <= src_switch_id;
                    target_dst_switch <= dst_switch_id;
                end
            end

            STATE_READ_HOST_ENTRY: begin
                if (entry_read_cnt < HOST_ENTRY_WORDS) begin
                    // Host Entry Address = Host Header + (index × 32) + (word_offset × 4)
                    mem_addr <= HOST_HEADER_SIZE +
                               (target_host_index * HOST_ENTRY_SIZE) +
                               (entry_read_cnt * 4);
                    entry_read_cnt <= entry_read_cnt + 1;
                end
            end

            STATE_PARSE_HOST_ENTRY: begin
                mem_addr <= mem_addr;
            end

            STATE_READ_PATH_ENTRY: begin
                if (entry_read_cnt < SWITCH_ENTRY_WORDS) begin
                    // Path Entry Address = Switch Header Offset + Header Size +
                    //                     ((src × (max_id+1) + dst) × 16) + (word_offset × 4)
                    // 注意: max_switch_id在PARSE_SW_HEADER状态被解析
                    mem_addr <= switch_table_offset + SWITCH_HEADER_SIZE +
                               ((target_src_switch * (max_switch_id + 1) + target_dst_switch) * SWITCH_ENTRY_SIZE) +
                               (entry_read_cnt * 4);
                    entry_read_cnt <= entry_read_cnt + 1;
                end
            end

            STATE_PARSE_PATH_ENTRY: begin
                mem_addr <= mem_addr;
            end

            STATE_ERROR: begin
                mem_addr <= 32'h0;
            end
        endcase
    end
end

//=============================================================================
// 数据读取和处理逻辑
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy <= 1'b0;
        tables_valid <= 1'b0;
        parse_error <= 1'b0;

        host_magic <= 32'h0;
        host_count <= 32'h0;

        switch_magic <= 32'h0;
        switch_count <= 32'h0;
        max_switch_id <= 32'h0;

        host_ip <= 32'h0;
        host_switch_id <= 32'h0;
        host_port <= 16'h0;
        host_qp <= 16'h0;
        host_mac <= 48'h0;
        host_valid <= 1'b0;

        path_valid_flag <= 1'b0;
        path_out_port <= 16'h0;
        path_out_qp <= 16'h0;
        path_next_hop_ip <= 32'h0;
        path_next_hop_port <= 16'h0;
        path_next_hop_qp <= 16'h0;
        path_next_hop_mac <= 48'h0;
        path_data_valid <= 1'b0;

    end else begin
        host_valid <= 1'b0;
        path_data_valid <= 1'b0;

        case (state)
            STATE_IDLE: begin
                busy <= 1'b0;
                tables_valid <= 1'b0;
                parse_error <= 1'b0;
            end

            STATE_READ_HOST_HEADER: begin
                busy <= 1'b1;
                if (header_read_cnt > 0) begin
                    host_header_buffer[header_read_cnt-1] <= mem_data;
                end
            end

            STATE_PARSE_HOST_HEADER: begin
                busy <= 1'b1;

                // 解析Host Table Header
                host_magic <= host_header_buffer[0];
                host_count <= host_header_buffer[1];

                // 验证Magic Number (0x484F5354 = "HOST")
                if (host_header_buffer[0] == 32'h484F5354) begin  // "HOST"
                    $display("[Routing Reader] Host Table Header: magic=0x%08x, host_count=%d",
                            host_header_buffer[0], host_header_buffer[1]);
                end else begin
                    parse_error <= 1'b1;
                    $display("[Routing Reader] ERROR: Invalid Host magic 0x%08x",
                            host_header_buffer[0]);
                end
            end

            STATE_READ_SW_HEADER: begin
                busy <= 1'b1;
                // header_read_cnt: 0(空闲) 1(读word0) 2(读word1) 3(读word2) 4(读word3) 5(结束)
                // 当cnt=2时，保存的是cnt=1时读取的数据到buffer[0]
                if (header_read_cnt > 1) begin
                    switch_header_buffer[header_read_cnt-2] <= mem_data;
                end
            end

            STATE_PARSE_SW_HEADER: begin
                busy <= 1'b1;

                // 解析Switch Path Table Header
                switch_magic <= switch_header_buffer[0];
                switch_count <= switch_header_buffer[1];
                max_switch_id <= switch_header_buffer[2];

                // 验证Magic Number (0x53574348 = "SWCH")
                if (switch_header_buffer[0] == 32'h53574348) begin  // "SWCH"
                    tables_valid <= 1'b1;
                    parse_error <= 1'b0;
                    $display("[Routing Reader] Switch Table Header: magic=0x%08x, switch_count=%d, max_id=%d",
                            switch_header_buffer[0], switch_header_buffer[1], switch_header_buffer[2]);
                end else begin
                    tables_valid <= 1'b0;
                    parse_error <= 1'b1;
                    $display("[Routing Reader] ERROR: Invalid Switch magic 0x%08x",
                            switch_header_buffer[0]);
                end
            end

            STATE_READY: begin
                busy <= 1'b0;
            end

            STATE_READ_HOST_ENTRY: begin
                busy <= 1'b1;
                if (entry_read_cnt > 0) begin
                    host_entry_buffer[entry_read_cnt-1] <= mem_data;
                end
            end

            STATE_PARSE_HOST_ENTRY: begin
                busy <= 1'b0;

                // 解析Host Entry (24字节)
                // Word 0: host_ip
                // Word 1: switch_id
                // Word 2: port[15:0] | qp[15:0]
                // Word 3-4: host_mac (48位)
                // Word 5: padding
                host_ip <= host_entry_buffer[0];
                host_switch_id <= host_entry_buffer[1];
                host_port <= host_entry_buffer[2][15:0];   // 低16位是port
                host_qp <= host_entry_buffer[2][31:16];    // 高16位是qp

                // MAC地址: 6字节，位于Word 3-4
                host_mac <= {
                    host_entry_buffer[3][7:0],
                    host_entry_buffer[3][15:8],
                    host_entry_buffer[3][23:16],
                    host_entry_buffer[3][31:24],
                    host_entry_buffer[4][7:0],
                    host_entry_buffer[4][15:8]
                };

                host_valid <= 1'b1;

                $display("[Routing Reader] Host Entry %d: ip=0x%08x, switch_id=%d, port=%d, qp=%d",
                        target_host_index, host_entry_buffer[0], host_entry_buffer[1],
                        host_entry_buffer[2][15:0], host_entry_buffer[2][31:16]);
            end

            STATE_READ_PATH_ENTRY: begin
                busy <= 1'b1;
                if (entry_read_cnt > 0) begin
                    path_entry_buffer[entry_read_cnt-1] <= mem_data;
                end
            end

            STATE_PARSE_PATH_ENTRY: begin
                busy <= 1'b0;

                // 解析Path Entry (24字节)
                // Word 0: valid[7:0] | padding[23:0]
                // Word 1: out_port[15:0] | out_qp[15:0]
                // Word 2: next_hop_ip[31:0]
                // Word 3: next_hop_port[15:0] | next_hop_qp[15:0]
                // Word 4-5: next_hop_mac[47:0] + padding2

                path_valid_flag <= (path_entry_buffer[0][0] != 0);
                path_out_port <= path_entry_buffer[1][15:0];
                path_out_qp <= path_entry_buffer[1][31:16];

                path_next_hop_ip <= path_entry_buffer[2];

                path_next_hop_port <= path_entry_buffer[3][15:0];
                path_next_hop_qp <= path_entry_buffer[3][31:16];

                // MAC地址: 6字节，位于Word 4-5
                path_next_hop_mac <= {
                    path_entry_buffer[4][7:0],
                    path_entry_buffer[4][15:8],
                    path_entry_buffer[4][23:16],
                    path_entry_buffer[4][31:24],
                    path_entry_buffer[5][7:0],
                    path_entry_buffer[5][15:8]
                };

                path_data_valid <= 1'b1;

                $display("[Routing Reader] Path Entry [%d→%d]: valid=%d, out_port=%d, out_qp=%d",
                        target_src_switch, target_dst_switch,
                        (path_entry_buffer[0][0] != 0),
                        path_entry_buffer[1][15:0],
                        path_entry_buffer[1][31:16]);
            end

            STATE_ERROR: begin
                busy <= 1'b0;
                tables_valid <= 1'b0;
                parse_error <= 1'b1;
            end
        endcase
    end
end

endmodule
