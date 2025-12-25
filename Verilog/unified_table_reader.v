// 统一路由表读取器（使用Memory接口，参考routing_table_reader.v）
// 从预加载的memory读取目的地路由表

`timescale 1ns / 1ps

module unified_table_reader #(
    parameter MAX_ENTRIES = 64
)(
    input  wire         clk,
    input  wire         rst_n,

    // Memory接口（连接到包含二进制数据的ROM）
    output reg [31:0]   mem_addr,
    input  wire [31:0]  mem_data,

    // 控制接口
    input  wire         start_read,
    input  wire [3:0]   target_switch_id,
    output reg          read_done,
    output reg          read_error,

    // 输出到routing engine的初始化接口
    output reg [255:0]  entry_data,
    output reg [5:0]    entry_addr,
    output reg          entry_valid
);

// 状态机
localparam IDLE             = 4'd0;
localparam READ_HEADER      = 4'd1;
localparam WAIT_HEADER      = 4'd2;
localparam CHECK_HEADER     = 4'd3;
localparam READ_ENTRY       = 4'd4;
localparam WAIT_ENTRY       = 4'd5;
localparam PARSE_ENTRY      = 4'd6;
localparam SKIP_TABLE       = 4'd7;
localparam DONE             = 4'd8;
localparam ERROR            = 4'd9;

reg [3:0] state;

// Header字段
reg [31:0] magic;
reg [31:0] entry_count;
reg [31:0] switch_id;
reg [31:0] reserved;

// Entry缓冲区（32字节 = 8个32位字）
reg [31:0] entry_buffer [0:7];

// 计数器
reg [5:0]  entry_idx;      // 当前处理的entry索引
reg [3:0]  word_idx;       // Entry内的字索引（0-8，需要能表示8）
reg [31:0] skip_count;     // 跳过计数

// 是否找到目标Switch的表
reg target_found;

// Header读取字计数（Header = 16字节 = 4个字）
reg [1:0] header_word_idx;

// 初始化
initial begin
    state = IDLE;
    read_done = 0;
    read_error = 0;
    entry_valid = 0;
    target_found = 0;
    mem_addr = 32'h0;
end

// 主状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        read_done <= 1'b0;
        read_error <= 1'b0;
        entry_valid <= 1'b0;
        target_found <= 1'b0;
        entry_idx <= 6'd0;
        word_idx <= 4'd0;
        header_word_idx <= 2'd0;
        mem_addr <= 32'h0;
        skip_count <= 32'd0;
    end else begin
        case (state)
            IDLE: begin
                entry_valid <= 1'b0;
                if (start_read) begin
                    state <= READ_HEADER;
                    mem_addr <= 32'h0;
                    header_word_idx <= 2'd0;
                    target_found <= 1'b0;
                end
            end

            READ_HEADER: begin
                // 发出地址，等待下一周期数据有效
                mem_addr <= mem_addr;  // 保持当前地址
                state <= WAIT_HEADER;
            end

            WAIT_HEADER: begin
                // 读取数据（此时mem_data已有效）
                if (header_word_idx == 0) begin
                    magic <= mem_data;
                    mem_addr <= mem_addr + 4;
                    header_word_idx <= 2'd1;
                    state <= READ_HEADER;  // 继续读取下一个字
                end else if (header_word_idx == 1) begin
                    entry_count <= mem_data;
                    mem_addr <= mem_addr + 4;
                    header_word_idx <= 2'd2;
                    state <= READ_HEADER;
                end else if (header_word_idx == 2) begin
                    switch_id <= mem_data;
                    mem_addr <= mem_addr + 4;
                    header_word_idx <= 2'd3;
                    state <= READ_HEADER;
                end else if (header_word_idx == 3) begin
                    reserved <= mem_data;
                    mem_addr <= mem_addr + 4;
                    state <= CHECK_HEADER;
                end
            end

            CHECK_HEADER: begin
                // 检查Magic
                if (magic != 32'h44455354) begin  // "DEST"
                    if (target_found) begin
                        // 已找到目标表，当前表无效Magic，说明已读完
                        state <= DONE;
                    end else begin
                        $display("[ERROR] Magic校验失败!");
                        state <= ERROR;
                        read_error <= 1'b1;
                    end
                end else if (switch_id == target_switch_id) begin
                    // 找到目标Switch的表
                    target_found <= 1'b1;
                    entry_idx <= 6'd0;
                    word_idx <= 4'd0;
                    state <= READ_ENTRY;
                end else begin
                    // 跳过此表
                    skip_count <= entry_count * 8;  // 每个Entry 8个字
                    state <= SKIP_TABLE;
                end
            end

            READ_ENTRY: begin
                entry_valid <= 1'b0;

                if (entry_idx < entry_count && entry_idx < MAX_ENTRIES) begin
                    // 读取Entry的8个字
                    if (word_idx < 8) begin
                        // 设置下一个字的地址（每次推进4字节）
                        mem_addr <= mem_addr + 4;
                        word_idx <= word_idx + 1;

                        // ROM同步读：跳过第一个周期（word_idx=0时ROM还没准备好数据）
                        if (word_idx > 0) begin
                            entry_buffer[word_idx-1] <= mem_data;
                        end
                    end else begin
                        // 读取最后一个字（word_idx=8时读取word[7]的数据）
                        // 注意：此时mem_addr已经指向下一个Entry的起始位置，不再推进
                        entry_buffer[7] <= mem_data;
                        state <= PARSE_ENTRY;
                    end
                end else begin
                    // 所有Entry加载完成
                    state <= DONE;
                end
            end

            PARSE_ENTRY: begin

                // 组装成256位Entry
                // entry_buffer[0] = [dst_ip[31:0]]
                // entry_buffer[1] = [padding1[7:0], is_broadcast, is_direct_host, valid]
                // entry_buffer[2] = [out_qp[15:0], out_port[15:0]]
                // entry_buffer[3] = [next_hop_ip[31:0]]
                // entry_buffer[4] = [next_hop_qp[15:0], next_hop_port[15:0]]
                // entry_buffer[5] = [next_hop_mac[15:0], next_hop_mac[31:16]]
                // entry_buffer[6] = [padding2[15:0], next_hop_mac[47:32]]
                // entry_buffer[7] = [padding2[63:16]]

                entry_data <= {
                    entry_buffer[7],  // [255:224]
                    entry_buffer[6],  // [223:192]
                    entry_buffer[5],  // [191:160]
                    entry_buffer[4],  // [159:128]
                    entry_buffer[3],  // [127:96]
                    entry_buffer[2],  // [95:64]
                    entry_buffer[1],  // [63:32]
                    entry_buffer[0]   // [31:0]
                };
                entry_addr <= entry_idx;
                entry_valid <= 1'b1;

                entry_idx <= entry_idx + 1;
                word_idx <= 4'd0;
                state <= READ_ENTRY;
            end

            SKIP_TABLE: begin
                // 跳过当前表的所有Entry
                if (skip_count > 0) begin
                    mem_addr <= mem_addr + 4;
                    skip_count <= skip_count - 1;
                    // 保持在当前状态直到skip_count=0
                end else begin
                    // 跳过完成，读取下一个表的Header
                    header_word_idx <= 2'd0;
                    state <= READ_HEADER;
                end
            end

            DONE: begin
                entry_valid <= 1'b0;
                read_done <= 1'b1;
            end

            ERROR: begin
                entry_valid <= 1'b0;
                read_error <= 1'b1;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
