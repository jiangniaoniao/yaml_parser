#!/usr/bin/env python3
# 将二进制路由表文件转换为Verilog $readmemh格式的hex文件

import sys
import struct

def bin_to_hex(bin_file, hex_file):
    """
    将二进制文件转换为32位字的hex文件
    每行一个32位字（小端序）
    """
    with open(bin_file, 'rb') as f_in:
        data = f_in.read()

    # 确保是4字节对齐
    if len(data) % 4 != 0:
        # 填充到4字节对齐
        padding = 4 - (len(data) % 4)
        data += b'\x00' * padding
        print(f"警告: 文件大小不是4的倍数，已填充{padding}字节")

    print(f"输入文件: {bin_file}")
    print(f"文件大小: {len(data)}字节 ({len(data)//4}个32位字)")

    with open(hex_file, 'w') as f_out:
        # 每4个字节转换为一个32位字（小端序）
        for i in range(0, len(data), 4):
            # 读取4个字节
            word_bytes = data[i:i+4]
            # 转换为32位整数（小端序）
            word = struct.unpack('<I', word_bytes)[0]
            # 写入hex文件（8位hex，不带0x前缀）
            f_out.write(f"{word:08x}\n")

    print(f"输出文件: {hex_file}")
    print(f"转换完成!")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: python3 bin2hex.py <输入.bin> <输出.hex>")
        print("示例: python3 bin2hex.py fpga_config_routing.bin fpga_config_routing.hex")
        sys.exit(1)

    bin_file = sys.argv[1]
    hex_file = sys.argv[2]

    try:
        bin_to_hex(bin_file, hex_file)
    except FileNotFoundError:
        print(f"错误: 找不到文件 {bin_file}")
        sys.exit(1)
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)
