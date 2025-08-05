#!/usr/bin/env python3
"""
运行100次IKE统计收集
"""

import subprocess
import re
import json
import time
from datetime import datetime

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
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
    return {}

def main():
    print("=== 运行100次IKE统计收集 ===")
    print(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    all_results = []
    success_count = 0
    error_count = 0
    
    for i in range(1, 101):
        print(f"\n--- 第 {i}/100 次运行 ---")
        
        try:
            # 重启strongswan服务
            print("重启strongswan服务...")
            restart_output = run_command("sudo systemctl restart strongswan")
            time.sleep(2)
            
            # 运行IKE连接测试
            print("运行IKE连接测试...")
            ike_output = run_command("sudo swanctl --initiate --ike net-net")
            
            # 提取统计数据
            stats = extract_ike_stats(ike_output)
            
            if stats:
                stats["run_number"] = i
                all_results.append(stats)
                success_count += 1
                print(f"✓ 成功 - retransmitted={stats['retransmitted']}, packets={stats['packets']}, single_transmission={stats['single_transmission']}, total_transmitted={stats['total_transmitted']}")
            else:
                error_count += 1
                print("✗ 失败 - 未找到统计数据")
                
        except Exception as e:
            error_count += 1
            print(f"✗ 错误: {e}")
        
        # 每10次运行后显示进度
        if i % 10 == 0:
            print(f"\n=== 进度: {i}/100 (成功: {success_count}, 失败: {error_count}) ===")
    
    # 保存所有结果
    results_filename = f"ike_stats_100_runs_{int(time.time())}.json"
    with open(results_filename, 'w', encoding='utf-8') as f:
        json.dump({
            "summary": {
                "total_runs": 100,
                "successful_runs": success_count,
                "failed_runs": error_count,
                "start_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "end_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            },
            "results": all_results
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\n=== 完成 ===")
    print(f"总运行次数: 100")
    print(f"成功次数: {success_count}")
    print(f"失败次数: {error_count}")
    print(f"成功率: {success_count/100*100:.1f}%")
    print(f"结果已保存到: {results_filename}")
    
    # 显示统计摘要
    if all_results:
        retransmitted_values = [r["retransmitted"] for r in all_results]
        packets_values = [r["packets"] for r in all_results]
        single_transmission_values = [r["single_transmission"] for r in all_results]
        total_transmitted_values = [r["total_transmitted"] for r in all_results]
        
        print(f"\n=== 数据统计 ===")
        print(f"retransmitted - 平均值: {sum(retransmitted_values)/len(retransmitted_values):.2f}")
        print(f"packets - 平均值: {sum(packets_values)/len(packets_values):.2f}")
        print(f"single_transmission - 平均值: {sum(single_transmission_values)/len(single_transmission_values):.2f}")
        print(f"total_transmitted - 平均值: {sum(total_transmitted_values)/len(total_transmitted_values):.2f}")

if __name__ == "__main__":
    main() 