# YAML to FPGA Configuration Converter

一个简化的YAML拓扑配置到FPGA二进制格式转换工具。

## 功能

- ✅ 解析YAML格式的网络拓扑配置文件
- ✅ 基本拓扑验证（根节点检查）
- ✅ 转换为FPGA可读取的二进制格式
- ✅ 显示拓扑摘要信息

## 编译

```bash
make deps    # 安装依赖
make        # 编译
make clean  # 清理
```

## 使用方法

### 基本转换
```bash
./bin/yaml2fpga topology-tree.yaml
```

### 指定输出文件
```bash
./bin/yaml2fpga topology-tree.yaml my_config.bin
```

### 仅显示拓扑摘要
```bash
./bin/yaml2fpga --summary topology-tree.yaml
```

### 显示帮助
```bash
./bin/yaml2fpga --help
```

## YAML文件格式

```yaml
switches:
  - id: 1
    root: true
    connections:
      - up: false
        host_id: 9998
        my_ip: "10.50.183.11"
        my_mac: "52:54:00:79:05:f1"
        my_port: 4791
        my_qp: 28
        peer_ip: "10.50.183.114"
        peer_mac: "52:54:00:c2:11:88"
        peer_port: 4791
        peer_qp: 17
```

## FPGA二进制格式

生成的二进制文件包含：

### 文件头 (16字节)
- Magic: 0x46475441 ("ATGF")
- Version: 格式版本号
- Total Connections: 总连接数
- Timestamp: 生成时间戳

### 连接条目 (每个32字节)
- Switch ID: 交换机标识符
- Host ID: 对端主机/交换机ID
- Local/Peer IP: IP地址（网络字节序）
- Local/Peer Port: 端口号（网络字节序）
- Local/Peer QP: 队列对编号（网络字节序）
- Local/Peer MAC: MAC地址（6字节）
- Up: 连接状态（1=启用，0=禁用）

## 示例输出

```
=== YAML to FPGA Configuration Converter ===
Input: topology-tree.yaml
Output: fpga_config.bin

Parsing YAML file...
=== Topology Summary ===
Switches: 3
  Switch 1 (Root: Yes): 2 connections
  Switch 2 (Root: No): 3 connections
  Switch 3 (Root: No): 3 connections
Total connections: 8
Root switches: 1
======================

Validating topology...
Validation passed

Converting to FPGA format...
Conversion completed (352 bytes)

Writing FPGA binary file...
FPGA configuration written to: fpga_config.bin

=== Conversion Complete ===
```

## 验证规则

- 必须有且仅有一个根节点交换机
- IP地址格式：xxx.xxx.xxx.xxx
- MAC地址格式：xx:xx:xx:xx:xx:xx
- 端口号范围：1-65535
- 交换机ID必须唯一

## 项目结构

```
yaml_parser/
├── Makefile              # 构建配置
├── include/
│   └── yaml2fpga.h      # 核心头文件
├── src/
│   ├── main.c           # 主程序
│   ├── yaml_parser.c     # YAML解析器
│   └── fpga_converter.c # FPGA格式转换器
├── bin/
│   └── yaml2fpga        # 编译后的可执行文件
└── README.md             # 本文档
```

## 错误代码

- `0`: 成功
- `-1`: 文件未找到
- `-2`: YAML解析错误
- `-3`: 配置无效

## 依赖

- libyaml-dev：YAML解析库
- gcc：C编译器

## 安装依赖

```bash
make deps
```

或手动安装：
```bash
sudo apt-get update
sudo apt-get install libyaml-dev gcc
```