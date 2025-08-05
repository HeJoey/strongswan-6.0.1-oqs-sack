#!/usr/bin/env python3
"""
传统分片机制性能测试 - 多丢包率综合分析
测试传统分片在不同丢包率(1%-40%)下的性能表现，每个条件运行500次
"""

import subprocess
import re
import json
import time
import os
import sys
from datetime import datetime
import statistics
from typing import Dict, List, Optional

class NetworkController:
    """网络条件控制器"""
    
    def __init__(self, interface: str = "ens33"):
        self.interface = interface
        self.original_setup_done = False
    
    def setup_tc_environment(self):
        """设置TC环境"""
        if not self.original_setup_done:
            print("Setting up traffic control environment...")
            # 删除可能存在的规则
            subprocess.run(f"sudo tc qdisc del dev {self.interface} root", 
                         shell=True, capture_output=True)
            self.original_setup_done = True
    
    def set_packet_loss(self, loss_rate: float) -> bool:
        """设置丢包率"""
        try:
            self.setup_tc_environment()
            
            # 删除现有规则
            subprocess.run(f"sudo tc qdisc del dev {self.interface} root", 
                         shell=True, capture_output=True)
            
            if loss_rate > 0:
                # 设置新的丢包率
                cmd = f"sudo tc qdisc add dev {self.interface} root netem loss {loss_rate}%"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"Error setting packet loss: {result.stderr}")
                    return False
            
            print(f"✓ Set packet loss rate to {loss_rate}%")
            return True
            
        except Exception as e:
            print(f"Error in set_packet_loss: {e}")
            return False
    
    def reset_network(self):
        """重置网络条件"""
        try:
            subprocess.run(f"sudo tc qdisc del dev {self.interface} root", 
                         shell=True, capture_output=True)
            print("✓ Network conditions reset")
        except Exception as e:
            print(f"Error resetting network: {e}")

class IkeTestRunner:
    """IKE测试运行器"""
    
    def __init__(self):
        self.network_controller = NetworkController()
    
    def run_command(self, command: str, timeout: int = 30) -> str:
        """运行命令并返回输出"""
        try:
            result = subprocess.run(command, shell=True, capture_output=True, 
                                  text=True, timeout=timeout)
            return result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return "Error: Command timeout"
        except Exception as e:
            return f"Error: {e}"
    
    def check_network_connectivity(self) -> bool:
        """检查网络连接性"""
        try:
            # 检查对端主机是否可达
            result = subprocess.run("ping -c 1 192.168.31.137", shell=True, 
                                  capture_output=True, timeout=10)
            return result.returncode == 0
        except:
            return False
    
    def extract_ike_stats(self, output: str) -> Optional[Dict]:
        """从输出中提取IKE统计数据"""
        # 寻找传统模式的统计模式
        traditional_pattern = r'DEBUG_C1_TRADITIONAL: retransmitted=(\d+), packets=(\d+), single_transmission=(\d+), total_transmitted=(\d+)'
        
        match = re.search(traditional_pattern, output)
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
                "timestamp": datetime.now().isoformat(),
                "mode": "traditional"
            }
        
        # 如果没找到传统模式，尝试其他模式
        general_pattern = r'total_transmitted=(\d+) bytes'
        match = re.search(general_pattern, output)
        if match:
            return {
                "retransmitted": 0,
                "packets": 0,
                "single_transmission": 0,
                "total_transmitted": int(match.group(1)),
                "timestamp": datetime.now().isoformat(),
                "mode": "general"
            }
        
        return None
    
    def run_single_test(self) -> Optional[Dict]:
        """运行单次IKE测试"""
        max_retries = 10  # 最大重试次数
        total_failed_transmitted = 0  # 累计失败尝试的传输量
        
        for attempt in range(max_retries):
            try:
                # 强制清理可能存在的连接
                if attempt > 0:
                    print(f"  🔄 重试第{attempt}次，清理连接...")
                    self.run_command("sudo systemctl stop strongswan", timeout=10)
                    time.sleep(3)  # 等待服务完全停止
                
                # 重启strongswan服务
                print("  🔄 重启strongswan服务...")
                self.run_command("sudo systemctl restart strongswan")
                time.sleep(3)  # 增加等待时间确保服务完全启动
                
                # 检查服务状态
                status_output = self.run_command("sudo systemctl is-active strongswan", timeout=10)
                if "active" not in status_output:
                    print(f"  ⚠️  strongswan服务未正常启动，重试...")
                    continue
                
                # 运行IKE连接测试
                print("  🔗 尝试建立IKE连接...")
                ike_output = self.run_command("sudo swanctl --initiate --ike net-net", timeout=35)
                
                # 检查是否有错误
                if "Error:" in ike_output or "timeout" in ike_output.lower() or "failed" in ike_output.lower():
                    print(f"  ❌ IKE连接失败 (尝试{attempt+1}/{max_retries}): {ike_output[:100]}...")
                    
                    # 记录失败尝试的传输量（假设每次失败尝试都发送了完整的IKE消息）
                    failed_transmitted = 2408  # 假设每次失败都发送了完整的IKE消息
                    total_failed_transmitted += failed_transmitted
                    print(f"  📊 失败尝试累计传输量: {total_failed_transmitted} 字节")
                    
                    if attempt < max_retries - 1:
                        time.sleep(2)  # 重试前等待
                        continue
                    else:
                        # 如果所有尝试都失败了，返回失败累计的传输量
                        return {
                            "retransmitted": max_retries - 1,  # 重试次数
                            "packets": 0,
                            "single_transmission": 2408,
                            "total_transmitted": total_failed_transmitted,
                            "timestamp": datetime.now().isoformat(),
                            "mode": "all_failed",
                            "failed_attempts": max_retries
                        }
                
                # 提取统计数据
                stats = self.extract_ike_stats(ike_output)
                if stats:
                    # 当前成功尝试的传输量
                    current_attempt_transmitted = stats["total_transmitted"]
                    # 总传输量 = 当前尝试传输量 + 之前失败尝试的累计传输量
                    total_transmitted = current_attempt_transmitted + total_failed_transmitted
                    
                    stats["total_transmitted"] = total_transmitted
                    stats["current_attempt_transmitted"] = current_attempt_transmitted
                    stats["failed_attempts_transmitted"] = total_failed_transmitted
                    print(f"  ✅ 连接成功，总传输量: {total_transmitted} 字节 (当前尝试: {current_attempt_transmitted} 字节, 失败尝试: {total_failed_transmitted} 字节)")
                else:
                    print(f"  ⚠️  连接成功但未找到统计数据")
                    # 即使没有统计数据，也返回一个基本的结果
                    current_attempt_transmitted = 2408  # 假设当前尝试的传输量
                    total_transmitted = current_attempt_transmitted + total_failed_transmitted
                    
                    stats = {
                        "retransmitted": 0,
                        "packets": 0,
                        "single_transmission": 2408,  # 假设值
                        "total_transmitted": total_transmitted,
                        "current_attempt_transmitted": current_attempt_transmitted,
                        "timestamp": datetime.now().isoformat(),
                        "mode": "estimated",
                        "failed_attempts_transmitted": total_failed_transmitted
                    }
                
                # 直接重启服务而不是terminate，避免丢包造成的巨大时延
                self.run_command("sudo systemctl restart strongswan")
                time.sleep(2)  # 增加等待时间
                
                return stats
                
            except Exception as e:
                print(f"  ❌ 单次测试错误 (尝试{attempt+1}/{max_retries}): {e}")
                
                # 记录异常情况下的传输量
                failed_transmitted = 2408
                total_failed_transmitted += failed_transmitted
                print(f"  📊 异常失败累计传输量: {total_failed_transmitted} 字节")
                
                if attempt < max_retries - 1:
                    time.sleep(2)  # 重试前等待
                    continue
                else:
                    # 如果所有尝试都失败了，返回失败累计的传输量
                    return {
                        "retransmitted": max_retries - 1,
                        "packets": 0,
                        "single_transmission": 2408,
                        "total_transmitted": total_failed_transmitted,
                        "timestamp": datetime.now().isoformat(),
                        "mode": "all_failed_exception",
                        "failed_attempts": max_retries
                    }
        
        return None

class PerformanceAnalyzer:
    """性能分析器"""
    
    @staticmethod
    def calculate_theoretical_values(loss_rate: float) -> Dict:
        """
        计算传统IKEv2"全部重传"模型的理论值
        
        基于几何分布模型：
        - 单次尝试成功概率: p_succ = (1-P)^N
        - 期望尝试次数: E[K] = 1/p_succ = 1/(1-P)^N  
        - 总传输数据量: E[Data_All] = E[K] × (N×D) = N×D / (1-P)^N
        
        其中：
        - N: 分片数量
        - D: 每片数据量(字节)
        - P: 单个分片丢包率
        """
        N = 2  # 分片数量
        D = 1204  # 每片数据量(字节) - 2408/2=1204
        P = loss_rate / 100  # 丢包率转换为小数
        
        if P >= 1.0:
            return {
                "parameters": {"N": N, "D": D, "P": P},
                "theoretical": {
                    "total_data_traditional": float('inf'),
                    "expected_attempts": float('inf'),
                    "success_rate": 0.0
                }
            }
        
        # 传统IKEv2"全部重传"模型计算
        # 1. 单次尝试成功概率: p_succ = (1-P)^N (所有N个分片都必须成功)
        single_attempt_success_rate = (1 - P) ** N
        
        if single_attempt_success_rate > 0:
            # 2. 期望尝试次数: E[K] = 1/p_succ (几何分布期望)
            expected_attempts = 1 / single_attempt_success_rate
            # 3. 总传输数据量期望: E[Data_All] = E[K] × (N×D)
            total_data_traditional = (N * D) * expected_attempts
        else:
            # 当P=1时，理论值为无穷大
            expected_attempts = float('inf')
            total_data_traditional = float('inf')
        
        return {
            "parameters": {
                "N": N,
                "D": D,
                "P": P,
                "single_attempt_success_rate": single_attempt_success_rate
            },
            "theoretical": {
                "total_data_traditional": total_data_traditional,
                "expected_attempts": expected_attempts,
                "success_rate": single_attempt_success_rate
            }
        }
    
    @staticmethod
    def analyze_results(results: List[Dict]) -> Dict:
        """分析结果数据"""
        if not results:
            return {}
        
        # 提取数据
        total_transmitted_values = [r["total_transmitted"] for r in results]
        retransmitted_values = [r["retransmitted"] for r in results]
        
        # 提取失败尝试的传输量和当前尝试的传输量（如果存在）
        failed_attempts_transmitted = []
        current_attempt_transmitted = []
        for r in results:
            if "failed_attempts_transmitted" in r:
                failed_attempts_transmitted.append(r["failed_attempts_transmitted"])
            if "current_attempt_transmitted" in r:
                current_attempt_transmitted.append(r["current_attempt_transmitted"])
        
        # 计算统计值
        analysis = {
            "count": len(results),
            "total_transmitted": {
                "mean": statistics.mean(total_transmitted_values),
                "median": statistics.median(total_transmitted_values),
                "std": statistics.stdev(total_transmitted_values) if len(total_transmitted_values) > 1 else 0,
                "min": min(total_transmitted_values),
                "max": max(total_transmitted_values),
                "values": total_transmitted_values
            },
            "retransmitted": {
                "mean": statistics.mean(retransmitted_values),
                "median": statistics.median(retransmitted_values),
                "std": statistics.stdev(retransmitted_values) if len(retransmitted_values) > 1 else 0,
                "min": min(retransmitted_values),
                "max": max(retransmitted_values)
            }
        }
        
        # 如果有失败尝试的传输量数据，添加相关统计
        if failed_attempts_transmitted:
            analysis["failed_attempts_transmitted"] = {
                "mean": statistics.mean(failed_attempts_transmitted),
                "median": statistics.median(failed_attempts_transmitted),
                "std": statistics.stdev(failed_attempts_transmitted) if len(failed_attempts_transmitted) > 1 else 0,
                "min": min(failed_attempts_transmitted),
                "max": max(failed_attempts_transmitted),
                "total": sum(failed_attempts_transmitted)
            }
        
        # 如果有当前尝试的传输量数据，添加相关统计
        if current_attempt_transmitted:
            analysis["current_attempt_transmitted"] = {
                "mean": statistics.mean(current_attempt_transmitted),
                "median": statistics.median(current_attempt_transmitted),
                "std": statistics.stdev(current_attempt_transmitted) if len(current_attempt_transmitted) > 1 else 0,
                "min": min(current_attempt_transmitted),
                "max": max(current_attempt_transmitted),
                "total": sum(current_attempt_transmitted)
            }
        
        # 计算重传分布（考虑最大重传次数限制）
        retransmit_distribution = {}
        for value in retransmitted_values:
            # 确保重传次数不超过10
            capped_value = min(value, 10)
            retransmit_distribution[capped_value] = retransmit_distribution.get(capped_value, 0) + 1
        analysis["retransmitted"]["distribution"] = retransmit_distribution
        
        # 统计不同模式的结果数量
        mode_counts = {}
        for r in results:
            mode = r.get("mode", "unknown")
            mode_counts[mode] = mode_counts.get(mode, 0) + 1
        analysis["mode_distribution"] = mode_counts
        
        return analysis
    
    @staticmethod
    def verify_theoretical_model():
        """验证理论模型的正确性"""
        print("=== 理论模型验证 ===")
        print("传统IKEv2'全部重传'模型验证:")
        print("参数: N=2, D=1204字节")
        print()
        
        test_loss_rates = [15, 20, 25, 30, 35, 40]
        
        for loss_rate in test_loss_rates:
            P = loss_rate / 100
            N = 2
            D = 1204
            
            # 理论计算
            p_succ = (1 - P) ** N
            E_K = 1 / p_succ if p_succ > 0 else float('inf')
            E_Data = (N * D) * E_K if E_K != float('inf') else float('inf')
            
            print(f"丢包率 {loss_rate}%:")
            print(f"  P = {P:.2f}")
            print(f"  p_succ = (1-{P:.2f})^2 = {p_succ:.4f}")
            print(f"  E[K] = 1/{p_succ:.4f} = {E_K:.2f}")
            print(f"  E[Data_All] = {E_K:.2f} × ({N}×{D}) = {E_Data:.0f} 字节")
            print()

def main():
    """主函数"""
    print("=== 传统分片机制性能测试 - 多丢包率分析 ===")
    print(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 验证理论模型
    analyzer = PerformanceAnalyzer()
    analyzer.verify_theoretical_model()
    
    # 测试参数
    loss_rates = [15, 20, 25, 30, 35, 40]  # 丢包率百分比
    tests_per_rate = 500  # 每个丢包率运行的测试次数
    
    # 初始化组件
    runner = IkeTestRunner()
    
    # 总结果存储
    all_results = {}
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
            print(f"理论期望尝试次数: {theoretical['theoretical']['expected_attempts']:.2f}")
            
            # 运行测试
            results = []
            success_count = 0
            failure_count = 0
            
            for i in range(1, tests_per_rate + 1):
                if i % 20 == 0 or i == 1:
                    print(f"  进度: {i}/{tests_per_rate}")
                
                # 检查网络连接性
                if i % 50 == 0:  # 每50次检查一次网络
                    if not runner.check_network_connectivity():
                        print(f"  ⚠️  网络连接异常，等待恢复...")
                        time.sleep(5)
                        continue
                
                stats = runner.run_single_test()
                if stats:
                    stats["run_number"] = i
                    stats["loss_rate"] = loss_rate
                    results.append(stats)
                    success_count += 1
                else:
                    failure_count += 1
                    print(f"  ⚠️  第{i}次测试失败")
                
                # 短暂休息避免系统过载
                if i % 10 == 0:
                    time.sleep(1.0)  # 增加休息时间
                
                # 如果连续失败太多，提前结束
                if failure_count > tests_per_rate * 0.8:  # 80%失败率
                    print(f"  ⚠️  失败率过高({failure_count}/{i})，提前结束测试")
                    break
                
                # 如果连续失败5次，增加额外休息时间
                if i > 5 and failure_count >= i - 5:
                    print(f"  ⏸️  连续失败较多，增加休息时间...")
                    time.sleep(3.0)
            
            # 分析结果
            analysis = analyzer.analyze_results(results)
            
            # 存储结果
            all_results[f"{loss_rate}%"] = {
                "loss_rate": loss_rate,
                "theoretical": theoretical,
                "analysis": analysis,
                "success_count": success_count,
                "failure_count": failure_count,
                "results": results
            }
            
            # 简要统计
            if analysis:
                avg_transmitted = analysis["total_transmitted"]["mean"]
                theoretical_transmitted = theoretical["theoretical"]["total_data_traditional"]
                
                # 计算失败尝试的平均传输量
                avg_failed_transmitted = 0
                if "failed_attempts_transmitted" in analysis:
                    avg_failed_transmitted = analysis["failed_attempts_transmitted"]["mean"]
                
                summary_stats[loss_rate] = {
                    "loss_rate": loss_rate,
                    "success_count": success_count,
                    "avg_total_transmitted": avg_transmitted,
                    "avg_failed_transmitted": avg_failed_transmitted,
                    "theoretical_transmitted": theoretical_transmitted,
                    "efficiency": (2408 / avg_transmitted * 100) if avg_transmitted > 0 else 0
                }
                
                print(f"  成功: {success_count}/{tests_per_rate} ({success_count/tests_per_rate*100:.1f}%)")
                print(f"  平均传输量: {avg_transmitted:.0f} 字节")
                print(f"  传输效率: {2408/avg_transmitted*100:.1f}%")
                
                # 显示模式分布
                if "mode_distribution" in analysis:
                    print(f"  模式分布: {analysis['mode_distribution']}")
            
            # 为每个丢包率单独保存JSON文件
            timestamp = int(time.time())
            detailed_filename = f"traditional_fragment_detailed_{timestamp}_{loss_rate}.json"
            
            with open(detailed_filename, 'w', encoding='utf-8') as f:
                json.dump({
                    "metadata": {
                        "test_type": "traditional_fragmentation_performance",
                        "loss_rate": loss_rate,
                        "start_time": datetime.now().isoformat(),
                        "tests_per_rate": tests_per_rate,
                        "total_tests": tests_per_rate,
                        "success_count": success_count,
                        "failure_count": failure_count
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
    summary_filename = f"traditional_fragment_summary_{timestamp}.json"
    
    with open(summary_filename, 'w', encoding='utf-8') as f:
        json.dump({
            "metadata": {
                "test_type": "traditional_fragmentation_summary",
                "timestamp": datetime.now().isoformat(),
                "loss_rates_tested": loss_rates,
                "tests_per_rate": tests_per_rate,
                "total_tests": len(loss_rates) * tests_per_rate
            },
            "summary_statistics": summary_stats,
            "theoretical_analysis": {
                loss_rate: analyzer.calculate_theoretical_values(loss_rate) 
                for loss_rate in loss_rates
            }
        }, f, indent=2, ensure_ascii=False)
    
    # 生成分析报告
    print(f"\n=== 最终统计报告 ===")
    print(f"每个丢包率的详细结果已单独保存")
    print(f"汇总结果保存到: {summary_filename}")
    
    print(f"\n{'丢包率':<8} {'成功率':<8} {'平均传输量':<12} {'失败传输量':<12} {'传输效率':<10} {'理论值':<12}")
    print("-" * 70)
    
    for loss_rate in loss_rates:
        if loss_rate in summary_stats:
            stats = summary_stats[loss_rate]
            success_rate = stats["success_count"] / tests_per_rate * 100
            avg_failed = stats.get("avg_failed_transmitted", 0)
            print(f"{loss_rate:>5}%   {success_rate:>6.1f}%   {stats['avg_total_transmitted']:>9.0f}字节   "
                  f"{avg_failed:>9.0f}字节   {stats['efficiency']:>7.1f}%   {stats['theoretical_transmitted']:>9.0f}字节")
    
    print(f"\n测试完成于: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    # 检查权限
    if os.geteuid() != 0:
        print("Warning: This script may need sudo privileges for network control.")
    
    main() 