#!/usr/bin/env python3
"""
测试失败传输量记录功能
"""

import json
from datetime import datetime

def test_failed_transmission_logic():
    """测试失败传输量记录逻辑"""
    
    # 模拟测试结果
    test_results = [
        {
            "retransmitted": 0,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 2408,  # 成功，无失败尝试
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 1,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 4816,  # 成功，包含1次失败尝试
            "failed_attempts_transmitted": 2408,
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 2,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 7224,  # 成功，包含2次失败尝试
            "failed_attempts_transmitted": 4816,
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 2,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 7224,  # 所有尝试都失败
            "timestamp": datetime.now().isoformat(),
            "mode": "all_failed",
            "failed_attempts": 3
        }
    ]
    
    # 分析结果
    total_transmitted_values = [r["total_transmitted"] for r in test_results]
    failed_attempts_transmitted = []
    for r in test_results:
        if "failed_attempts_transmitted" in r:
            failed_attempts_transmitted.append(r["failed_attempts_transmitted"])
    
    print("=== 失败传输量记录测试 ===")
    print(f"测试结果数量: {len(test_results)}")
    print(f"总传输量统计:")
    print(f"  平均值: {sum(total_transmitted_values) / len(total_transmitted_values):.0f} 字节")
    print(f"  最小值: {min(total_transmitted_values)} 字节")
    print(f"  最大值: {max(total_transmitted_values)} 字节")
    
    if failed_attempts_transmitted:
        print(f"失败尝试传输量统计:")
        print(f"  平均值: {sum(failed_attempts_transmitted) / len(failed_attempts_transmitted):.0f} 字节")
        print(f"  总失败传输量: {sum(failed_attempts_transmitted)} 字节")
    
    # 模式分布
    mode_counts = {}
    for r in test_results:
        mode = r.get("mode", "unknown")
        mode_counts[mode] = mode_counts.get(mode, 0) + 1
    print(f"模式分布: {mode_counts}")
    
    # 保存测试结果
    with open("test_failed_transmission_results.json", 'w', encoding='utf-8') as f:
        json.dump({
            "test_type": "failed_transmission_logic_test",
            "timestamp": datetime.now().isoformat(),
            "results": test_results,
            "analysis": {
                "total_transmitted": {
                    "mean": sum(total_transmitted_values) / len(total_transmitted_values),
                    "min": min(total_transmitted_values),
                    "max": max(total_transmitted_values)
                },
                "failed_attempts_transmitted": {
                    "mean": sum(failed_attempts_transmitted) / len(failed_attempts_transmitted) if failed_attempts_transmitted else 0,
                    "total": sum(failed_attempts_transmitted)
                },
                "mode_distribution": mode_counts
            }
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\n测试结果已保存到: test_failed_transmission_results.json")

if __name__ == "__main__":
    test_failed_transmission_logic() 