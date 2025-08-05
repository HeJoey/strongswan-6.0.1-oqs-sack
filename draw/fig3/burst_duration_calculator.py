#!/usr/bin/env python3
"""
基于平均突发持续时间的GE模型参数计算器
方案A: X轴 = 平均突发持续时间 (ms)

设计思路:
1. 固定状态B的丢包率为100% (PER_B = 1)
2. 固定状态G→B的转移概率p为小值 (如p=0.01)
3. 改变状态B→G的恢复概率q，控制平均突发持续时间
4. 平均突发持续时间 = 1/q * Δt (ms)

核心问题: "网络中断多长时间，IPsec连接会失败？"
"""

import argparse
import sys
import math

def calculate_burst_duration_ge_model(burst_duration_ms, p_value=0.01, time_slot_ms=10.0):
    """
    计算基于平均突发持续时间的GE模型参数
    
    参数:
    - burst_duration_ms: 平均突发持续时间 (毫秒)
    - p_value: 状态G→B的转移概率 (固定值，默认0.01，即1%)
    - time_slot_ms: 时间槽长度 (毫秒，默认10.0ms，按照技术文档建议)
    
    返回:
    - p: 状态G→B的转移概率
    - q: 状态B→G的恢复概率
    - PER_B: 状态B的丢包率 (固定为1.0)
    - PER_G: 状态G的丢包率 (固定为0.0)
    """
    
    if burst_duration_ms <= 0:
        raise ValueError("平均突发持续时间必须大于0")
    
    if not (0 < p_value < 1):
        raise ValueError("转移概率p必须在0-1之间")
    
    if time_slot_ms <= 0:
        raise ValueError("时间槽长度必须大于0")
    
    # 计算恢复概率q
    # 平均突发持续时间 = 1/q * time_slot_ms
    # 因此 q = time_slot_ms / burst_duration_ms
    q_value = time_slot_ms / burst_duration_ms
    
    # 检查q值的合理性
    if q_value >= 1:
        raise ValueError(f"恢复概率q={q_value:.6f} >= 1，请增加突发持续时间或减少时间槽长度")
    
    if q_value <= 0:
        raise ValueError(f"恢复概率q={q_value:.6f} <= 0，参数无效")
    
    # 固定参数
    PER_B = 1.0  # 状态B的丢包率 = 100%
    PER_G = 0.0  # 状态G的丢包率 = 0%
    
    return p_value, q_value, PER_B, PER_G

def validate_parameters(p, q, PER_B, PER_G):
    """验证GE模型参数的有效性"""
    if not (0 < p < 1):
        return False, f"转移概率p无效: {p:.6f}"
    
    if not (0 < q < 1):
        return False, f"恢复概率q无效: {q:.6f}"
    
    if PER_B != 1.0:
        return False, f"状态B丢包率必须为1.0，当前为: {PER_B:.6f}"
    
    if PER_G != 0.0:
        return False, f"状态G丢包率必须为0.0，当前为: {PER_G:.6f}"
    
    return True, "参数有效"

def generate_tc_command(p, q, PER_B, PER_G, interface="ens33"):
    """生成tc命令"""
    # 使用Gilbert-Elliot模型: p, r, 1-h, 1-k
    # p: 从好状态转移到坏状态的概率 (G→B)
    # r: 从坏状态转移到好状态的概率 (B→G)
    # 1-h: 坏状态下的丢包率 (PER_B)
    # 1-k: 好状态下的丢包率 (PER_G)
    
    # 参数映射 - tc netem使用百分比格式
    p_param = p * 100  # G→B转移概率 (转换为百分比)
    r_param = q * 100  # B→G转移概率 (转换为百分比)
    h_param = PER_B * 100  # 坏状态下的丢包率 (转换为百分比)
    k_param = PER_G * 100  # 好状态下的丢包率 (转换为百分比)
    
    return f"tc qdisc add dev {interface} root netem loss gemodel {p_param:.6f} {r_param:.6f} {h_param:.6f} {k_param:.6f}"

def calculate_statistics(p, q, PER_B, PER_G, time_slot_ms=1.0):
    """计算统计量"""
    # 平均突发持续时间
    avg_burst_duration = time_slot_ms / q
    
    # 平均好状态持续时间
    avg_good_duration = time_slot_ms / p
    
    # 坏状态时间比例
    bad_state_ratio = p / (p + q)
    
    # 好状态时间比例
    good_state_ratio = q / (p + q)
    
    # 总体错误率
    overall_error_rate = bad_state_ratio * PER_B + good_state_ratio * PER_G
    
    return {
        'avg_burst_duration': avg_burst_duration,
        'avg_good_duration': avg_good_duration,
        'bad_state_ratio': bad_state_ratio,
        'good_state_ratio': good_state_ratio,
        'overall_error_rate': overall_error_rate
    }

def main():
    parser = argparse.ArgumentParser(description="基于平均突发持续时间的GE模型参数计算器")
    parser.add_argument("--burst-duration", "-d", type=float, required=True,
                       help="平均突发持续时间 (毫秒)")
    parser.add_argument("--p-value", "-p", type=float, default=0.01,
                       help="状态G→B的转移概率 (默认0.01)")
    parser.add_argument("--time-slot", "-t", type=float, default=10.0,
                       help="时间槽长度 (毫秒，默认10.0，按照技术文档建议)")
    parser.add_argument("--interface", "-i", default="ens33",
                       help="网络接口名称")
    parser.add_argument("--tc-command", action="store_true",
                       help="输出tc命令")
    parser.add_argument("--verbose", "-v", action="store_true",
                       help="详细输出")
    
    args = parser.parse_args()
    
    try:
        # 计算GE模型参数
        p, q, PER_B, PER_G = calculate_burst_duration_ge_model(
            args.burst_duration, args.p_value, args.time_slot
        )
        
        print(f"基于突发持续时间的GE模型参数:")
        print(f"  平均突发持续时间: {args.burst_duration:.2f} ms")
        print(f"  转移概率 p (G→B): {p:.6f}")
        print(f"  恢复概率 q (B→G): {q:.6f}")
        print(f"  状态B丢包率 PER_B: {PER_B:.6f}")
        print(f"  状态G丢包率 PER_G: {PER_G:.6f}")
        
        # 验证参数
        valid, message = validate_parameters(p, q, PER_B, PER_G)
        if not valid:
            print(f"警告: {message}")
        
        # 计算统计量
        stats = calculate_statistics(p, q, PER_B, PER_G, args.time_slot)
        
        # 输出tc命令
        if args.tc_command:
            tc_cmd = generate_tc_command(p, q, PER_B, PER_G, args.interface)
            print(f"\ntc命令:")
            print(f"  {tc_cmd}")
        
        # 详细输出
        if args.verbose:
            print(f"\n统计量:")
            print(f"  平均突发持续时间: {stats['avg_burst_duration']:.2f} ms")
            print(f"  平均好状态持续时间: {stats['avg_good_duration']:.2f} ms")
            print(f"  坏状态时间比例: {stats['bad_state_ratio']:.4f}")
            print(f"  好状态时间比例: {stats['good_state_ratio']:.4f}")
            print(f"  总体错误率: {stats['overall_error_rate']:.4f}")
            
            print(f"\n设计说明:")
            print(f"  - 固定转移概率p={p:.6f} ({p*100:.2f}%)，确保突发事件以固定频率发生")
            print(f"  - 平均每 {1/p:.1f} 个时间步长发生一次突发事件")
            print(f"  - 调整恢复概率q={q:.6f} ({q*100:.4f}%)，控制平均突发持续时间")
            print(f"  - 状态B完全丢包(PER_B=1.0)，模拟链路中断")
            print(f"  - 状态G无丢包(PER_G=0.0)，模拟正常链路")
            print(f"  - 时间步长: {args.time_slot}ms (按照技术文档建议)")
            
            print(f"\n科学意义:")
            print(f"  - 直接考验IKEv2协议的超时和重传机制")
            print(f"  - 揭示协议层面的深层脆弱性")
            print(f"  - 回答核心问题: '网络中断多长时间，IPsec连接会失败？'")
        
    except ValueError as e:
        print(f"错误: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"未知错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 