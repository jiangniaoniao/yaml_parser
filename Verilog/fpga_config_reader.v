`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 20:28:45
// Design Name: 
// Module Name: fpga_config_reader
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


module fpga_config_reader #(
    parameter MAX_CONNECTIONS = 64,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,
    
    // 存储器接口 (连接到包含二进制数据的ROM)
    output reg [ADDR_WIDTH-1:0]    mem_addr,
    input  wire [DATA_WIDTH-1:0]    mem_data,
    
    // 控制接口
    input  wire                     start_read,
    output reg                      busy,
    output reg                      config_valid,
    output reg                      parse_error,
    
    // 文件头寄存器
    output reg [31:0]              header_magic,
    output reg [31:0]              header_version,
    output reg [31:0]              header_connections,
    output reg [31:0]              header_timestamp,
    
    // 连接查询接口
    input  wire [5:0]             conn_index,
    input  wire                     read_connection,
    
    // 连接寄存器输出
    output reg [31:0]              conn_switch_id,
    output reg [31:0]              conn_host_id,
    output reg [31:0]              conn_my_ip,
    output reg [31:0]              conn_peer_ip,
    output reg [15:0]              conn_my_port,
    output reg [15:0]              conn_peer_port,
    output reg [15:0]              conn_my_qp,
    output reg [15:0]              conn_peer_qp,
    output reg [47:0]              conn_my_mac,
    output reg [47:0]              conn_peer_mac,
    output reg                     conn_up,
    output reg                     conn_valid
);

// 状态机定义
parameter STATE_IDLE          = 3'd0;
parameter STATE_READ_HEADER   = 3'd1;
parameter STATE_PARSE_HEADER  = 3'd2;
parameter STATE_READY         = 3'd3;
parameter STATE_READ_CONN     = 3'd4;
parameter STATE_PARSE_CONN    = 3'd5;
parameter STATE_ERROR         = 3'd6;

reg [2:0]                       state, next_state;

// 内部寄存器
reg [31:0]                      header_buffer [0:3];
reg [2:0]                       header_read_cnt;
reg [5:0]                       target_conn_index;
reg [3:0]                       conn_read_cnt;  // 连接读取计数（0-10）
reg [31:0]                      conn_buffer [0:10];
reg                             read_connection_reg;  // 寄存器存储read_connection

// 常数定义
localparam HEADER_SIZE_BYTES = 16;     // 头部16字节
localparam HEADER_SIZE_WORDS = 4;      // 头部4个字
localparam CONN_SIZE_BYTES = 44;       // 每个连接44字节
localparam WORDS_PER_CONN = 11;        // 每个连接11个字

//=============================================================================
// 状态机 - 组合逻辑
//=============================================================================
always @(*) begin
    next_state = state;
    case (state)
        STATE_IDLE:
            if (start_read)
                next_state = STATE_READ_HEADER;
                
        STATE_READ_HEADER:
            if (header_read_cnt == HEADER_SIZE_WORDS)
                next_state = STATE_PARSE_HEADER;
                
        STATE_PARSE_HEADER:
            next_state = STATE_READY;
                
        STATE_READY:
            if (read_connection_reg && conn_index < header_connections)
                next_state = STATE_READ_CONN;
                
        STATE_READ_CONN:
            if (conn_read_cnt == WORDS_PER_CONN)
                next_state = STATE_PARSE_CONN;
                
        STATE_PARSE_CONN:
            next_state = STATE_READY;
                
        STATE_ERROR:
            next_state = STATE_IDLE;
                
        default:
            next_state = STATE_IDLE;
    endcase
end

//=============================================================================
// 寄存器read_connection
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        read_connection_reg <= 1'b0;
    end else begin
        read_connection_reg <= read_connection;
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
        conn_read_cnt <= 4'h0;
        target_conn_index <= 6'h0;
    end else begin
        state <= next_state;
        
        case (next_state)
            STATE_IDLE: begin
                mem_addr <= 32'h0;
                header_read_cnt <= 3'b0;
                conn_read_cnt <= 4'h0;
                target_conn_index <= 6'h0;
            end
            
            STATE_READ_HEADER: begin
                // 头部起始地址为0，每个32位读取地址增加4
                mem_addr <= header_read_cnt * 4;  // 字节地址：0, 4, 8, 12
                if (header_read_cnt < HEADER_SIZE_WORDS) begin
                    header_read_cnt <= header_read_cnt + 1;
                end
            end
            
            STATE_PARSE_HEADER: begin
                // 保持地址不变
                mem_addr <= mem_addr;
            end
            
            STATE_READY: begin
                mem_addr <= 32'h0;
                conn_read_cnt <= 4'h0;
                
                // 在READY状态捕获conn_index
                if (read_connection && conn_index < header_connections) begin
                    target_conn_index <= conn_index;
                    $display("[DUT] STATE_READY: Captured conn_index=%d, target_conn_index=%d", 
                            conn_index, conn_index);
                end
            end
            
            STATE_READ_CONN: begin
                if (conn_read_cnt < WORDS_PER_CONN) begin
                    // 计算字节地址
                    // 头部: 0-15字节
                    // 连接n起始地址: 16 + n * 44
                    // 每个字偏移: conn_read_cnt * 4
                    mem_addr <= HEADER_SIZE_BYTES + 
                               (target_conn_index * CONN_SIZE_BYTES) + 
                               (conn_read_cnt * 4);
                    
                    $display("[DUT] STATE_READ_CONN: target_conn_index=%d, conn_read_cnt=%d, mem_addr=0x%08x", 
                            target_conn_index, conn_read_cnt, 
                            HEADER_SIZE_BYTES + (target_conn_index * CONN_SIZE_BYTES) + (conn_read_cnt * 4));
                    
                    conn_read_cnt <= conn_read_cnt + 1;
                end
            end
            
            STATE_PARSE_CONN: begin
                // 保持地址不变
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
        config_valid <= 1'b0;
        parse_error <= 1'b0;
        header_magic <= 32'h0;
        header_version <= 32'h0;
        header_connections <= 32'h0;
        header_timestamp <= 32'h0;
        
        conn_switch_id <= 32'h0;
        conn_host_id <= 32'h0;
        conn_my_ip <= 32'h0;
        conn_peer_ip <= 32'h0;
        conn_my_port <= 16'h0;
        conn_peer_port <= 16'h0;
        conn_my_qp <= 16'h0;
        conn_peer_qp <= 16'h0;
        conn_my_mac <= 48'h0;
        conn_peer_mac <= 48'h0;
        conn_up <= 1'b0;
        conn_valid <= 1'b0;
        
        // 初始化缓冲区
        for (integer i = 0; i < HEADER_SIZE_WORDS; i = i + 1) begin
            header_buffer[i] <= 32'h0;
        end
        for (integer j = 0; j < WORDS_PER_CONN; j = j + 1) begin
            conn_buffer[j] <= 32'h0;
        end
    end else begin
        conn_valid <= 1'b0;
        
        case (state)
            STATE_IDLE: begin
                busy <= 1'b0;
                config_valid <= 1'b0;
                parse_error <= 1'b0;
            end
            
            STATE_READ_HEADER: begin
                busy <= 1'b1;
                config_valid <= 1'b0;
                
                // 存储头部数据 - 注意时序
                if (header_read_cnt > 0) begin
                    // header_read_cnt已经递增，所以用header_read_cnt-1作为索引
                    header_buffer[header_read_cnt-1] <= mem_data;
                end
            end
            
            STATE_PARSE_HEADER: begin
                busy <= 1'b1;
                
                // 解析头部
                header_magic <= header_buffer[0];
                header_version <= header_buffer[1];
                header_connections <= header_buffer[2];
                header_timestamp <= header_buffer[3];
                
                // 验证魔数
                if (header_buffer[0] == 32'h41544746) begin  // "ATGF"小端序
                    config_valid <= 1'b1;
                    parse_error <= 1'b0;
                    $display("[DUT] Header parsed: magic=0x%08x, version=%d, conns=%d", 
                            header_buffer[0], header_buffer[1], header_buffer[2]);
                end else begin
                    config_valid <= 1'b0;
                    parse_error <= 1'b1;
                    $display("[DUT] Error: Invalid magic 0x%08x, expected 0x41544746", 
                            header_buffer[0]);
                end
            end
            
            STATE_READY: begin
                busy <= 1'b0;
                config_valid <= 1'b1;
            end
            
            STATE_READ_CONN: begin
                busy <= 1'b1;
                config_valid <= 1'b1;
                
                // 存储连接数据
                if (conn_read_cnt > 0) begin
                    // conn_read_cnt已经递增，所以用conn_read_cnt-1作为索引
                    conn_buffer[conn_read_cnt-1] <= mem_data;
                end
            end
            
            STATE_PARSE_CONN: begin
                busy <= 1'b0;
                
                // 解析连接数据
                conn_switch_id <= conn_buffer[0];
                conn_host_id <= conn_buffer[1];
                conn_my_ip <= conn_buffer[2];
                conn_peer_ip <= conn_buffer[3];
                
                // 端口和QP号（小端序）
                conn_my_port <= conn_buffer[4][15:0];
                conn_peer_port <= conn_buffer[4][31:16];
                conn_my_qp <= conn_buffer[5][15:0];
                conn_peer_qp <= conn_buffer[5][31:16];
                
                // MAC地址
                // my_mac: conn_buffer[6]的低32位 + conn_buffer[7]的低16位
                conn_my_mac <= {
                    conn_buffer[6][7:0],    // byte0
                    conn_buffer[6][15:8],   // byte1
                    conn_buffer[6][23:16],  // byte2
                    conn_buffer[6][31:24],  // byte3
                    conn_buffer[7][7:0],    // byte4
                    conn_buffer[7][15:8]    // byte5
                };
                
                // peer_mac: conn_buffer[7]的高16位 + conn_buffer[8]的32位
                conn_peer_mac <= {
                    conn_buffer[7][23:16],  // byte6
                    conn_buffer[7][31:24],  // byte7
                    conn_buffer[8][7:0],    // byte8
                    conn_buffer[8][15:8],   // byte9
                    conn_buffer[8][23:16],  // byte10
                    conn_buffer[8][31:24]   // byte11
                };
                
                // up字段
                conn_up <= conn_buffer[9][7:0] != 0;
                conn_valid <= 1'b1;
                
                $display("[DUT] Connection %d parsed: switch_id=%d, host_id=%d", 
                        target_conn_index, conn_buffer[0], conn_buffer[1]);
            end
            
            STATE_ERROR: begin
                busy <= 1'b0;
                config_valid <= 1'b0;
                parse_error <= 1'b1;
            end
        endcase
    end
end

endmodule