# 统一路由系统测试指南

## 文件清单

### Verilog模块
- `unified_routing_engine.v` - CAM查找引擎（核心）
- `unified_table_reader.v` - 二进制文件读取器
- `unified_routing_top.v` - 顶层集成模块
- `tb_unified_routing.v` - 测试台

### 生成的二进制文件
- `fpga_config_routing.bin` - 统一路由表（624字节，包含3个Switch的表）

## 在Vivado中测试步骤

### 1. 准备工作

```bash
# 确保二进制文件在项目根目录
cd /home/jiangniaoniao/yaml_parser
ls -l fpga_config_routing.bin
# 应该看到：-rw-rw-r-- 1 ... 624 ... fpga_config_routing.bin
```

### 2. 创建Vivado项目

1. 打开Vivado
2. 创建新的RTL项目（Create Project）
3. 添加源文件：
   - `Verilog/unified_routing_engine.v`
   - `Verilog/unified_table_reader.v`
   - `Verilog/unified_routing_top.v`
4. 添加仿真文件：
   - `Verilog/tb_unified_routing.v`（设置为Top Module）

### 3. 配置仿真

在Vivado中设置仿真参数：

**方法A：在TCL Console中设置**
```tcl
# 设置仿真工作目录为项目根目录（包含.bin文件的位置）
set_property -name {xsim.simulate.runtime} -value {100us} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.custom_tcl} -value {/home/jiangniaoniao/yaml_parser} -objects [get_filesets sim_1]
```

**方法B：复制二进制文件到仿真目录**
```bash
# 找到Vivado仿真目录（通常是）
# <project_dir>/<project_name>.sim/sim_1/behav/xsim/

# 复制二进制文件到仿真目录
cp fpga_config_routing.bin <vivado_sim_dir>/
```

### 4. 运行仿真

#### 测试Switch 1（根交换机）

在`tb_unified_routing.v`中设置：
```verilog
parameter TEST_SWITCH_ID = 1;
```

**预期结果**：
- ✓ Switch 2 IP (10.50.183.114) → 直连，port=4791, QP=28
- ✓ Switch 3 IP (10.50.183.98) → 直连，port=4791, QP=29
- ✓ Host 1 (10.50.183.250) → 路由到Switch 2，port=4791, QP=28
- ✓ Host 3 (10.50.183.125) → 路由到Switch 3，port=4791, QP=29

#### 测试Switch 2（中间交换机）

在`tb_unified_routing.v`中设置：
```verilog
parameter TEST_SWITCH_ID = 2;
```

**预期结果**：
- ✓ Host 1 (10.50.183.250) → 直连，port=23333, QP=28, MAC=52:54:00:cd:f4:99
- ✓ Host 2 (10.50.183.8) → 直连，port=23334, QP=29, MAC=52:54:00:16:fd:30
- ✓ Host 3 (10.50.183.125) → 默认路由向上，port=4791, QP=17, next_hop=10.50.183.11 (Switch 1)
- ✓ Host 4 (10.50.183.221) → 默认路由向上，port=4791, QP=17

#### 测试Switch 3（中间交换机）

在`tb_unified_routing.v`中设置：
```verilog
parameter TEST_SWITCH_ID = 3;
```

**预期结果**：
- ✓ Host 3 (10.50.183.125) → 直连，port=23335, QP=30, MAC=52:54:00:b5:1f:cc
- ✓ Host 4 (10.50.183.221) → 直连，port=23336, QP=31, MAC=52:54:00:5c:de:f2
- ✓ Host 1 (10.50.183.250) → 默认路由向上，port=4791, QP=17
- ✓ Host 2 (10.50.183.8) → 默认路由向上，port=4791, QP=17

### 5. 查看波形

在Vivado中：
1. Run Simulation
2. 打开Wave窗口
3. 添加关键信号：
   - `dut/init_state` - 初始化状态机
   - `lookup_valid`, `lookup_dst_ip` - 查找请求
   - `resp_valid`, `resp_found` - 查找结果
   - `resp_out_port`, `resp_out_qp` - 输出端口和QP
   - `resp_next_hop_mac` - 下一跳MAC地址
   - `resp_is_direct_host` - 直连标志

### 6. 检查控制台输出

查看Vivado TCL Console的输出，应该看到类似：

```
========================================
[INIT] 统一路由系统初始化开始
[INIT] 交换机ID: 1
[INIT] 路由表文件: fpga_config_routing.bin
========================================
[INFO] 开始读取统一路由表: fpga_config_routing.bin
[INFO] 目标Switch ID: 1
[INFO] Header解析完成:
       Magic: 0x44455354 (应为0x44455354='DEST')
       Entry Count: 6
       Switch ID: 1
[INFO] 找到目标Switch 1的路由表，开始加载...
[INFO] 加载Entry 0: dst_ip=0x0a32b772, valid=1
[INFO] 加载Entry 1: dst_ip=0x0a32b762, valid=1
...
[INIT] 初始化完成，系统进入运行模式
========================================

[TEST] 测试: Switch 2 IP (10.50.183.114) - 应为直连
       查找目标IP: 10.50.183.114
       ✓ 查找成功!
       - 输出端口: 4791
       - 输出QP: 28
       ...
```

## 性能验证

### 查找延迟
- **目标**: 2 cycles
- **验证**: 在波形中测量从`lookup_valid`拉高到`resp_valid`拉高的延迟

### 流水线吞吐量
- **目标**: 每周期1次查找
- **验证**: 连续发送3个查找请求，观察每周期都有结果输出

## 常见问题

### 问题1：找不到二进制文件
```
[ERROR] 无法打开文件: fpga_config_routing.bin
```

**解决方案**：
1. 确认文件在正确路径
2. 复制文件到Vivado仿真目录
3. 或在`unified_table_reader.v`中修改`FILENAME`参数为绝对路径

### 问题2：初始化失败
```
[ERROR] Magic校验失败!
```

**解决方案**：
重新生成二进制文件：
```bash
./bin/yaml2fpga --unified topology-tree.yaml
```

### 问题3：查找失败
```
✗ 查找失败 - 未找到路由
```

**可能原因**：
1. IP地址不在路由表中
2. Switch ID设置错误
3. 初始化未完成

## 与旧版本对比测试

可以同时运行新旧两个版本进行对比：

| 指标 | 旧版（routing_system_top.v） | 新版（unified_routing_top.v） |
|------|----------------------------|------------------------------|
| 查找延迟 | 5 cycles | **2 cycles** |
| BRAM消耗 | ~60 KB | **~2 KB** |
| 查找方式 | index查找 | **IP直接查找** |
| 支持广播 | ❌ | **✅** |

## 下一步测试

测试成功后，可以：
1. 增加更多Host测试大规模拓扑
2. 测试AllReduce广播功能
3. 与container_inc-master的软件实现对比性能
4. 综合到真实FPGA测试时序和资源消耗

## 资源消耗估算（Xilinx 7系列）

| 资源 | 预估消耗 | 说明 |
|------|---------|------|
| LUTs | ~2500 | CAM比较器阵列 |
| FFs | ~500 | 流水线寄存器 |
| BRAM_18K | 2 | Entry存储 |
| 最大频率 | >200 MHz | 关键路径短 |

---

**测试完成后，请报告结果，我们将进行性能分析和优化。**
