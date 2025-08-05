#!/usr/bin/env python3
"""
IKE Statistics Extractor
运行strongswan命令并提取IKE传输统计数据
"""

import subprocess
import re
import json
import time
from typing import Dict, Optional

def run_command(command: str) -> str:
    """运行命令并返回输出"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return "Command timed out"
    except Exception as e:
        return f"Error running command: {e}"

def extract_ike_stats(output: str) -> Optional[Dict]:
    """从输出中提取IKE统计数据"""
    # 匹配DEBUG_C1_TRADITIONAL行的正则表达式
    pattern = r'DEBUG_C1_TRADITIONAL: retransmitted=(\d+), packets=(\d+), single_transmission=(\d+), total_transmitted=(\d+)'
    
    match = re.search(pattern, output)
    if match:
        retransmitted = int(match.group(1))
        # 限制最大重传次数为10
        if retransmitted > 10:
            retransmitted = 10
        
        return {
            "retransmitted": retransmitted,
            "packets": int(match.group(2)),
            "single_transmission": int(match.group(3)),
            "total_transmitted": int(match.group(4)),
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "raw_output": output
        }
    return None

def main():
    """主函数"""
    print("=== IKE Statistics Extractor ===")
    print("正在重启strongswan服务...")
    
    # 重启strongswan服务
    restart_output = run_command("sudo systemctl restart strongswan")
    print("重启完成")
    
    # 等待服务启动
    time.sleep(2)
    
    print("正在运行IKE连接测试...")
    
    # 运行swanctl命令并提取C1数据
    ike_output = run_command("sudo swanctl --initiate --ike net-net")
    
    # 提取统计数据
    stats = extract_ike_stats(ike_output)
    
    if stats:
        print("\n=== 提取的统计数据 ===")
        print(f"重传次数: {stats['retransmitted']}")
        print(f"数据包数量: {stats['packets']}")
        print(f"单次传输大小: {stats['single_transmission']} bytes")
        print(f"总传输大小: {stats['total_transmitted']} bytes")
        print(f"时间戳: {stats['timestamp']}")
        
        # 保存到JSON文件
        filename = f"ike_stats_{int(time.time())}.json"
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(stats, f, indent=2, ensure_ascii=False)
        
        print(f"\n数据已保存到: {filename}")
        
        # 显示JSON内容
        print("\n=== JSON数据 ===")
        print(json.dumps(stats, indent=2, ensure_ascii=False))
        
    else:
        print("未找到DEBUG_C1_TRADITIONAL数据")
        print("完整输出:")
        print(ike_output)

if __name__ == "__main__":
    main() 