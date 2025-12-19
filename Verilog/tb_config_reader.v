`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 20:50:44
// Design Name: 
// Module Name: tb_config_reader
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


module tb_config_reader();

//=============================================================================
// 参数定义
//=============================================================================
parameter CLK_PERIOD = 10;  // 100MHz时钟
parameter BIN_FILE = "fpga_config.bin";
parameter ROM_DEPTH = 512;

//=============================================================================
// 信号定义
//=============================================================================
reg                              clk;
reg                              rst_n;

// 控制接口
reg                               start_read;
wire                              busy;
wire                              config_valid;
wire                              parse_error;

// 文件头寄存器
wire [31:0]                      header_magic;
wire [31:0]                      header_version;
wire [31:0]                      header_connections;
wire [31:0]                      header_timestamp;

// 连接查询接口
reg        [5:0]                  conn_index;
reg                               read_connection;

// 连接寄存器输出
wire       [31:0]                  conn_switch_id;
wire       [31:0]                  conn_my_ip;
wire       [31:0]                  conn_peer_ip;
wire       [15:0]                  conn_my_port;
wire       [15:0]                  conn_peer_port;
wire       [47:0]                  conn_my_mac;
wire       [47:0]                  conn_peer_mac;
wire                               conn_valid;

// 存储器接口
wire [31:0]                       mem_addr;
reg [31:0]                        mem_data;

// 二进制文件ROM
reg [7:0]                         file_data [0:ROM_DEPTH-1];
reg [31:0]                        actual_file_size;
reg                               file_loaded;

// 整数变量声明
integer i;
integer fd;
integer bytes_read;
integer byte_val;

//=============================================================================
// 时钟生成
//=============================================================================
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

//=============================================================================
// 复位序列
//=============================================================================
initial begin
    rst_n = 1'b0;
    start_read = 1'b0;
    conn_index = 6'h0;
    read_connection = 1'b0;
    mem_data = 32'h0;
    file_loaded = 1'b0;
    actual_file_size = 32'h0;
    
    #(CLK_PERIOD * 10);
    rst_n = 1'b1;
    #(CLK_PERIOD * 5);
end

//=============================================================================
// 加载二进制文件
//=============================================================================
initial begin
    // 等待复位完成
    @(posedge rst_n);
    #(CLK_PERIOD);
    
    fd = $fopen(BIN_FILE, "rb");
    if (fd == 0) begin
        $display("ERROR: Cannot open file %s", BIN_FILE);
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
    
    $display("=== Binary File Loaded ===");
    $display("File: %s", BIN_FILE);
    $display("Size: %0d bytes", actual_file_size);
    
    // 打印前16字节用于调试
    $display("First 16 bytes:");
    for (i = 0; i < 16; i = i + 4) begin
        $display("  [%0d] 0x%08x", i, 
                {file_data[i+3], file_data[i+2], file_data[i+1], file_data[i]});
    end
    $display("==========================");
end

//=============================================================================
// 存储器读取逻辑（组合逻辑）
//=============================================================================
always @(mem_addr or rst_n or file_loaded or actual_file_size) begin
    if (rst_n === 1'b0) begin
        mem_data = 32'h0;
    end else if (file_loaded === 1'b1 && mem_addr < actual_file_size) begin
        if ((mem_addr + 3) < actual_file_size) begin
            mem_data = {file_data[mem_addr+3], file_data[mem_addr+2], 
                       file_data[mem_addr+1], file_data[mem_addr]};
        end else begin
            // 如果地址不是4字节对齐，返回0
            mem_data = 32'h0;
        end
    end else begin
        mem_data = 32'h0;
    end
end

//=============================================================================
// DUT实例化
//=============================================================================
fpga_config_reader #(
    .MAX_CONNECTIONS(64),
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32)
) u_dut (
    .clk                (clk),
    .rst_n              (rst_n),
    
    // 存储器接口
    .mem_addr           (mem_addr),
    .mem_data           (mem_data),
    
    // 控制接口
    .start_read         (start_read),
    .busy               (busy),
    .config_valid        (config_valid),
    .parse_error        (parse_error),
    
    // 文件头输出
    .header_magic        (header_magic),
    .header_version      (header_version),
    .header_connections  (header_connections),
    .header_timestamp    (header_timestamp),
    
    // 连接查询
    .conn_index         (conn_index),
    .read_connection    (read_connection),
    
    // 连接寄存器输出（新结构）
    .conn_switch_id     (conn_switch_id),
    .conn_my_ip      (conn_my_ip),
    .conn_peer_ip       (conn_peer_ip),
    .conn_my_port    (conn_my_port),
    .conn_peer_port     (conn_peer_port),
    .conn_my_mac     (conn_my_mac),
    .conn_peer_mac      (conn_peer_mac),
    .conn_valid         (conn_valid)
);

//=============================================================================
// 测试序列
//=============================================================================
initial begin
    // 等待文件加载和复位完成
    wait(file_loaded);
    #(CLK_PERIOD * 10);
    
    $display("\n=== Test Start ===");
    
    // 测试1: 读取配置头部
    $display("Step 1: Reading configuration header...");
    start_read = 1'b1;
    #(CLK_PERIOD * 2);
    start_read = 1'b0;
    
    // 等待读取完成
    wait(config_valid === 1'b1 || parse_error === 1'b1);
    #(CLK_PERIOD * 10);
    
    if (config_valid === 1'b1) begin
        $display("Configuration header loaded successfully!");
        $display("  Magic: 0x%08x", header_magic);
        $display("  Version: %0d", header_version);
        $display("  Connections: %0d", header_connections);
        $display("  Timestamp: 0x%08x", header_timestamp);
    end else begin
        $display("ERROR: Failed to load configuration header");
        $finish;
    end
    
    #(CLK_PERIOD * 20);
    
    // 测试2: 读取连接0
    if (header_connections > 0) begin
        $display("\nStep 2: Reading connection 0...");
        conn_index = 6'h0;
        read_connection = 1'b1;
        #(CLK_PERIOD * 2);
        read_connection = 1'b0;
        
        wait(conn_valid === 1'b1);
        #(CLK_PERIOD * 5);
        
        $display("Connection 0 data:");
        $display("  Switch ID: %0d", conn_switch_id);
        $display("  Local IP: 0x%08x", conn_my_ip);
        $display("  Peer IP: 0x%08x", conn_peer_ip);
        $display("  Local Port: %0d (0x%04x)", conn_my_port, conn_my_port);
        $display("  Peer Port: %0d (0x%04x)", conn_peer_port, conn_peer_port);
        $display("  Local MAC: %012x", conn_my_mac);
        $display("  Peer MAC: %012x", conn_peer_mac);
        
        // 以冒号分隔的格式显示MAC地址
        $display("  Local MAC (formatted): %02x:%02x:%02x:%02x:%02x:%02x",
                conn_my_mac[47:40],
                conn_my_mac[39:32],
                conn_my_mac[31:24],
                conn_my_mac[23:16],
                conn_my_mac[15:8],
                conn_my_mac[7:0]);
        $display("  Peer MAC (formatted): %02x:%02x:%02x:%02x:%02x:%02x",
                conn_peer_mac[47:40],
                conn_peer_mac[39:32],
                conn_peer_mac[31:24],
                conn_peer_mac[23:16],
                conn_peer_mac[15:8],
                conn_peer_mac[7:0]);
    end
    
    #(CLK_PERIOD * 20);
    
    // 测试3: 读取连接1
    if (header_connections > 1) begin
        $display("\nStep 3: Reading connection 1...");
        conn_index = 6'h1;
        read_connection = 1'b1;
        #(CLK_PERIOD * 2);
        read_connection = 1'b0;
        
        wait(conn_valid === 1'b1);
        #(CLK_PERIOD * 5);
        
        $display("Connection 1 data:");
       $display("  Switch ID: %0d", conn_switch_id);
        $display("  Local IP: 0x%08x", conn_my_ip);
        $display("  Peer IP: 0x%08x", conn_peer_ip);
        $display("  Local Port: %0d (0x%04x)", conn_my_port, conn_my_port);
        $display("  Peer Port: %0d (0x%04x)", conn_peer_port, conn_peer_port);
        $display("  Local MAC: %012x", conn_my_mac);
        $display("  Peer MAC: %012x", conn_peer_mac);
        
        // 以冒号分隔的格式显示MAC地址
        $display("  Local MAC (formatted): %02x:%02x:%02x:%02x:%02x:%02x",
                conn_my_mac[47:40],
                conn_my_mac[39:32],
                conn_my_mac[31:24],
                conn_my_mac[23:16],
                conn_my_mac[15:8],
                conn_my_mac[7:0]);
        $display("  Peer MAC (formatted): %02x:%02x:%02x:%02x:%02x:%02x",
                conn_peer_mac[47:40],
                conn_peer_mac[39:32],
                conn_peer_mac[31:24],
                conn_peer_mac[23:16],
                conn_peer_mac[15:8],
                conn_peer_mac[7:0]);
    end
    
    #(CLK_PERIOD * 20);
    
    // 测试4: 测试连续读取所有连接
    if (header_connections > 0) begin
        $display("\nStep 4: Testing all connections...");
        for (i = 0; i < header_connections; i = i + 1) begin
            conn_index = i;
            read_connection = 1'b1;
            #(CLK_PERIOD * 2);
            read_connection = 1'b0;
            
            wait(conn_valid === 1'b1);
            #(CLK_PERIOD * 5);
            
            $display("Connection %0d: Switch=%d, LocalPort=%d, PeerPort=%d", 
                    i, conn_switch_id, conn_my_port, conn_peer_port);
        end
    end
    
    #(CLK_PERIOD * 50);
    
    $display("\n=== Test Complete ===");
    $finish;
end

//=============================================================================
// 波形文件生成
//=============================================================================
initial begin
    $dumpfile("tb_config_reader.vcd");
    $dumpvars(0, tb_config_reader);
end

//=============================================================================
// 监控关键信号
//=============================================================================
always @(posedge clk) begin
    if (busy === 1'b1) begin
        $display("Time %0t: state=%d, mem_addr=0x%08x, mem_data=0x%08x", 
                 $time, u_dut.state, mem_addr, mem_data);
    end
end

//=============================================================================
// 超时保护
//=============================================================================
initial begin
    #(CLK_PERIOD * 50000);  // 5000个时钟周期后超时
    $display("TEST TIMEOUT!");
    $finish;
end

endmodule