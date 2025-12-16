import struct
import sys

def read_fpga_config(filename):
    with open(filename, 'rb') as f:
        data = f.read()
    
    # 解析头部
    magic, version, total_conn, timestamp = struct.unpack('<IIII', data[0:16])
    
    print(f"Magic: 0x{magic:08x} ({chr((magic>>24)&0xFF)}{chr((magic>>16)&0xFF)}{chr((magic>>8)&0xFF)}{chr(magic&0xFF)})")
    print(f"Version: {version}")
    print(f"Total connections: {total_conn}")
    print(f"Timestamp: {timestamp}")
    
    # 解析连接条目
    for i in range(total_conn):
        offset = 16 + i * 42
        entry = data[offset:offset+42]
        
        switch_id, host_id, local_ip, peer_ip = struct.unpack('<IIII', entry[0:16])
        local_port, peer_port, local_qp, peer_qp = struct.unpack('<HHHH', entry[16:24])
        
        print(f"\nConnection {i}:")
        print(f"  Switch ID: {switch_id}, Host ID: {host_id}")
        print(f"  Local IP: 0x{local_ip:08x}, Peer IP: 0x{peer_ip:08x}")
        print(f"  Ports: local={local_port}, peer={peer_port}")
        print(f"  QPs: local={local_qp}, peer={peer_qp}")

if __name__ == "__main__":
    read_fpga_config(sys.argv[1])