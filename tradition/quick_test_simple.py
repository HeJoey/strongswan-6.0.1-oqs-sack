#!/usr/bin/env python3
"""
简化测试脚本 - 验证JSON文件生成
"""

import sys
import json
import time
from datetime import datetime
sys.path.append('.')
from traditional_fragment_performance_test import *

def main():
    print("=== 简化测试 - 验证JSON文件生成 ===")
    
    # 只测试一个丢包率，少量测试
    loss_rates = [1]  # 只测试1%丢包率
    tests_per_rate = 5  # 只运行5次测试
    
    runner = IkeTestRunner()
    analyzer = PerformanceAnalyzer()
    summary_stats = {}
    
    try:
        for loss_rate in loss_rates:
            print(f"\n=== 测试丢包率: {loss_rate}% ===")
            
            # 设置网络条件
            if not runner.network_controller.set_packet_loss(loss_rate):
                print(f"Failed to set packet loss rate {loss_rate}%, skipping...")
                continue
            
            # 计算理论值
            theoretical = analyzer.calculate_theoretical_values(loss_rate)
            print(f"理论期望传输量: {theoretical['theoretical']['total_data_traditional']:.0f} 字节")
            
            # 运行测试
            results = []
            success_count = 0
            
            for i in range(1, tests_per_rate + 1):
                print(f"  进度: {i}/{tests_per_rate}")
                
                stats = runner.run_single_test()
                if stats:
                    stats["run_number"] = i
                    stats["loss_rate"] = loss_rate
                    results.append(stats)
                    success_count += 1
                else:
                    print(f"  ⚠️  第{i}次测试失败")
            
            # 分析结果
            analysis = analyzer.analyze_results(results)
            
            # 简要统计
            if analysis:
                avg_transmitted = analysis["total_transmitted"]["mean"]
                theoretical_transmitted = theoretical["theoretical"]["total_data_traditional"]
                
                summary_stats[loss_rate] = {
                    "loss_rate": loss_rate,
                    "success_count": success_count,
                    "avg_total_transmitted": avg_transmitted,
                    "theoretical_transmitted": theoretical_transmitted,
                    "efficiency": (2400 / avg_transmitted * 100) if avg_transmitted > 0 else 0
                }
                
                print(f"  成功: {success_count}/{tests_per_rate}")
                print(f"  平均传输量: {avg_transmitted:.0f} 字节")
                print(f"  传输效率: {2400/avg_transmitted*100:.1f}%")
            
            # 为每个丢包率单独保存JSON文件
            timestamp = int(time.time())
            detailed_filename = f"quick_test_detailed_{timestamp}_{loss_rate}.json"
            
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
        # 重置网络条件
        runner.network_controller.reset_network()
    
    # 保存汇总结果
    timestamp = int(time.time())
    summary_filename = f"quick_test_summary_{timestamp}.json"
    
    with open(summary_filename, 'w', encoding='utf-8') as f:
        json.dump({
            "metadata": {
                "test_type": "quick_traditional_fragmentation_summary",
                "timestamp": datetime.now().isoformat(),
                "loss_rates_tested": loss_rates,
                "tests_per_rate": tests_per_rate
            },
            "summary_statistics": summary_stats
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\n=== 测试完成 ===")
    print(f"汇总结果保存到: {summary_filename}")

if __name__ == "__main__":
    main() 