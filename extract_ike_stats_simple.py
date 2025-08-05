#!/usr/bin/env python3
"""
简化版IKE Statistics Extractor
只提取核心统计数据
"""

import subprocess
import re
import json
import time

def run_command(command: str) -> str:
    """运行命令并返回输出"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error: {e}"

def extract_ike_stats(output: str) -> dict:
    """从输出中提取IKE统计数据"""
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
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
        }
    return {}

def main():
    print("=== IKE Statistics Extractor (简化版) ===")
    
    # 重启strongswan服务
    print("重启strongswan服务...")
    run_command("sudo systemctl restart strongswan")
    time.sleep(2)
    
    # 运行IKE连接测试
    print("运行IKE连接测试...")
    ike_output = run_command("sudo swanctl --initiate --ike net-net | grep DEBUG_C1_TRADITIONAL")
    
    # 提取统计数据
    stats = extract_ike_stats(ike_output)
    
    if stats:
        print("\n=== 提取的统计数据 ===")
        print(json.dumps(stats, indent=2, ensure_ascii=False))
        
        # 保存到JSON文件
        filename = f"ike_stats_{int(time.time())}.json"
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(stats, f, indent=2, ensure_ascii=False)
        
        print(f"\n数据已保存到: {filename}")
    else:
        print("未找到DEBUG_C1_TRADITIONAL数据")

if __name__ == "__main__":
    main() 