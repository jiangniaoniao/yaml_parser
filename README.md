# YAML到FPGA路由配置转换系统

## 项目概述

本项目实现了一个**YAML-to-FPGA配置转换器和硬件路由查找系统**，用于将树形网络拓扑配置转换为FPGA可读的二进制格式，并提供高性能的硬件路由查找功能。

系统由两个主要组件构成：
1. **C语言转换器**：解析YAML拓扑文件，生成FPGA二进制配置
2. **Verilog硬件模块**：在FPGA上实现高速路由表查找

### 核心特性

- ✅ **树形拓扑优化**：专为树状网络结构设计的路由算法
- ✅ **CAM并行查找**：使用内容寻址存储器实现O(1)查找
- ✅ **3级流水线**：3时钟周期延迟，接近1查询/周期的吞吐量
- ✅ **完整路由信息**：单次查询返回端口、QP、下一跳IP/MAC等完整信息
- ✅ **广播支持预留**：架构已预留AllReduce广播功能接口

---

## 系统架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                   YAML拓扑配置文件                            │
│              (定义Switch、Host、连接关系)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  C语言转换器 (yaml2fpga)                      │
│  ┌──────────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │ YAML解析器   │→ │ 路由表生成器 │→ │ 二进制文件生成器 │   │
│  │ (libyaml)   │  │ (树形算法)  │  │  (按Switch分组)  │   │
│  └──────────────┘  └─────────────┘  └──────────────────┘   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────────┐
        │  fpga_routing.hex                │
        │  (每个Switch一个路由表)           │
        └──────────────┬───────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Verilog硬件模块 (FPGA)                       │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  router (顶层模块)                                   │   │
│  │  ┌────────────────────┐  ┌────────────────────────┐ │   │
│  │  │ router_reader      │ →│ router_searcher        │ │   │
│  │  │  (读取ROM初始化)    │  │   (CAM + BRAM查找)    │ │   │
│  │  └────────────────────┘  └────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  输入: dst_ip (32-bit)                                       │
│  输出: out_port, out_qp, next_hop_ip, next_hop_mac 等       │                                      
└─────────────────────────────────────────────────────────────┘
```

### 三级路由架构（方案3：树形拓扑优化）

本项目实现的是**统一目的地路由表**方案，每个交换机存储到所有目标Host的直接转发信息。

#### 与之前方案的对比

| 特性 |     两级查表      |    统一路由表     |
|-----|-------------------|------------------|
| 查表次数 | 2次 (Host表 + Path表) | **1次** |
| 存储需求 | Host表 + Switch²路径表 | N_hosts × 每个Switch |
| 查找延迟 | 6-8 cycles | **3 cycles** |
| 适用场景 | 任意拓扑 | **树形拓扑** |
| 扩展性 | Switch数量受限 | Host数量受限 |

---

## 目录结构

```
yaml_parser/
├── src/                        # C源代码
│   ├── main.c                  # 主程序入口
│   ├── yaml_parser.c           # YAML解析器
│   ├── fpga_converter.c        # 旧格式转换器（保留）
│   ├── flow_table.c            # 两级路由表生成器（保留）
│   └── unified_routing.c       # 统一路由表生成器 主要使用
│
├── include/
│   └── yaml2fpga.h             # 数据结构定义和函数声明
│
├── Verilog/                    # Verilog硬件模块
│   ├── router.v                # 顶层模块 
│   ├── router_reader.v         # 路由表读取器 
│   ├── router_seacher.v        # CAM查找引擎 
│   ├── tb_router.v             # 测试台 
│
├── topology-tree.yaml          # 示例拓扑配置文件
├── Makefile                    # 构建脚本
└── README.md                   # 本文档
```

---

## 快速开始

### 1. 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get install libyaml-dev

# 或使用 make
make deps
```

### 2. 编译C转换器

```bash
make
```

生成的可执行文件：`bin/yaml2fpga`

### 3. 转换YAML拓扑

```bash
# 使用默认配置文件
./bin/yaml2fpga topology-tree.yaml

# 指定输出文件名
./bin/yaml2fpga topology-tree.yaml my_routing.bin

# 只显示拓扑摘要，不生成文件
./bin/yaml2fpga --summary topology-tree.yaml
```

生成的输出文件：
- `fpga_routing_unified.bin` - 统一路由表（推荐使用）
- `fpga_config_routing.bin` - 两级路由表（兼容旧系统）

### 4. Verilog仿真测试

在Vivado或其他仿真器中：

1. 添加源文件：
   - `Verilog/unified_routing_top.v`
   - `Verilog/unified_table_reader.v`
   - `Verilog/unified_routing_engine.v`

2. 添加测试台：
   - `Verilog/tb_unified_routing.v`

3. 将生成的 `.bin` 文件放在仿真工作目录

4. 运行仿真

---

## YAML配置文件格式

### 示例

```yaml
switches:
  - id: 1
    root: true  # 必须有且仅有一个根节点
    connections:
      # 下行连接到子交换机
      - up: false
        host_id: 2
        my_ip: "10.50.183.11"
        my_mac: "52:54:00:79:05:f1"
        my_port: 4791
        my_qp: 28
        peer_ip: "10.50.183.12"
        peer_mac: "52:54:00:c2:11:88"
        peer_port: 4791
        peer_qp: 17

      # 下行连接到Host
      - up: false
        host_id: 9998
        my_ip: "10.50.183.11"
        my_mac: "52:54:00:79:05:f1"
        my_port: 4792
        my_qp: 29
        peer_ip: "10.50.183.250"
        peer_mac: "52:54:00:aa:bb:cc"
        peer_port: 4791
        peer_qp: 18

  - id: 2
    root: false
    connections:
      # 上行连接到父交换机
      - up: true
        host_id: 1
        my_ip: "10.50.183.12"
        my_mac: "52:54:00:c2:11:88"
        my_port: 4791
        my_qp: 17
        peer_ip: "10.50.183.11"
        peer_mac: "52:54:00:79:05:f1"
        peer_port: 4791
        peer_qp: 28

      # 下行连接到Host
      - up: false
        host_id: 9999
        my_ip: "10.50.183.12"
        my_mac: "52:54:00:c2:11:88"
        my_port: 4792
        my_qp: 18
        peer_ip: "10.50.183.8"
        peer_mac: "52:54:00:dd:ee:ff"
        peer_port: 4791
        peer_qp: 19
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | int | 交换机唯一ID（从1开始） |
| `root` | bool | 是否为根节点（全局唯一） |
| `up` | bool | `true`=上行链路, `false`=下行链路 |
| `host_id` | int | 对端设备ID |
| `my_ip` | string | 本端IP地址 |
| `my_mac` | string | 本端MAC地址（格式：xx:xx:xx:xx:xx:xx） |
| `my_port` | int | 本端RDMA端口号 |
| `my_qp` | int | 本端Queue Pair号 |
| `peer_*` | string/int | 对端对应信息 |

### 拓扑约束

1. **必须是树形拓扑**（无环）
2. **有且仅有一个根节点**（`root: true`）
3. **每个非根节点有且仅有一个上行链路**（`up: true`）
4. **Host通过下行链路连接**（`up: false`）

---

## 二进制文件格式

### 统一路由表格式 (`fpga_routing_unified.bin`)

文件包含所有交换机的路由表，每个交换机一个独立的表段。

#### 文件结构

```
┌─────────────────────────────────────────────────┐
│  Switch 1 路由表                                 │
│  ┌───────────────────────────────────────────┐  │
│  │ Header (16 bytes)                         │  │
│  │  - magic: 0x44455354 ("DEST")            │  │
│  │  - entry_count: uint32                   │  │
│  │  - switch_id: uint32                     │  │
│  │  - reserved: uint32                      │  │
│  ├───────────────────────────────────────────┤  │
│  │ Entry 0 (32 bytes)                        │  │
│  │ Entry 1 (32 bytes)                        │  │
│  │ ...                                       │  │
│  │ Entry N-1 (32 bytes)                      │  │
│  └───────────────────────────────────────────┘  │
├─────────────────────────────────────────────────┤
│  Switch 2 路由表                                 │
│  ┌───────────────────────────────────────────┐  │
│  │ Header (16 bytes)                         │  │
│  │ Entries...                                │  │
│  └───────────────────────────────────────────┘  │
├─────────────────────────────────────────────────┤
│  ...                                            │
└─────────────────────────────────────────────────┘
```

#### 路由条目格式 (32 bytes)

| 偏移 | 字段 | 类型 | 说明 |
|------|------|------|------|
| 0 | dst_ip | uint32 | 目标Host IP地址（查找键） |
| 4 | valid | uint8 | 条目有效标志 (1=有效) |
| 5 | is_direct_host | uint8 | 是否直连Host (1=直连) |
| 6 | is_broadcast | uint8 | 是否广播 (预留) |
| 7 | padding1 | uint8 | 对齐填充 |
| 8 | out_port | uint16 | 输出端口号 |
| 10 | out_qp | uint16 | 输出Queue Pair号 |
| 12 | next_hop_ip | uint32 | 下一跳IP地址 |
| 16 | next_hop_port | uint16 | 下一跳端口号 |
| 18 | next_hop_qp | uint16 | 下一跳QP号 |
| 20 | next_hop_mac[6] | uint8[6] | 下一跳MAC地址 |
| 26 | padding2[6] | uint8[6] | 对齐到32字节 |

**注意**：所有多字节字段使用**小端序**存储。

---

## Verilog硬件模块

### 模块层次

```
unified_routing_top
├── unified_table_reader
│   └── 从ROM读取并解析路由表
│       输入: mem_data (32-bit ROM接口)
│       输出: entry_data (256-bit), entry_addr, entry_valid
│
└── unified_routing_engine
    ├── CAM查找逻辑 (IP并行匹配)
    └── BRAM存储 (256-bit路由条目)
        输入: lookup_dst_ip (32-bit)
        输出: resp_* (完整转发信息)
```

### 关键参数

```verilog
// unified_routing_engine
parameter MAX_ENTRIES = 64;      // 最大路由条目数
parameter ENTRY_WIDTH = 256;     // 条目宽度 (32字节)
parameter IP_WIDTH = 32;         // IP地址宽度

// unified_routing_top
parameter SWITCH_ID = 1;         // 本交换机ID
parameter MEM_SIZE = 2048;       // ROM大小（字数）
```

### 流水线时序

```
Cycle 0: 输入 lookup_valid=1, lookup_dst_ip
Cycle 1: Stage 1 - CAM并行匹配，生成 match_idx
Cycle 2: Stage 2 - BRAM读取 dest_table[match_idx]
Cycle 3: Stage 3 - 解析字段，输出 resp_valid=1 + 转发信息
```

**总延迟**：3个时钟周期
**吞吐量**：流水线满载时 ~1 查询/周期

### 接口信号

#### 输入

| 信号 | 宽度 | 说明 |
|------|------|------|
| clk | 1 | 时钟信号 |
| rst_n | 1 | 低电平复位 |
| lookup_valid | 1 | 查找请求有效 |
| lookup_dst_ip | 32 | 目标IP地址 |

#### 输出

| 信号 | 宽度 | 说明 |
|------|------|------|
| resp_valid | 1 | 响应有效 |
| resp_found | 1 | 是否找到路由 |
| resp_out_port | 16 | 输出端口号 |
| resp_out_qp | 16 | 输出QP号 |
| resp_next_hop_ip | 32 | 下一跳IP |
| resp_next_hop_port | 16 | 下一跳端口 |
| resp_next_hop_qp | 16 | 下一跳QP |
| resp_next_hop_mac | 48 | 下一跳MAC |
| resp_is_direct_host | 1 | 是否直连Host |
| resp_is_broadcast | 1 | 是否广播（预留） |

---

## 路由算法说明

### 当前实现（支持2层树）

#### 路由决策逻辑

对于每个交换机生成到所有Host的路由条目：

1. **直连Host**：
   ```
   if (Host连接在本交换机) {
       is_direct_host = 1
       out_port = Host连接端口
       next_hop = Host的IP/MAC
   }
   ```

2. **根交换机转发非直连Host**：
   ```
   else if (本交换机是Root) {
       找到Host所在的子树（哪个直接子节点下）
       out_port = 到该子树的下行端口
       next_hop = 子节点交换机的IP/MAC
   }
   ```

3. **非根交换机转发非直连Host**：
   ```
   else {
       // 默认路由：向上转发
       out_port = 上行端口
       next_hop = 父交换机的IP/MAC
   }
   ```

#### 支持的拓扑示例

✅ **2层树（当前完全支持）**：
```
         SW1 (Root)
        /    |    \
      SW2   SW3   SW4
       |     |     |
      H1    H2    H3
```

转发示例：
- SW2 → H3: SW2向上转发到SW1，SW1向下转发到SW4，SW4交付H3 ✅
- SW3 → H1: SW3向上转发到SW1，SW1向下转发到SW2，SW2交付H1 ✅

### 限制（3层+树不支持）

❌ **3层及更深的树**：
```
         SW1 (Root)
        /          \
      SW2          SW3 (中间节点)
      / \          / \
    SW4 SW5      SW6 SW7
     |   |        |   |
    H1  H2       H3  H4
```

问题示例：
- SW3 → H1: SW3向上转发到SW1（正确），SW1向下到SW2（正确），SW2交付SW4（正确）✅
- **但SW3自己的子节点SW6/SW7无法向下转发** ❌
  - SW3只有"向上转发"逻辑
  - 如果SW3的子节点需要互相通信，会绕道根节点

**原因**：当前代码中，非根节点统一使用"默认路由向上"策略，缺少"判断目标是否在自己子树"的逻辑。

**解决方案**：修改 `src/unified_routing.c` 的路由生成逻辑（仅需修改C代码，Verilog无需改动）

---

## 存储资源占用

### FPGA资源需求

每个交换机的路由引擎占用：

| Host数量 | CAM (寄存器) | BRAM (36Kb块) | 总BRAM |
|---------|-------------|--------------|--------|
| 16 | ~200 LUTs | 0.5 | 18 Kb |
| 64 | ~800 LUTs | 2 | 72 Kb |
| 128 | ~1600 LUTs | 4 | 144 Kb |

**典型配置（64 hosts）**：
- 每个交换机：2 KB RAM
- Xilinx XC7A35T（90个BRAM36）可支持 **~40个交换机**
- Xilinx XC7A200T（365个BRAM36）可支持 **~180个交换机**

---

## 测试和验证

### C转换器测试

```bash
# 测试默认拓扑文件
make test

# 这会执行：
./bin/yaml2fpga topology-tree.yaml
```

输出示例：
```
解析Switch 1 (root)
  连接0: 下行到Host 2 (10.50.183.12)
  连接1: 下行到Host 9998 (10.50.183.250)

构建Switch 1的统一路由表...
收集到 4 个Host
  [Entry 0] 直连Host: 10.50.183.250 -> port=4792, QP=29
  [Entry 1] 路由到子树Switch 2: host_ip=0a32b708 -> next_hop=10.50.183.12
  ...
Switch 1 路由表构建完成，共 4 条目

生成文件: fpga_routing_unified.bin (208 bytes)
```

### Verilog仿真测试

使用 `Verilog/tb_unified_routing.v` 进行测试：

#### 预期输出

```
========== 性能测试：连续查表吞吐能力 ==========
连续发送 16 个查询请求，验证流水线吞吐量...
首个结果在周期 3 返回（延迟 = 3 周期）
已发送 16 个查询请求（周期 0 - 16）

性能测试结果：
  - 发送查询数：16
  - 收到响应数：16
  - 首次响应延迟：3周期（符合3级流水线）
  - 总处理周期：18（发送第1个到收到最后1个）
  - 平均吞吐量：0.89 查询/周期
  ✓ 流水线吞吐量测试通过！
```

---

## 当前限制和已知问题

### 功能限制

1. **仅支持2层树形拓扑** ⚠️
   - 3层及更深的树无法正确路由
   - 中间节点缺少向下转发逻辑
   - **影响**：深层次树形网络不可用
   - **解决方案**：仅需修改C代码（约50行），Verilog无需改动

2. **广播功能未实现** ⚠️
   - 数据结构已预留 `is_broadcast` 字段
   - 但C代码未设置，Verilog未实现多播逻辑
   - **影响**：AllReduce集合通信不可用

3. **Host数量限制** ℹ️
   - 当前参数：`MAX_ENTRIES = 64`
   - 可修改参数增大，但会增加BRAM占用
   - **影响**：超过64个Host需要重新配置

---

## 未来改进计划

### 1. 支持深层次树（高优先级）

**修改文件**：`src/unified_routing.c`（Verilog无需修改）

**需要增加的功能**：
```c
// 判断目标交换机是否在当前交换机的子树中
bool is_in_my_subtree(config, my_switch_id, target_switch_id);

// 修改非根节点的路由决策逻辑
if (is_root) {
    // 现有逻辑：向子树转发
} else {
    if (is_in_my_subtree(config, switch_id, host_switch_id)) {
        // 新增：向下转发到子树
    } else {
        // 现有逻辑：向上转发到父节点
    }
}
```

**影响**：
- ✅ 支持任意深度的树形拓扑
- ✅ Verilog硬件无需修改
- ⏱️ 工作量：约50行代码

### 2. 实现广播功能

**需要修改**：
1. `src/unified_routing.c`：识别广播场景，设置 `is_broadcast=1`
2. `src/unified_routing.c`：生成 `fpga_broadcast_config_t` 表
3. `Verilog/unified_routing_engine.v`：扩展为多播输出引擎

**适用场景**：AllReduce、广播通信

### 3. 路由压缩和优化

**方案**：
1. **前缀聚合**：相同转发动作的IP段合并为一个条目
2. **默认路由**：使用通配符条目减少表项数量
3. **两级TCAM**：快速路径（直连）+ 慢速路径（转发）

**效果**：存储空间减少50%-90%

---

## 常见问题

### Q1: 为什么选择统一路由表而不是两级查表？

**A**: 针对树形拓扑的优化选择：
- **延迟敏感**：3周期 vs 6-8周期
- **逻辑简单**：单次查找，易于时序收敛
- **适合树形**：树形拓扑下路径唯一，无需动态计算

两级查表更适合：任意拓扑、大规模网络（100+ switches）

### Q2: 如何判断我的拓扑是否支持？

**A**: 检查以下条件：
1. ✅ 是否为树形结构（无环）
2. ✅ 是否有唯一的根节点
3. ⚠️ **树的深度是否≤2层**（当前限制）

如果是3层+树，需要等待深层次树支持功能实现。

### Q3: 深层次树支持需要修改Verilog吗？

**A**: **不需要**！Verilog模块是通用的查找引擎，只要C代码正确生成路由表条目，Verilog就能正确转发。只需修改 `src/unified_routing.c` 的路由生成逻辑（约50行代码）。

### Q4: MAC地址格式有什么特殊要求？

**A**: 当前实现使用**反向字节序**存储：
- YAML中：`52:54:00:c2:11:88`
- 存储为：`[88, 11, c2, 00, 54, 52]`
- 原因：适配Verilog 48位小端读取

---

## 参考资料

### 相关文档

- `Makefile`：构建系统说明
- 源代码注释：详细的实现说明

### 技术标准

- YAML 1.2规范
- RDMA/InfiniBand QP机制
- Verilog IEEE 1364-2005标准

---

## 更新日志

### v1.0 (当前版本)
- ✅ 实现统一路由表方案
- ✅ CAM+BRAM 3级流水线查找引擎
- ✅ 支持2层树形拓扑
- ✅ 完整的Verilog测试台和性能测试
- ✅ MAC地址字节序修复
- ⚠️ 深层次树支持待实现（仅需修改C代码）
- ⚠️ 广播功能待实现

### 已修复的问题
- ✅ ROM地址越界检查
- ✅ 流水线init_mode干扰问题
- ✅ Testbench吞吐量统计逻辑
- ✅ MAC地址小端序适配
- ✅ Entry字段位宽对齐

---

**项目状态**：核心功能完成，支持2层树形拓扑的完整路由查找

**最后更新**：2024年12月
