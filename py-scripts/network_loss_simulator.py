#!/usr/bin/env python3
"""
网络丢包率模拟器
用于测试strongSwan的选择性重传机制

使用方法:
    python3 network_loss_simulator.py --interface eth0 --loss 5.0
    python3 network_loss_simulator.py --interface eth0 --loss 10.0 --delay 50
    python3 network_loss_simulator.py --interface eth0 --clear
"""

import argparse
import subprocess
import sys
import time
import json
from datetime import datetime

class NetworkLossSimulator:
    def __init__(self):
        self.interface = None
        self.current_loss = 0.0
        self.current_delay = 0
        self.is_active = False
        
    def check_tc_installed(self):
        """检查tc命令是否可用"""
        try:
            result = subprocess.run(['tc', '-help'], 
                                  capture_output=True, text=True, timeout=5)
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False
    
    def get_interface_status(self, interface):
        """获取网络接口状态"""
        try:
            result = subprocess.run(['ip', 'link', 'show', interface], 
                                  capture_output=True, text=True, timeout=5)
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False
    
    def set_network_loss(self, interface, loss_percent, delay_ms=0, jitter_ms=0):
        """设置网络丢包率和延迟"""
        if not self.check_tc_installed():
            print("错误: tc命令不可用，请安装iproute2包")
            return False
        
        if not self.get_interface_status(interface):
            print(f"错误: 网络接口 {interface} 不存在或不可用")
            return False
        
        try:
            # 清除现有的tc规则
            subprocess.run(['sudo', 'tc', 'qdisc', 'del', 'dev', interface, 'root'], 
                         capture_output=True)
        except subprocess.CalledProcessError:
            pass  # 如果没有现有规则，会报错，这是正常的
        
        # 构建tc命令
        tc_cmd = ['sudo', 'tc', 'qdisc', 'add', 'dev', interface, 'root', 'netem']
        
        if loss_percent > 0:
            tc_cmd.extend(['loss', f'{loss_percent}%'])
        
        if delay_ms > 0:
            if jitter_ms > 0:
                tc_cmd.extend(['delay', f'{delay_ms}ms', f'{jitter_ms}ms'])
            else:
                tc_cmd.extend(['delay', f'{delay_ms}ms'])
        
        # 执行tc命令
        result = subprocess.run(tc_cmd, capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            self.interface = interface
            self.current_loss = loss_percent
            self.current_delay = delay_ms
            self.is_active = True
            
            print(f"✓ 成功设置网络参数:")
            print(f"  接口: {interface}")
            print(f"  丢包率: {loss_percent}%")
            print(f"  延迟: {delay_ms}ms")
            if jitter_ms > 0:
                print(f"  抖动: {jitter_ms}ms")
            return True
        else:
            print(f"✗ 设置失败: {result.stderr}")
            return False
    
    def clear_network_loss(self, interface):
        """清除网络丢包设置"""
        try:
            result = subprocess.run(['sudo', 'tc', 'qdisc', 'del', 'dev', interface, 'root'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                self.is_active = False
                self.current_loss = 0.0
                self.current_delay = 0
                print(f"✓ 已清除 {interface} 的网络丢包设置")
                return True
            else:
                print(f"✗ 清除失败: {result.stderr}")
                return False
        except subprocess.CalledProcessError:
            print(f"✗ 清除失败: 可能没有现有的tc规则")
            return False
    
    def show_current_status(self, interface):
        """显示当前网络状态"""
        try:
            result = subprocess.run(['sudo', 'tc', 'qdisc', 'show', 'dev', interface], 
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                print(f"当前 {interface} 的网络状态:")
                print(result.stdout)
            else:
                print(f"{interface} 没有设置tc规则")
        except subprocess.CalledProcessError:
            print(f"无法获取 {interface} 的网络状态")
    
    def test_connectivity(self, target="8.8.8.8", count=5):
        """测试网络连通性"""
        print(f"\n测试网络连通性 (ping {target}):")
        try:
            result = subprocess.run(['ping', '-c', str(count), target], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print("✓ 网络连通性正常")
                print(result.stdout)
            else:
                print("✗ 网络连通性异常")
                print(result.stderr)
        except subprocess.TimeoutExpired:
            print("✗ 网络连通性测试超时")
    
    def save_config(self, filename="network_loss_config.json"):
        """保存当前配置"""
        config = {
            "interface": self.interface,
            "loss_percent": self.current_loss,
            "delay_ms": self.current_delay,
            "is_active": self.is_active,
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            with open(filename, 'w') as f:
                json.dump(config, f, indent=2)
            print(f"✓ 配置已保存到 {filename}")
        except Exception as e:
            print(f"✗ 保存配置失败: {e}")
    
    def load_config(self, filename="network_loss_config.json"):
        """加载配置"""
        try:
            with open(filename, 'r') as f:
                config = json.load(f)
            
            print(f"✓ 从 {filename} 加载配置:")
            for key, value in config.items():
                if key != "timestamp":
                    print(f"  {key}: {value}")
            
            return config
        except FileNotFoundError:
            print(f"✗ 配置文件 {filename} 不存在")
            return None
        except Exception as e:
            print(f"✗ 加载配置失败: {e}")
            return None

def main():
    parser = argparse.ArgumentParser(description="网络丢包率模拟器")
    parser.add_argument('--interface', '-i', required=True, 
                       help='网络接口名称 (如: eth0, ens33)')
    parser.add_argument('--loss', '-l', type=float, default=0.0,
                       help='丢包率百分比 (0.0-100.0)')
    parser.add_argument('--delay', '-d', type=int, default=0,
                       help='延迟毫秒数')
    parser.add_argument('--jitter', '-j', type=int, default=0,
                       help='抖动毫秒数')
    parser.add_argument('--clear', '-c', action='store_true',
                       help='清除网络丢包设置')
    parser.add_argument('--status', '-s', action='store_true',
                       help='显示当前网络状态')
    parser.add_argument('--test', '-t', action='store_true',
                       help='测试网络连通性')
    parser.add_argument('--save', action='store_true',
                       help='保存当前配置')
    parser.add_argument('--load', action='store_true',
                       help='加载保存的配置')
    parser.add_argument('--config-file', default='network_loss_config.json',
                       help='配置文件路径')
    
    args = parser.parse_args()
    
    simulator = NetworkLossSimulator()
    
    # 检查权限
    if subprocess.run(['sudo', '-n', 'true'], capture_output=True).returncode != 0:
        print("错误: 需要sudo权限来设置网络参数")
        print("请使用: sudo python3 network_loss_simulator.py ...")
        sys.exit(1)
    
    # 处理命令
    if args.clear:
        simulator.clear_network_loss(args.interface)
    elif args.status:
        simulator.show_current_status(args.interface)
    elif args.test:
        simulator.test_connectivity()
    elif args.save:
        simulator.save_config(args.config_file)
    elif args.load:
        config = simulator.load_config(args.config_file)
        if config and config.get('is_active'):
            simulator.set_network_loss(
                config['interface'], 
                config['loss_percent'], 
                config['delay_ms']
            )
    else:
        # 设置网络丢包
        if simulator.set_network_loss(args.interface, args.loss, args.delay, args.jitter):
            print("\n提示:")
            print("- 使用 --clear 清除设置")
            print("- 使用 --status 查看当前状态")
            print("- 使用 --test 测试连通性")
            print("- 使用 --save 保存配置")

if __name__ == "__main__":
    main() 