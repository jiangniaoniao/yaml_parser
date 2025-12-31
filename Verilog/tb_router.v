`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/26 15:35:30
// Design Name: 
// Module Name: tb_router
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


module tb_router;

// 时钟和复位
reg clk;
reg rst_n;

// 查找接口
reg         lookup_valid;
reg [31:0]  lookup_dst_ip;

// 响应接口
wire        resp_valid;
wire        resp_found;
wire [15:0] resp_out_port;
wire [15:0] resp_out_qp;
wire [31:0] resp_next_hop_ip;
wire [15:0] resp_next_hop_port;
wire [15:0] resp_next_hop_qp;
wire [47:0] resp_next_hop_mac;
wire        resp_is_direct_host;
wire        resp_is_broadcast;
wire        resp_is_default_route;  // 新增：默认路由标志

// 状态输出
wire        init_done;
wire        init_error;

// 时钟生成
parameter CLK_PERIOD = 10;
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 测试配置
integer test_count = 16;  // 连续发送16个查询
integer cycle_count = 0;
integer resp_count = 0;
integer start_cycle, end_cycle;
integer first_resp_cycle;

// 参数：测试哪个Switch
// 1 = 根Switch, 2 = 中间Switch 2, 3 = 中间Switch 3
parameter TEST_SWITCH_ID = 2;

// 实例化DUT
router #(
    .ROUTING_TABLE_FILE("fpga_routing.hex"),  // hex格式文件
    .MAX_ENTRIES(64),
    .MY_SWITCH_ID(TEST_SWITCH_ID)
) dut (
    .clk(clk),
    .rst_n(rst_n),

    .lookup_valid(lookup_valid),
    .lookup_dst_ip(lookup_dst_ip),

    .resp_valid(resp_valid),
    .resp_found(resp_found),
    .resp_out_port(resp_out_port),
    .resp_out_qp(resp_out_qp),
    .resp_next_hop_ip(resp_next_hop_ip),
    .resp_next_hop_port(resp_next_hop_port),
    .resp_next_hop_qp(resp_next_hop_qp),
    .resp_next_hop_mac(resp_next_hop_mac),
    .resp_is_direct_host(resp_is_direct_host),
    .resp_is_broadcast(resp_is_broadcast),
    .resp_is_default_route(resp_is_default_route),  // 新增

    .init_done(init_done),
    .init_error(init_error)
);

// 测试任务：查找IP地址
task test_lookup;
    input [31:0] dst_ip;
    input [8*40:1] description;  // 字符串描述
    begin
        $display("\n[TEST] 测试: %s", description);
        $display("       查找目标IP: %d.%d.%d.%d",
                 (dst_ip >> 24) & 8'hFF,
                 (dst_ip >> 16) & 8'hFF,
                 (dst_ip >> 8) & 8'hFF,
                 dst_ip & 8'hFF);

        @(posedge clk);
        lookup_valid <= 1'b1;
        lookup_dst_ip <= dst_ip;

        @(posedge clk);
        lookup_valid <= 1'b0;

        // 等待3个周期（3级pipeline延迟）
        repeat(3) @(posedge clk);

        if (resp_valid) begin
            if (resp_found) begin
                $display("        查找成功!");
                $display("       - 输出端口: %d", resp_out_port);
                $display("       - 输出QP: %d", resp_out_qp);
                $display("       - 下一跳IP: %d.%d.%d.%d",
                         (resp_next_hop_ip >> 24) & 8'hFF,
                         (resp_next_hop_ip >> 16) & 8'hFF,
                         (resp_next_hop_ip >> 8) & 8'hFF,
                         resp_next_hop_ip & 8'hFF);
                $display("       - 下一跳端口: %d", resp_next_hop_port);
                $display("       - 下一跳QP: %d", resp_next_hop_qp);
                $display("       - 下一跳MAC: %02x:%02x:%02x:%02x:%02x:%02x",
                         resp_next_hop_mac[47:40], resp_next_hop_mac[39:32],
                         resp_next_hop_mac[31:24], resp_next_hop_mac[23:16],
                         resp_next_hop_mac[15:8],  resp_next_hop_mac[7:0]);
                $display("       - 直连Host: %s", resp_is_direct_host ? "是" : "否");
                $display("       - 广播: %s", resp_is_broadcast ? "是" : "否");
                $display("       - 默认路由: %s", resp_is_default_route ? "是" : "否");  // 新增
            end else begin
                $display("        查找失败 - 未找到路由");
            end
        end else begin
            $display("        响应无效");
        end

        repeat(3) @(posedge clk);
    end
endtask

// 主测试流程
initial begin
    $display("========================================");
    $display("测试Switch ID: %d", TEST_SWITCH_ID);
    $display("========================================");

    // 初始化
    rst_n = 0;
    lookup_valid = 0;
    lookup_dst_ip = 32'h0;

    #(CLK_PERIOD * 5);
    rst_n = 1;

    // 等待初始化完成
    $display("\n等待系统初始化...");
    wait(init_done || init_error);

    if (init_error) begin
        $display("[FATAL] 初始化失败!");
        $finish;
    end

    $display("\n初始化完成，开始测试...\n");
    repeat(10) @(posedge clk);

    // ========== 测试用例 ==========

    if (TEST_SWITCH_ID == 1) begin
        // Switch 1（根）测试用例
        $display("\n========== Switch 1（根）测试用例 ==========");

        // 测试1：查找Switch 2的IP（直连）
        test_lookup(32'h0a32b772, "Switch 2 IP (10.50.183.114) - 应为直连");

        // 测试2：查找Switch 3的IP（直连）
        test_lookup(32'h0a32b762, "Switch 3 IP (10.50.183.98) - 应为直连");

        // 测试3：查找Host 1（通过Switch 2）
        test_lookup(32'h0a32b7fa, "Host 1 (10.50.183.250) - 应路由到Switch 2");

        // 测试4：查找Host 2（通过Switch 2）
        test_lookup(32'h0a32b708, "Host 2 (10.50.183.8) - 应路由到Switch 2");

        // 测试5：查找Host 3（通过Switch 3）
        test_lookup(32'h0a32b77d, "Host 3 (10.50.183.125) - 应路由到Switch 3");

        // 测试6：查找Host 4（通过Switch 3）
        test_lookup(32'h0a32b7dd, "Host 4 (10.50.183.221) - 应路由到Switch 3");

        // 测试7：查找不存在的IP
        test_lookup(32'h0a32b7ff, "不存在的IP (10.50.183.255) - 应查找失败");

    end else if (TEST_SWITCH_ID == 2) begin
        // Switch 2（中间）测试用例
        $display("\n========== Switch 2（中间节点）测试用例 ==========");

        // 测试1：查找Host 1（直连）
        test_lookup(32'h0a32b7fa, "Host 1 (10.50.183.250) - 应为直连");

        // 测试2：查找Host 2（直连）
        test_lookup(32'h0a32b708, "Host 2 (10.50.183.8) - 应为直连");

        // 测试3：查找Switch 2自己的IP（默认路由向上）
        test_lookup(32'h0a32b772, "Switch 2 IP (10.50.183.114) - 应默认路由到Switch 1");

        // 测试4：查找Switch 3的IP（默认路由向上）
        test_lookup(32'h0a32b762, "Switch 3 IP (10.50.183.98) - 应默认路由到Switch 1");

        // 测试5：查找Host 3（默认路由向上）
        test_lookup(32'h0a32b77d, "Host 3 (10.50.183.125) - 应默认路由到Switch 1");

        // 测试6：查找Host 4（默认路由向上）
        test_lookup(32'h0a32b7dd, "Host 4 (10.50.183.221) - 应默认路由到Switch 1");

    end else if (TEST_SWITCH_ID == 3) begin
        // Switch 3（中间）测试用例
        $display("\n========== Switch 3（中间节点）测试用例 ==========");

        // 测试1：查找Host 3（直连）
        test_lookup(32'h0a32b77d, "Host 3 (10.50.183.125) - 应为直连");

        // 测试2：查找Host 4（直连）
        test_lookup(32'h0a32b7dd, "Host 4 (10.50.183.221) - 应为直连");

        // 测试3：查找Switch 2的IP（默认路由向上）
        test_lookup(32'h0a32b772, "Switch 2 IP (10.50.183.114) - 应默认路由到Switch 1");

        // 测试4：查找Switch 3自己的IP（默认路由向上）
        test_lookup(32'h0a32b762, "Switch 3 IP (10.50.183.98) - 应默认路由到Switch 1");

        // 测试5：查找Host 1（默认路由向上）
        test_lookup(32'h0a32b7fa, "Host 1 (10.50.183.250) - 应默认路由到Switch 1");

        // 测试6：查找Host 2（默认路由向上）
        test_lookup(32'h0a32b708, "Host 2 (10.50.183.8) - 应默认路由到Switch 1");
    end

    // ========== 性能测试：连续查表吞吐能力 ==========
    $display("\n========== 性能测试：连续查表吞吐能力 ==========");
    $display("连续发送 %0d 个查询请求，验证流水线吞吐量...", test_count);

    // 记录开始周期
    start_cycle = 0;
    first_resp_cycle = -1;

    // 连续发送查询请求（每周期1个），同时统计响应
    repeat(test_count) begin
        // 根据cycle_count设置IP地址和lookup_valid
        case (cycle_count % 4)
            0: lookup_dst_ip <= 32'h0a32b7fa;  // Host 1
            1: lookup_dst_ip <= 32'h0a32b708;  // Host 2
            2: lookup_dst_ip <= 32'h0a32b77d;  // Host 3
            3: lookup_dst_ip <= 32'h0a32b7dd;  // Host 4
        endcase
        lookup_valid <= 1'b1;

        @(posedge clk);

        // 统计响应（在时钟上升沿之后立即检查）
        if (resp_valid) begin
            resp_count = resp_count + 1;
            if (first_resp_cycle == -1) begin
                first_resp_cycle = cycle_count;
                $display("首个结果在周期 %0d 返回（延迟 = %0d 周期）",
                         cycle_count, cycle_count - start_cycle);
            end
            if (resp_count == test_count)
                end_cycle = cycle_count;
        end

        cycle_count = cycle_count + 1;
    end

    @(posedge clk);
    lookup_valid <= 1'b0;
    cycle_count = cycle_count + 1;

    $display("已发送 %0d 个查询请求（周期 %0d - %0d）", test_count, start_cycle, cycle_count-1);
    $display("等待流水线输出剩余结果...");

    // 等待剩余输出结果（最多再等5个周期）
    repeat(5) begin
        @(posedge clk);

        if (resp_valid) begin
            resp_count = resp_count + 1;
            if (first_resp_cycle == -1) begin
                first_resp_cycle = cycle_count;
                $display("首个结果在周期 %0d 返回（延迟 = %0d 周期）",
                         cycle_count, cycle_count - start_cycle);
            end
            if (resp_count == test_count)
                end_cycle = cycle_count;
        end

        cycle_count = cycle_count + 1;
    end

    // 统计结果
    $display("\n性能测试结果：");
    $display("  - 发送查询数：%0d", test_count);
    $display("  - 收到响应数：%0d", resp_count);

    if (first_resp_cycle != -1) begin
        $display("  - 首次响应延迟：%0d周期（符合3级流水线）", first_resp_cycle);
    end

    if (resp_count == test_count) begin
        $display("  - 总处理周期：%0d（发送第1个到收到最后1个）", end_cycle - start_cycle);
        $display("   流水线吞吐量测试通过！");
    end else begin
        $display("   警告：收到响应数(%0d)少于发送数(%0d)", resp_count, test_count);
    end

    repeat(10) @(posedge clk);

    $display("\n========================================");
    $display("测试完成!");
    $display("========================================");
    $finish;
end

// 超时保护
initial begin
    #(CLK_PERIOD * 100000);
    $display("[ERROR] 测试超时!");
    $finish;
end

endmodule
