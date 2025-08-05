#!/usr/bin/env python3
"""
分阶段IKE性能测试 - 专门测试中间交换阶段在丢包条件下的性能
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

class StagedIkeTestRunner:
    """分阶段IKE测试运行器"""
    
    def __init__(self):
        self.network_controller = NetworkController()
        self.connection_name = "net-net"
    
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
    
    def run_ikeinit(self) -> bool:
        """运行IKE_SA_INIT阶段"""
        print("  🔗 执行IKE_SA_INIT阶段...")
        command = f"sudo swanctl --ikeinit --ike {self.connection_name}"
        output = self.run_command(command, timeout=35)
        
        if "completed successfully" in output or "IKE_SA_INIT completed successfully" in output:
            print("  ✅ IKE_SA_INIT成功")
            return True
        else:
            print(f"  ❌ IKE_SA_INIT失败: {output[:100]}...")
            return False
    
    def run_ikeinter_with_loss(self, loss_rate: float) -> Optional[Dict]:
        """在丢包条件下运行IKE_INTERMEDIATE阶段"""
        print(f"  🔗 在{loss_rate}%丢包率下执行IKE_INTERMEDIATE阶段...")
        
        # 设置丢包率
        if not self.network_controller.set_packet_loss(loss_rate):
            print("  ❌ 设置丢包率失败")
            return None
        
        # 运行IKE_INTERMEDIATE
        command = f"sudo swanctl --ikeinter --ike {self.connection_name}"
        output = self.run_command(command, timeout=35)
        
        # 提取统计数据
        stats = self.extract_ike_stats(output)
        
        if "completed successfully" in output or "IKE_INTERMEDIATE completed successfully" in output:
            print("  ✅ IKE_INTERMEDIATE成功")
            if stats:
                print(f"  📊 传输量: {stats['total_transmitted']} 字节")
            return stats
        else:
            print(f"  ❌ IKE_INTERMEDIATE失败: {output[:100]}...")
            return None
    
    def run_ikeauth(self) -> bool:
        """运行IKE_AUTH阶段"""
        print("  🔗 执行IKE_AUTH阶段...")
        command = f"sudo swanctl --ikeauth --ike {self.connection_name}"
        output = self.run_command(command, timeout=35)
        
        if "completed successfully" in output or "IKE_AUTH completed successfully" in output:
            print("  ✅ IKE_AUTH成功")
            return True
        else:
            print(f"  ❌ IKE_AUTH失败: {output[:100]}...")
            return False
    
    def cleanup_connection(self):
        """清理连接"""
        print("  🧹 清理连接...")
        command = f"sudo swanctl --terminate --ike {self.connection_name}"
        self.run_command(command, timeout=10)
        time.sleep(2)
    
    def run_single_staged_test(self, loss_rate: float) -> Optional[Dict]:
        """运行单次分阶段测试"""
        max_retries = 3
        
        for attempt in range(max_retries):
            try:
                # 清理可能存在的连接
                if attempt > 0:
                    print(f"  🔄 重试第{attempt}次，清理连接...")
                    self.cleanup_connection()
                
                # 重启strongswan服务
                print("  🔄 重启strongswan服务...")
                self.run_command("sudo systemctl restart strongswan")
                time.sleep(3)
                
                # 检查服务状态
                status_output = self.run_command("sudo systemctl is-active strongswan", timeout=10)
                if "active" not in status_output:
                    print(f"  ⚠️  strongswan服务未正常启动，重试...")
                    continue
                
                # 步骤1: IKE_SA_INIT (无丢包)
                if not self.run_ikeinit():
                    print(f"  ❌ IKE_SA_INIT失败 (尝试{attempt+1}/{max_retries})")
                    if attempt < max_retries - 1:
                        time.sleep(2)
                        continue
                    else:
                        return None
                
                # 步骤2: IKE_INTERMEDIATE (有丢包)
                stats = self.run_ikeinter_with_loss(loss_rate)
                if not stats:
                    print(f"  ❌ IKE_INTERMEDIATE失败 (尝试{attempt+1}/{max_retries})")
                    if attempt < max_retries - 1:
                        time.sleep(2)
                        continue
                    else:
                        return None
                
                # 步骤3: IKE_AUTH (无丢包)
                if not self.run_ikeauth():
                    print(f"  ❌ IKE_AUTH失败 (尝试{attempt+1}/{max_retries})")
                    if attempt < max_retries - 1:
                        time.sleep(2)
                        continue
                    else:
                        return None
                
                # 清理连接
                self.cleanup_connection()
                
                return stats
                
            except Exception as e:
                print(f"  ❌ 单次测试错误 (尝试{attempt+1}/{max_retries}): {e}")
                if attempt < max_retries - 1:
                    time.sleep(2)
                    continue
                else:
                    return None
        
        return None

class PerformanceAnalyzer:
    """性能分析器"""
    
    @staticmethod
    def analyze_results(results: List[Dict]) -> Dict:
        """分析结果数据"""
        if not results:
            return {}
        
        # 提取数据
        total_transmitted_values = [r["total_transmitted"] for r in results]
        retransmitted_values = [r["retransmitted"] for r in results]
        
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
        
        # 计算重传分布
        retransmit_distribution = {}
        for value in retransmitted_values:
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

def main():
    """主函数"""
    print("=== 分阶段IKE性能测试 - 中间交换阶段丢包分析 ===")
    print(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # 测试参数
    loss_rates = [5, 10, 15, 20, 25, 30, 35, 40]  # 丢包率百分比
    tests_per_rate = 100  # 每个丢包率运行的测试次数
    
    # 初始化组件
    runner = StagedIkeTestRunner()
    analyzer = PerformanceAnalyzer()
    
    # 总结果存储
    all_results = {}
    summary_stats = {}
    
    try:
        for loss_rate in loss_rates:
            print(f"\n=== 测试丢包率: {loss_rate}% ===")
            
            # 运行测试
            results = []
            success_count = 0
            failure_count = 0
            
            for i in range(1, tests_per_rate + 1):
                if i % 10 == 0 or i == 1:
                    print(f"  进度: {i}/{tests_per_rate}")
                
                # 检查网络连接性
                if i % 20 == 0:
                    if not runner.check_network_connectivity():
                        print(f"  ⚠️  网络连接异常，等待恢复...")
                        time.sleep(5)
                        continue
                
                stats = runner.run_single_staged_test(loss_rate)
                if stats:
                    stats["run_number"] = i
                    stats["loss_rate"] = loss_rate
                    results.append(stats)
                    success_count += 1
                else:
                    failure_count += 1
                    print(f"  ⚠️  第{i}次测试失败")
                
                # 短暂休息避免系统过载
                if i % 5 == 0:
                    time.sleep(1.0)
                
                # 如果连续失败太多，提前结束
                if failure_count > tests_per_rate * 0.8:
                    print(f"  ⚠️  失败率过高({failure_count}/{i})，提前结束测试")
                    break
            
            # 分析结果
            analysis = analyzer.analyze_results(results)
            
            # 存储结果
            all_results[f"{loss_rate}%"] = {
                "loss_rate": loss_rate,
                "analysis": analysis,
                "success_count": success_count,
                "failure_count": failure_count,
                "results": results
            }
            
            # 简要统计
            if analysis:
                avg_transmitted = analysis["total_transmitted"]["mean"]
                
                summary_stats[loss_rate] = {
                    "loss_rate": loss_rate,
                    "success_count": success_count,
                    "avg_total_transmitted": avg_transmitted,
                    "efficiency": (2408 / avg_transmitted * 100) if avg_transmitted > 0 else 0
                }
                
                print(f"  成功: {success_count}/{tests_per_rate} ({success_count/tests_per_rate*100:.1f}%)")
                print(f"  平均传输量: {avg_transmitted:.0f} 字节")
                print(f"  传输效率: {2408/avg_transmitted*100:.1f}%")
            
            # 为每个丢包率单独保存JSON文件
            timestamp = int(time.time())
            detailed_filename = f"staged_fragment_detailed_{timestamp}_{loss_rate}.json"
            
            with open(detailed_filename, 'w', encoding='utf-8') as f:
                json.dump({
                    "metadata": {
                        "test_type": "staged_fragmentation_performance",
                        "loss_rate": loss_rate,
                        "start_time": datetime.now().isoformat(),
                        "tests_per_rate": tests_per_rate,
                        "total_tests": tests_per_rate,
                        "success_count": success_count,
                        "failure_count": failure_count
                    },
                    "performance_analysis": analysis,
                    "detailed_results": results
                }, f, indent=2, ensure_ascii=False)
            
            print(f"  📁 详细结果已保存到: {detailed_filename}")
    
    finally:
        # 重置网络条件
        runner.network_controller.reset_network()
    
    # 保存汇总结果
    timestamp = int(time.time())
    summary_filename = f"staged_fragment_summary_{timestamp}.json"
    
    with open(summary_filename, 'w', encoding='utf-8') as f:
        json.dump({
            "metadata": {
                "test_type": "staged_fragmentation_summary",
                "timestamp": datetime.now().isoformat(),
                "loss_rates_tested": loss_rates,
                "tests_per_rate": tests_per_rate,
                "total_tests": len(loss_rates) * tests_per_rate
            },
            "summary_statistics": summary_stats
        }, f, indent=2, ensure_ascii=False)
    
    # 生成分析报告
    print(f"\n=== 最终统计报告 ===")
    print(f"每个丢包率的详细结果已单独保存")
    print(f"汇总结果保存到: {summary_filename}")
    
    print(f"\n{'丢包率':<8} {'成功率':<8} {'平均传输量':<12} {'传输效率':<10}")
    print("-" * 50)
    
    for loss_rate in loss_rates:
        if loss_rate in summary_stats:
            stats = summary_stats[loss_rate]
            success_rate = stats["success_count"] / tests_per_rate * 100
            print(f"{loss_rate:>5}%   {success_rate:>6.1f}%   {stats['avg_total_transmitted']:>9.0f}字节   "
                  f"{stats['efficiency']:>7.1f}%")
    
    print(f"\n测试完成于: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    # 检查权限
    if os.geteuid() != 0:
        print("Warning: This script may need sudo privileges for network control.")
    
    main() 