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
    
    // 文件头寄存器 (用于波形观察)
    output reg [31:0]              header_magic,
    output reg [31:0]              header_version,
    output reg [31:0]              header_connections,
    output reg [31:0]              header_timestamp,
    
    // 连接查询接口
    input  wire [5:0]             conn_index,
    input  wire                     read_connection,
    
    // 连接寄存器输出 (用于波形观察)
    output reg [31:0]              conn_switch_id,
    output reg [31:0]              conn_host_id,
    output reg [31:0]              conn_local_ip,
    output reg [31:0]              conn_peer_ip,
    output reg [15:0]              conn_local_port,
    output reg [15:0]              conn_peer_port,
    output reg [15:0]              conn_local_qp,
    output reg [15:0]              conn_peer_qp,
    output reg [47:0]              conn_local_mac,
    output reg [47:0]              conn_peer_mac,
    output reg                     conn_up,
    output reg                     conn_valid
);

// 状态机定义
parameter STATE_IDLE          = 3'd0;
parameter STATE_READ_HEADER   = 3'd1;
parameter STATE_PARSE_HEADER   = 3'd2;
parameter STATE_READY         = 3'd3;
parameter STATE_READ_CONN     = 3'd4;
parameter STATE_ERROR         = 3'd5;

reg [2:0]                       state, next_state;

// 内部寄存器
reg [31:0]                      header_buffer [0:3];
reg [2:0]                       header_read_cnt;
reg [5:0]                       current_conn;
reg [4:0]                       conn_word_count;
reg [31:0]                      conn_buffer [0:10];

// 循环变量声明
integer i;
integer j;

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
            if (header_read_cnt >= 3'd4)
                next_state = STATE_PARSE_HEADER;
                
        STATE_PARSE_HEADER:
            next_state = STATE_READY;
                
        STATE_READY:
            if (read_connection && conn_index < header_connections)
                next_state = STATE_READ_CONN;
                
        STATE_READ_CONN:
            if (conn_word_count >= 5'd11)
                next_state = STATE_READY;
                
        STATE_ERROR:
            if (!start_read)
                next_state = STATE_IDLE;
                
        default:
            next_state = STATE_IDLE;
    endcase
end

//=============================================================================
// 状态机 - 时序逻辑
//=============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        mem_addr <= 32'h0;
        header_read_cnt <= 3'b0;
        current_conn <= 6'h0;
        conn_word_count <= 5'h0;
    end else begin
        state <= next_state;
        
        case (next_state)
            STATE_IDLE: begin
                mem_addr <= 32'h0;
                header_read_cnt <= 3'b0;
                current_conn <= 6'h0;
                conn_word_count <= 5'h0;
            end
            
            STATE_READ_HEADER: begin
                if (header_read_cnt < 3'd4) begin
                    mem_addr <= (header_read_cnt << 2);
                    header_read_cnt <= header_read_cnt + 1;
                end
            end
            
            STATE_PARSE_HEADER: begin
                mem_addr <= mem_addr;
            end
            
            STATE_READY: begin
                mem_addr <= 32'h0;
            end
            
            STATE_READ_CONN: begin
                if (conn_word_count < 5'd11) begin
                    mem_addr <= 16 + (conn_index * 44) + (conn_word_count << 2);
                    conn_word_count <= conn_word_count + 1;
                end
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
        conn_local_ip <= 32'h0;
        conn_peer_ip <= 32'h0;
        conn_local_port <= 16'h0;
        conn_peer_port <= 16'h0;
        conn_local_qp <= 16'h0;
        conn_peer_qp <= 16'h0;
        conn_local_mac <= 48'h0;
        conn_peer_mac <= 48'h0;
        conn_up <= 1'b0;
        conn_valid <= 1'b0;
        
        // 初始化缓冲区
        for (i = 0; i < 4; i = i + 1) begin
            header_buffer[i] <= 32'h0;
        end
        for (j = 0; j < 11; j = j + 1) begin
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
                
                if (header_read_cnt > 0) begin
                    header_buffer[header_read_cnt-1] <= mem_data;
                end
            end
            
            STATE_PARSE_HEADER: begin
                busy <= 1'b1;
                
                header_magic <= header_buffer[0];
                header_version <= header_buffer[1];
                header_connections <= header_buffer[2];
                header_timestamp <= header_buffer[3];
                
                if (header_buffer[0] == 32'h41544746) begin
                    config_valid <= 1'b1;
                    parse_error <= 1'b0;
                end else begin
                    config_valid <= 1'b0;
                    parse_error <= 1'b1;
                end
            end
            
            STATE_READY: begin
                busy <= 1'b0;
                config_valid <= 1'b1;
            end
            
            STATE_READ_CONN: begin
                busy <= 1'b1;
                config_valid <= 1'b1;
                
                if (conn_word_count > 0) begin
                    conn_buffer[conn_word_count-1] <= mem_data;
                end
                
                if (conn_word_count >= 5'd11) begin
                    conn_switch_id <= conn_buffer[0];
                    conn_host_id <= conn_buffer[1];
                    conn_local_ip <= conn_buffer[2];
                    conn_peer_ip <= conn_buffer[3];
                    
                    conn_local_port <= conn_buffer[4][15:0];
                    conn_peer_port <= conn_buffer[4][31:16];
                    
                    conn_local_qp <= conn_buffer[5][15:0];
                    conn_peer_qp <= conn_buffer[5][31:16];
                    
                    conn_local_mac <= {conn_buffer[6][7:0],
                                      conn_buffer[6][15:8],
                                      conn_buffer[6][23:16],
                                      conn_buffer[6][31:24],
                                      conn_buffer[7][7:0],
                                      conn_buffer[7][15:8]};
                    
                    conn_peer_mac <= {conn_buffer[7][23:16],
                                     conn_buffer[7][31:24],
                                     conn_buffer[8][7:0],
                                     conn_buffer[8][15:8],
                                     conn_buffer[8][23:16],
                                     conn_buffer[8][31:24]};
                    
                    conn_up <= conn_buffer[9][7:0];
                    conn_valid <= 1'b1;
                end
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