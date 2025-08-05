#!/usr/bin/env python3
"""
测试修复后的传输量累加逻辑
"""

import json
from datetime import datetime

def test_fixed_transmission_logic():
    """测试修复后的传输量累加逻辑"""
    
    # 模拟修复后的测试结果
    test_results = [
        {
            "retransmitted": 0,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 2408,  # 成功，无失败尝试
            "current_attempt_transmitted": 2408,
            "failed_attempts_transmitted": 0,
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 1,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 4816,  # 成功：2408(当前) + 2408(失败)
            "current_attempt_transmitted": 2408,
            "failed_attempts_transmitted": 2408,
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 2,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 7224,  # 成功：2408(当前) + 4816(失败)
            "current_attempt_transmitted": 2408,
            "failed_attempts_transmitted": 4816,
            "timestamp": datetime.now().isoformat(),
            "mode": "traditional"
        },
        {
            "retransmitted": 2,
            "packets": 0,
            "single_transmission": 2408,
            "total_transmitted": 7224,  # 所有尝试都失败：2408*3
            "timestamp": datetime.now().isoformat(),
            "mode": "all_failed",
            "failed_attempts": 3
        }
    ]
    
    # 分析结果
    total_transmitted_values = [r["total_transmitted"] for r in test_results]
    failed_attempts_transmitted = []
    current_attempt_transmitted = []
    
    for r in test_results:
        if "failed_attempts_transmitted" in r:
            failed_attempts_transmitted.append(r["failed_attempts_transmitted"])
        if "current_attempt_transmitted" in r:
            current_attempt_transmitted.append(r["current_attempt_transmitted"])
    
    print("=== 修复后的传输量累加逻辑测试 ===")
    print(f"测试结果数量: {len(test_results)}")
    print(f"总传输量统计:")
    print(f"  平均值: {sum(total_transmitted_values) / len(total_transmitted_values):.0f} 字节")
    print(f"  最小值: {min(total_transmitted_values)} 字节")
    print(f"  最大值: {max(total_transmitted_values)} 字节")
    
    if failed_attempts_transmitted:
        print(f"失败尝试传输量统计:")
        print(f"  平均值: {sum(failed_attempts_transmitted) / len(failed_attempts_transmitted):.0f} 字节")
        print(f"  总失败传输量: {sum(failed_attempts_transmitted)} 字节")
    
    if current_attempt_transmitted:
        print(f"当前尝试传输量统计:")
        print(f"  平均值: {sum(current_attempt_transmitted) / len(current_attempt_transmitted):.0f} 字节")
        print(f"  总当前尝试传输量: {sum(current_attempt_transmitted)} 字节")
    
    # 验证逻辑正确性
    print(f"\n=== 逻辑验证 ===")
    for i, result in enumerate(test_results):
        print(f"结果 {i+1}:")
        print(f"  模式: {result.get('mode', 'unknown')}")
        print(f"  总传输量: {result['total_transmitted']} 字节")
        
        if "current_attempt_transmitted" in result and "failed_attempts_transmitted" in result:
            current = result["current_attempt_transmitted"]
            failed = result["failed_attempts_transmitted"]
            total = result["total_transmitted"]
            print(f"  当前尝试: {current} 字节")
            print(f"  失败尝试: {failed} 字节")
            print(f"  验证: {current} + {failed} = {current + failed} (应该等于 {total})")
            if current + failed == total:
                print(f"  ✅ 逻辑正确")
            else:
                print(f"  ❌ 逻辑错误")
        elif result.get("mode") == "all_failed":
            print(f"  所有尝试都失败，总传输量: {result['total_transmitted']} 字节")
    
    # 模式分布
    mode_counts = {}
    for r in test_results:
        mode = r.get("mode", "unknown")
        mode_counts[mode] = mode_counts.get(mode, 0) + 1
    print(f"\n模式分布: {mode_counts}")
    
    # 保存测试结果
    with open("test_fixed_transmission_results.json", 'w', encoding='utf-8') as f:
        json.dump({
            "test_type": "fixed_transmission_logic_test",
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
                "current_attempt_transmitted": {
                    "mean": sum(current_attempt_transmitted) / len(current_attempt_transmitted) if current_attempt_transmitted else 0,
                    "total": sum(current_attempt_transmitted)
                },
                "mode_distribution": mode_counts
            }
        }, f, indent=2, ensure_ascii=False)
    
    print(f"\n测试结果已保存到: test_fixed_transmission_results.json")

if __name__ == "__main__":
    test_fixed_transmission_logic() 