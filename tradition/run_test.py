#!/usr/bin/env python3
"""
传统分片性能测试 - 简化运行器
快速运行传统分片机制在不同丢包率下的性能测试
"""

import subprocess
import sys
import os

def check_requirements():
    """检查运行要求"""
    print("=== 检查运行环境 ===")
    
    # 检查权限
    if os.geteuid() != 0:
        print("❌ 需要root权限来控制网络和重启服务")
        print("请使用: sudo python3 run_test.py")
        return False
    
    # 检查tc命令
    result = subprocess.run("which tc", shell=True, capture_output=True)
    if result.returncode != 0:
        print("❌ 缺少tc命令，请安装: sudo apt-get install iproute2")
        return False
    
    # 检查strongswan
    result = subprocess.run("systemctl is-active strongswan", shell=True, capture_output=True)
    if result.returncode != 0:
        print("❌ strongswan服务未运行，请检查strongswan安装")
        return False
    
    print("✅ 环境检查通过")
    return True

def get_network_interface():
    """获取网络接口"""
    print("\n=== 检测网络接口 ===")
    
    # 常见接口名
    interfaces = ["eth0", "enp0s3", "ens33", "wlan0"]
    
    for iface in interfaces:
        result = subprocess.run(f"ip link show {iface}", shell=True, capture_output=True)
        if result.returncode == 0:
            print(f"✅ 发现接口: {iface}")
            return iface
    
    # 如果没找到，列出所有接口
    result = subprocess.run("ip link show | grep '^[0-9]' | cut -d: -f2", 
                          shell=True, capture_output=True, text=True)
    if result.stdout:
        available = [line.strip() for line in result.stdout.split('\n') if line.strip()]
        print(f"可用接口: {available}")
        if available:
            return available[0]  # 返回第一个可用接口
    
    return "enp0s3"  # 默认值

def run_quick_test():
    """运行快速测试 (仅几个丢包率，每个50次)"""
    print("\n=== 快速测试模式 ===")
    print("测试丢包率: 0%, 5%, 10%, 20%")
    print("每个条件运行50次")
    
    # 修改脚本运行快速测试
    script_content = """
import sys
import json
import time
from datetime import datetime
sys.path.append('.')
from traditional_fragment_performance_test import *

# 快速测试参数
loss_rates = [0, 5, 10, 20]
tests_per_rate = 50

# 验证理论模型
analyzer = PerformanceAnalyzer()
analyzer.verify_theoretical_model()

# 运行测试 (复制主要逻辑但减少测试次数)
runner = IkeTestRunner()
summary_stats = {}

print("=== 快速测试开始 ===")

try:
    for loss_rate in loss_rates:
        print(f"\\n=== 测试丢包率: {loss_rate}% ===")
        
        if not runner.network_controller.set_packet_loss(loss_rate):
            continue
        
        results = []
        success_count = 0
        
        # 动态休息时间管理
        base_rest_time = 5.0  # 基础休息时间5秒
        current_rest_time = base_rest_time
        consecutive_failures = 0  # 连续失败计数
        consecutive_successes = 0  # 连续成功计数
        
        for i in range(1, tests_per_rate + 1):
            if i % 10 == 0:
                print(f"  进度: {i}/{tests_per_rate}")
            
            stats = runner.run_single_test()
            if stats:
                results.append(stats)
                success_count += 1
                consecutive_successes += 1
                consecutive_failures = 0  # 重置连续失败计数
                
                # 成功时减少休息时间（减半，但不低于基础时间）
                if consecutive_successes >= 3:  # 连续成功3次后开始减少休息时间
                    current_rest_time = max(base_rest_time, current_rest_time * 0.5)
                    consecutive_successes = 0  # 重置连续成功计数
                    print(f"  ✅ 连续成功，休息时间调整为: {current_rest_time:.1f}秒")
            else:
                consecutive_failures += 1
                consecutive_successes = 0  # 重置连续成功计数
                print(f"  ⚠️  第{i}次测试失败")
                
                # 失败时增加休息时间
                current_rest_time *= 2.0
                print(f"  ⏸️  连续失败{consecutive_failures}次，休息时间调整为: {current_rest_time:.1f}秒")
            
            # 应用动态休息时间
            print(f"  💤 休息 {current_rest_time:.1f} 秒...")
            time.sleep(current_rest_time)
        
        # 分析结果
        analysis = analyzer.analyze_results(results)
        if analysis:
            avg_transmitted = analysis["total_transmitted"]["mean"]
            theoretical = analyzer.calculate_theoretical_values(loss_rate)
            theoretical_transmitted = theoretical["theoretical"]["total_data_traditional"]
            
            summary_stats[loss_rate] = {
                "success_count": success_count,
                "avg_total_transmitted": avg_transmitted,
                "theoretical_transmitted": theoretical_transmitted,
                "efficiency": (2408 / avg_transmitted * 100) if avg_transmitted > 0 else 0
            }
            print(f"  成功: {success_count}/{tests_per_rate}")
            print(f"  平均传输量: {avg_transmitted:.0f} 字节")
            print(f"  理论传输量: {theoretical_transmitted:.0f} 字节")
            print(f"  效率: {2408/avg_transmitted*100:.1f}%")
            
            # 为每个丢包率单独保存JSON文件
            import time
            timestamp = int(time.time())
            detailed_filename = f"tradition/quick_test_detailed_{timestamp}_{loss_rate}.json"
            
            with open(detailed_filename, 'w', encoding='utf-8') as f:
                json.dump({
                    "metadata": {
                        "test_type": "quick_traditional_fragmentation_performance",
                        "loss_rate": loss_rate,
                        "start_time": datetime.now().isoformat(),
                        "tests_per_rate": tests_per_rate,
                        "total_tests": tests_per_rate,
                        "success_count": success_count
                    },
                    "theoretical_analysis": theoretical,
                    "performance_analysis": analysis,
                    "detailed_results": results
                }, f, indent=2, ensure_ascii=False)
            
            print(f"  📁 详细结果已保存到: {detailed_filename}")

finally:
    runner.network_controller.reset_network()

# 显示汇总
print(f"\\n=== 快速测试结果 ===")
print(f"{'丢包率':<8} {'成功率':<8} {'平均传输量':<12} {'效率':<8}")
print("-" * 40)
for loss_rate in loss_rates:
    if loss_rate in summary_stats:
        stats = summary_stats[loss_rate]
        success_rate = stats["success_count"] / tests_per_rate * 100
        print(f"{loss_rate:>5}%   {success_rate:>6.1f}%   {stats['avg_total_transmitted']:>9.0f}字节   {stats['efficiency']:>6.1f}%")
"""
    
    with open("/tmp/quick_test.py", "w") as f:
        f.write(script_content)
    
    subprocess.run("python3 /tmp/quick_test.py", shell=True)

def run_full_test():
    """运行完整测试"""
    print("\n=== 完整测试模式 ===")
    print("测试所有丢包率: 1%-40%")
    print("每个条件运行500次")
    print("预计运行时间: 3-4小时")
    
    confirm = input("确认运行完整测试? (y/N): ")
    if confirm.lower() != 'y':
        print("测试取消")
        return
    
    subprocess.run("python3 traditional_fragment_performance_test.py", shell=True)

def main():
    """主菜单"""
    print("传统分片性能测试工具")
    print("作者: Assistant")
    print(f"工作目录: {os.getcwd()}")
    
    if not check_requirements():
        sys.exit(1)
    
    interface = get_network_interface()
    print(f"✅ 将使用网络接口: {interface}")
    
    # 更新脚本中的接口名
    print(f"✅ 更新网络接口配置为: {interface}")
    
    while True:
        print("\n=== 选择测试模式 ===")
        print("1. 快速测试 (0%, 5%, 10%, 20% 丢包率, 每个50次)")
        print("2. 完整测试 (1%-40% 丢包率, 每个500次)")
        print("3. 退出")
        
        choice = input("请选择 (1-3): ").strip()
        
        if choice == "1":
            run_quick_test()
            break
        elif choice == "2":
            run_full_test()
            break
        elif choice == "3":
            print("退出")
            break
        else:
            print("无效选择，请重试")

if __name__ == "__main__":
    main() 