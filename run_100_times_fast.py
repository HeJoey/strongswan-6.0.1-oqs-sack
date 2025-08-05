#!/usr/bin/env python3
"""
运行100次IKE统计收集 - 详细分析版本
用于验证分片传输在30%丢包率下的性能差异
"""

import subprocess
import re
import json
import time
from datetime import datetime
import statistics

def run_command(command: str) -> str:
    """运行命令并返回输出"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=20)
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

def calculate_theoretical_values():
    """计算理论值"""
    # 已知参数
    N = 2  # 分片数量
    D = 1200  # 每片数据量(字节)
    P = 0.3  # 丢包率30%
    
    # 情况一：丢失一片，全部重传 (真实IPsec/UDP模式)
    # TotalData_All = (N * D) / ((1 - P)^N)
    single_attempt_success_rate = (1 - P) ** N  # 0.7^2 = 0.49
    total_data_all = (N * D) / single_attempt_success_rate  # 2400 / 0.49
    
    # 情况二：选择性重传 (理想TCP模式)
    # TotalData_Selective = (N * D) / (1 - P)
    total_data_selective = (N * D) / (1 - P)  # 2400 / 0.7
    
    # 计算差异
    bandwidth_overhead = (total_data_all - total_data_selective) / total_data_selective
    
    return {
        "parameters": {
            "N": N,
            "D": D,
            "P": P,
            "single_attempt_success_rate": single_attempt_success_rate
        },
        "theoretical": {
            "total_data_all": total_data_all,
            "total_data_selective": total_data_selective,
            "bandwidth_overhead": bandwidth_overhead,
            "expected_attempts": 1 / single_attempt_success_rate
        }
    }

def analyze_results(results):
    """分析结果数据"""
    if not results:
        return {}
    
    # 提取数据
    retransmitted_values = [r["retransmitted"] for r in results]
    packets_values = [r["packets"] for r in results]
    single_transmission_values = [r["single_transmission"] for r in results]
    total_transmitted_values = [r["total_transmitted"] for r in results]
    
    # 计算统计值
    analysis = {
        "retransmitted": {
            "mean": statistics.mean(retransmitted_values),
            "median": statistics.median(retransmitted_values),
            "std": statistics.stdev(retransmitted_values) if len(retransmitted_values) > 1 else 0,
            "min": min(retransmitted_values),
            "max": max(retransmitted_values),
            "distribution": {}
        },
        "packets": {
            "mean": statistics.mean(packets_values),
            "median": statistics.median(packets_values),
            "std": statistics.stdev(packets_values) if len(packets_values) > 1 else 0,
            "min": min(packets_values),
            "max": max(packets_values)
        },
        "single_transmission": {
            "mean": statistics.mean(single_transmission_values),
            "median": statistics.median(single_transmission_values),
            "std": statistics.stdev(single_transmission_values) if len(single_transmission_values) > 1 else 0,
            "min": min(single_transmission_values),
            "max": max(single_transmission_values)
        },
        "total_transmitted": {
            "mean": statistics.mean(total_transmitted_values),
            "median": statistics.median(total_transmitted_values),
            "std": statistics.stdev(total_transmitted_values) if len(total_transmitted_values) > 1 else 0,
            "min": min(total_transmitted_values),
            "max": max(total_transmitted_values)
        }
    }
    
    # 计算分布
    for value in retransmitted_values:
        analysis["retransmitted"]["distribution"][value] = analysis["retransmitted"]["distribution"].get(value, 0) + 1
    
    return analysis

def main():
    print("=== 运行100次IKE统计收集 (详细分析版) ===")
    print(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 计算理论值
    theoretical = calculate_theoretical_values()
    print("\n=== 理论计算 ===")
    print(f"参数: N={theoretical['parameters']['N']}, D={theoretical['parameters']['D']}, P={theoretical['parameters']['P']}")
    print(f"单次尝试成功率: {theoretical['parameters']['single_attempt_success_rate']:.3f}")
    print(f"期望尝试次数: {theoretical['theoretical']['expected_attempts']:.2f}")
    print(f"全部重传理论值: {theoretical['theoretical']['total_data_all']:.0f} 字节")
    print(f"选择性重传理论值: {theoretical['theoretical']['total_data_selective']:.0f} 字节")
    print(f"带宽开销: {theoretical['theoretical']['bandwidth_overhead']*100:.1f}%")
    
    all_results = []
    success_count = 0
    error_count = 0
    
    for i in range(1, 101):
        print(f"第 {i:3d}/100 次运行...", end=" ")
        
        try:
            # 每次运行前重启服务
            run_command("sudo systemctl restart strongswan")
            time.sleep(1)  # 等待服务启动
            
            # 运行IKE连接测试
            ike_output = run_command("sudo swanctl --initiate --ike net-net")
            time.sleep(3)  # 等待连接完成
            
            # 提取统计数据
            stats = extract_ike_stats(ike_output)
            
            if stats:
                stats["run_number"] = i
                all_results.append(stats)
                success_count += 1
                print(f"✓ 成功 (retransmitted={stats['retransmitted']}, total_transmitted={stats['total_transmitted']})")
            else:
                error_count += 1
                print("✗ 失败")
                
        except Exception as e:
            error_count += 1
            print(f"✗ 错误: {e}")
        
        # 每20次运行后显示进度
        if i % 20 == 0:
            print(f"\n=== 进度: {i}/100 (成功: {success_count}, 失败: {error_count}) ===")
    
    # 分析结果
    analysis = analyze_results(all_results)
    
    # 保存所有结果
    results_filename = f"ike_stats_detailed_analysis_{int(time.time())}.json"
    with open(results_filename, 'w', encoding='utf-8') as f:
        json.dump({
            "summary": {
                "total_runs": 100,
                "successful_runs": success_count,
                "failed_runs": error_count,
                "success_rate": f"{success_count/100*100:.1f}%",
                "start_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "end_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            },
            "theoretical_calculations": theoretical,
            "statistical_analysis": analysis,
            "results": all_results
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\n=== 完成 ===")
    print(f"总运行次数: 100")
    print(f"成功次数: {success_count}")
    print(f"失败次数: {error_count}")
    print(f"成功率: {success_count/100*100:.1f}%")
    print(f"结果已保存到: {results_filename}")
    
    # 显示详细统计
    if analysis:
        print(f"\n=== 实际数据统计 ===")
        print(f"retransmitted - 平均值: {analysis['retransmitted']['mean']:.2f}, 中位数: {analysis['retransmitted']['median']:.2f}")
        print(f"packets - 平均值: {analysis['packets']['mean']:.2f}, 中位数: {analysis['packets']['median']:.2f}")
        print(f"single_transmission - 平均值: {analysis['single_transmission']['mean']:.2f}, 中位数: {analysis['single_transmission']['median']:.2f}")
        print(f"total_transmitted - 平均值: {analysis['total_transmitted']['mean']:.2f}, 中位数: {analysis['total_transmitted']['median']:.2f}")
        
        # 显示分布
        print(f"\n=== retransmitted 分布 ===")
        for value, count in sorted(analysis['retransmitted']['distribution'].items()):
            print(f"  {value}: {count} 次 ({count/len(all_results)*100:.1f}%)")
        
        # 理论值与实际值比较
        print(f"\n=== 理论值与实际值比较 ===")
        actual_mean_total = analysis['total_transmitted']['mean']
        theoretical_total = theoretical['theoretical']['total_data_all']
        print(f"理论期望总传输量: {theoretical_total:.0f} 字节")
        print(f"实际平均总传输量: {actual_mean_total:.0f} 字节")
        print(f"差异: {abs(actual_mean_total - theoretical_total):.0f} 字节 ({abs(actual_mean_total - theoretical_total)/theoretical_total*100:.1f}%)")

if __name__ == "__main__":
    main() 