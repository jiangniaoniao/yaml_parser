`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_routing_table_reader
// Description: 测试台 for routing_table_reader 模块
//////////////////////////////////////////////////////////////////////////////////

module tb_routing_table_reader();

//=============================================================================
// 参数定义
//=============================================================================
parameter CLK_PERIOD = 10;  // 100MHz时钟
parameter BIN_FILE = "fpga_config_routing.bin";
parameter ROM_DEPTH = 2048;

//=============================================================================
// 信号定义
//=============================================================================
reg                              clk;
reg                              rst_n;

// 控制接口
reg                              start_read;
wire                             busy;
wire                             tables_valid;
wire                             parse_error;

// Host Table Header
wire [31:0]                      host_magic;
wire [31:0]                      host_count;

// Host查询接口
reg  [5:0]                       host_index;
reg                              read_host;

// Host输出
wire [31:0]                      host_ip;
wire [31:0]                      host_switch_id;
wire [31:0]                      host_switch_ip;
wire [15:0]                      host_port;
wire [15:0]                      host_qp;
wire [47:0]                      host_mac;
wire                             host_valid;

// Switch Path Table Header
wire [31:0]                      switch_magic;
wire [31:0]                      switch_count;
wire [31:0]                      max_switch_id;

// Path查询接口
reg  [3:0]                       src_switch_id;
reg  [3:0]                       dst_switch_id;
reg                              read_path;

// Path输出
wire                             path_valid_flag;
wire [7:0]                       path_next_hop_switch;
wire [15:0]                      path_out_port;
wire [15:0]                      path_out_qp;
wire [15:0]                      path_distance;
wire [31:0]                      path_next_hop_ip;
wire [15:0]                      path_next_hop_port;
wire [15:0]                      path_next_hop_qp;
wire                             path_data_valid;

// 存储器接口
wire [31:0]                      mem_addr;
reg  [31:0]                      mem_data;

// 二进制文件ROM
reg [7:0]                        file_data [0:ROM_DEPTH-1];
reg [31:0]                       actual_file_size;
reg                              file_loaded;

// 整数变量声明
integer i;
integer j;
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
    host_index = 6'h0;
    read_host = 1'b0;
    src_switch_id = 4'h0;
    dst_switch_id = 4'h0;
    read_path = 1'b0;
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

    $display("=== Routing Table Binary File Loaded ===");
    $display("File: %s", BIN_FILE);
    $display("Size: %0d bytes", actual_file_size);

    // 打印前32字节用于调试 (Host Table Header + 第一个Host Entry的前16字节)
    $display("First 32 bytes (Host Table Header + partial entry):");
    for (i = 0; i < 32; i = i + 4) begin
        $display("  [%0d] 0x%08x", i,
                {file_data[i+3], file_data[i+2], file_data[i+1], file_data[i]});
    end
    $display("=========================================");
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
routing_table_reader #(
    .MAX_HOSTS(64),
    .MAX_SWITCHES(16),
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32)
) u_dut (
    .clk                    (clk),
    .rst_n                  (rst_n),

    // 存储器接口
    .mem_addr               (mem_addr),
    .mem_data               (mem_data),

    // 控制接口
    .start_read             (start_read),
    .busy                   (busy),
    .tables_valid           (tables_valid),
    .parse_error            (parse_error),

    // Host Table Header
    .host_magic             (host_magic),
    .host_count             (host_count),

    // Host查询
    .host_index             (host_index),
    .read_host              (read_host),

    // Host输出
    .host_ip                (host_ip),
    .host_switch_id         (host_switch_id),
    .host_switch_ip         (host_switch_ip),
    .host_port              (host_port),
    .host_qp                (host_qp),
    .host_mac               (host_mac),
    .host_valid             (host_valid),

    // Switch Path Table Header
    .switch_magic           (switch_magic),
    .switch_count           (switch_count),
    .max_switch_id          (max_switch_id),

    // Path查询
    .src_switch_id          (src_switch_id),
    .dst_switch_id          (dst_switch_id),
    .read_path              (read_path),

    // Path输出
    .path_valid_flag        (path_valid_flag),
    .path_next_hop_switch   (path_next_hop_switch),
    .path_out_port          (path_out_port),
    .path_out_qp            (path_out_qp),
    .path_distance          (path_distance),
    .path_next_hop_ip       (path_next_hop_ip),
    .path_next_hop_port     (path_next_hop_port),
    .path_next_hop_qp       (path_next_hop_qp),
    .path_data_valid        (path_data_valid)
);

//=============================================================================
// 辅助函数: IP地址转换
//=============================================================================
function [8*16-1:0] ip_to_string;
    input [31:0] ip;
    reg [7:0] b0, b1, b2, b3;
    begin
        b0 = ip[31:24];
        b1 = ip[23:16];
        b2 = ip[15:8];
        b3 = ip[7:0];
        // 简化显示，实际使用时可能需要格式化
        ip_to_string = ip;
    end
endfunction

//=============================================================================
// 测试序列
//=============================================================================
initial begin
    // 等待文件加载和复位完成
    wait(file_loaded);
    #(CLK_PERIOD * 10);

    $display("\n========================================");
    $display("=== Routing Table Reader Test Start ===");
    $display("========================================\n");

    // =========================================================================
    // 测试1: 读取两个表的Header
    // =========================================================================
    $display("Step 1: Reading routing table headers...");
    start_read = 1'b1;
    #(CLK_PERIOD * 2);
    start_read = 1'b0;

    // 等待解析完成
    wait(tables_valid === 1'b1 || parse_error === 1'b1);
    #(CLK_PERIOD * 10);

    if (tables_valid === 1'b1) begin
        $display("\n✓ Routing table headers loaded successfully!");
        $display("\n--- Host Table ---");
        $display("  Magic: 0x%08x", host_magic);
        $display("  Host Count: %0d", host_count);

        $display("\n--- Switch Path Table ---");
        $display("  Magic: 0x%08x", switch_magic);
        $display("  Switch Count: %0d", switch_count);
        $display("  Max Switch ID: %0d", max_switch_id);
        $display("  Array Dimension: %0d × %0d", max_switch_id+1, max_switch_id+1);
    end else begin
        $display("\n✗ ERROR: Failed to load routing table headers");
        $finish;
    end

    #(CLK_PERIOD * 20);

    // =========================================================================
    // 测试2: 读取所有Host Entries
    // =========================================================================
    if (host_count > 0) begin
        $display("\n========================================");
        $display("Step 2: Reading all host entries...");
        $display("========================================");

        for (i = 0; i < host_count; i = i + 1) begin
            $display("\n--- Reading Host Entry %0d ---", i);
            host_index = i[5:0];
            read_host = 1'b1;
            #(CLK_PERIOD * 2);
            read_host = 1'b0;

            wait(host_valid === 1'b1);
            #(CLK_PERIOD * 5);

            // 显示主机信息
            $display("  Host IP:       %0d.%0d.%0d.%0d",
                    host_ip[31:24], host_ip[23:16], host_ip[15:8], host_ip[7:0]);
            $display("  Switch ID:     %0d", host_switch_id);
            $display("  Switch IP:     %0d.%0d.%0d.%0d",
                    host_switch_ip[31:24], host_switch_ip[23:16],
                    host_switch_ip[15:8], host_switch_ip[7:0]);
            $display("  Port:          %0d", host_port);
            $display("  QP:            %0d", host_qp);
            $display("  MAC:           %012x", host_mac);

            #(CLK_PERIOD * 10);
        end
    end

    #(CLK_PERIOD * 20);

    // =========================================================================
    // 测试3: 读取有效的Switch Path Entries
    // =========================================================================
    $display("\n========================================");
    $display("Step 3: Reading switch path entries...");
    $display("========================================");

    // 遍历所有可能的路径
    for (i = 0; i <= max_switch_id; i = i + 1) begin
        for (j = 0; j <= max_switch_id; j = j + 1) begin
            if (i != j) begin  // 跳过到自己的路径
                $display("\n--- Reading Path Entry [%0d → %0d] ---", i, j);
                src_switch_id = i[3:0];
                dst_switch_id = j[3:0];
                read_path = 1'b1;
                #(CLK_PERIOD * 2);
                read_path = 1'b0;

                wait(path_data_valid === 1'b1);
                #(CLK_PERIOD * 5);

                // 显示路径信息
                if (path_valid_flag) begin
                    $display("  ✓ Valid Path Found!");
                    $display("    Next Hop Switch: %0d", path_next_hop_switch);
                    $display("    Out Port:        %0d", path_out_port);
                    $display("    Out QP:          %0d", path_out_qp);
                    $display("    Distance:        %0d hops", path_distance);
                    $display("    Next Hop IP:     %0d.%0d.%0d.%0d",
                            path_next_hop_ip[31:24], path_next_hop_ip[23:16],
                            path_next_hop_ip[15:8], path_next_hop_ip[7:0]);
                    $display("    Next Hop Port:   %0d", path_next_hop_port);
                    $display("    Next Hop QP:     %0d", path_next_hop_qp);
                end else begin
                    $display("  ✗ No valid path");
                end

                #(CLK_PERIOD * 10);
            end
        end
    end

    #(CLK_PERIOD * 50);

    $display("\n========================================");
    $display("=== All Tests Complete ===");
    $display("========================================\n");
    $finish;
end

//=============================================================================
// 波形文件生成
//=============================================================================
initial begin
    $dumpfile("tb_routing_table_reader.vcd");
    $dumpvars(0, tb_routing_table_reader);
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
    #(CLK_PERIOD * 100000);  // 100000个时钟周期后超时
    $display("TEST TIMEOUT!");
    $finish;
end

endmodule
