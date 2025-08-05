#!/usr/bin/env python3
"""
测试分片重传统计的正确性
"""

import subprocess
import re
import time

def run_ike_connection():
    """运行IKE连接测试"""
    print("启动IKE连接测试...")
    
    # 启动swanctl连接
    cmd = ["sudo", "swanctl", "--initiate", "--ike", "net-net"]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        print("连接超时")
        return "", ""
    except Exception as e:
        print(f"执行命令时出错: {e}")
        return "", ""

def analyze_transmission_stats(output):
    """分析传输统计信息"""
    print("\n=== 传输统计分析 ===")
    
    # 查找关键统计信息
    patterns = {
        'initial_transmission': r'DEBUG_A3_INITIAL_TRANSMISSION.*total_data_size=(\d+).*tracker_total=(\d+)',
        'retransmission': r'DEBUG_A1_PACKETS_SENT.*retransmitted=(\d+).*total_data_size=(\d+).*tracker_total=(\d+)',
        'selective_retransmit': r'SELECTIVE_RETRANSMIT.*retransmit_data_size=(\d+).*total_transmitted=(\d+).*original_size=(\d+).*efficiency=([\d.]+)%.*retransmissions=(\d+).*total_fragment_retransmissions=(\d+)',
        'fragment_retransmit': r'DEBUG_G1_RETRANSMIT.*fragment_id=(\d+).*retransmit_count=(\d+).*total_transmitted=(\d+).*fragment_efficiency=([\d.]+)%',
        'final_stats': r'DEBUG_E1_REQUEST_TRANSMISSION_STATS.*original_size=(\d+).*total_transmitted=(\d+).*efficiency=([\d.]+)%.*retransmissions=(\d+)'
    }
    
    stats = {}
    for key, pattern in patterns.items():
        matches = re.findall(pattern, output)
        stats[key] = matches
        if matches:
            print(f"\n{key.upper()}:")
            for match in matches:
                print(f"  {match}")
    
    # 验证统计的正确性
    print("\n=== 统计验证 ===")
    
    if 'initial_transmission' in stats and stats['initial_transmission']:
        initial_size = int(stats['initial_transmission'][0][0])
        initial_tracker = int(stats['initial_transmission'][0][1])
        print(f"初始传输: {initial_size} bytes, tracker: {initial_tracker} bytes")
        
        if initial_size == initial_tracker:
            print("✓ 初始传输统计正确")
        else:
            print("✗ 初始传输统计错误")
    
    if 'selective_retransmit' in stats and stats['selective_retransmit']:
        for match in stats['selective_retransmit']:
            retransmit_size = int(match[0])
            total_transmitted = int(match[1])
            original_size = int(match[2])
            efficiency = float(match[3])
            retransmissions = int(match[4])
            fragment_retransmissions = int(match[5])
            
            print(f"\n选择性重传统计:")
            print(f"  重传数据量: {retransmit_size} bytes")
            print(f"  总传输量: {total_transmitted} bytes")
            print(f"  原始大小: {original_size} bytes")
            print(f"  效率: {efficiency}%")
            print(f"  重传次数: {retransmissions}")
            print(f"  分片重传次数: {fragment_retransmissions}")
            
            # 验证效率计算
            expected_efficiency = (original_size / total_transmitted) * 100
            if abs(efficiency - expected_efficiency) < 0.1:
                print("✓ 效率计算正确")
            else:
                print(f"✗ 效率计算错误: 期望 {expected_efficiency:.2f}%, 实际 {efficiency:.2f}%")
    
    if 'final_stats' in stats and stats['final_stats']:
        for match in stats['final_stats']:
            original_size = int(match[0])
            total_transmitted = int(match[1])
            efficiency = float(match[2])
            retransmissions = int(match[3])
            
            print(f"\n最终统计:")
            print(f"  原始大小: {original_size} bytes")
            print(f"  总传输量: {total_transmitted} bytes")
            print(f"  效率: {efficiency}%")
            print(f"  重传次数: {retransmissions}")
            
            # 验证最终统计
            if total_transmitted >= original_size:
                print("✓ 总传输量 >= 原始大小")
            else:
                print("✗ 总传输量 < 原始大小 (错误)")
            
            expected_efficiency = (original_size / total_transmitted) * 100
            if abs(efficiency - expected_efficiency) < 0.1:
                print("✓ 最终效率计算正确")
            else:
                print(f"✗ 最终效率计算错误: 期望 {expected_efficiency:.2f}%, 实际 {efficiency:.2f}%")

def main():
    """主函数"""
    print("开始测试分片重传统计...")
    
    # 运行IKE连接
    stdout, stderr = run_ike_connection()
    
    # 分析输出
    if stdout:
        analyze_transmission_stats(stdout)
    else:
        print("没有获取到输出")
    
    if stderr:
        print(f"\n错误输出:\n{stderr}")

if __name__ == "__main__":
    main() 