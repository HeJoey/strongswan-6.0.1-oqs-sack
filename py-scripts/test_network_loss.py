#!/usr/bin/env python3
"""
网络丢包测试脚本
用于快速测试网络丢包功能
"""

import subprocess
import sys
import time
from network_loss_simulator import NetworkLossSimulator

def test_network_loss():
    """测试网络丢包功能"""
    simulator = NetworkLossSimulator()
    
    # 获取网络接口
    try:
        result = subprocess.run(['ip', 'route', 'get', '8.8.8.8'], 
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            # 解析输出获取接口名称
            output = result.stdout
            interface = output.split('dev')[1].split()[0].strip()
            print(f"检测到网络接口: {interface}")
        else:
            print("无法自动检测网络接口，请手动指定")
            interface = input("请输入网络接口名称 (如: eth0): ").strip()
    except Exception as e:
        print(f"检测网络接口失败: {e}")
        interface = input("请输入网络接口名称 (如: eth0): ").strip()
    
    if not interface:
        print("错误: 未指定网络接口")
        return False
    
    print(f"\n开始测试网络丢包功能...")
    print(f"接口: {interface}")
    
    # 测试1: 设置5%丢包率
    print(f"\n=== 测试1: 设置5%丢包率 ===")
    if simulator.set_network_loss(interface, 5.0):
        print("✓ 设置成功")
        simulator.test_connectivity()
    else:
        print("✗ 设置失败")
        return False
    
    # 测试2: 设置10%丢包率
    print(f"\n=== 测试2: 设置10%丢包率 ===")
    if simulator.set_network_loss(interface, 10.0):
        print("✓ 设置成功")
        simulator.test_connectivity()
    else:
        print("✗ 设置失败")
        return False
    
    # 测试3: 设置丢包率+延迟
    print(f"\n=== 测试3: 设置5%丢包率+50ms延迟 ===")
    if simulator.set_network_loss(interface, 5.0, 50):
        print("✓ 设置成功")
        simulator.test_connectivity()
    else:
        print("✗ 设置失败")
        return False
    
    # 测试4: 清除设置
    print(f"\n=== 测试4: 清除网络设置 ===")
    if simulator.clear_network_loss(interface):
        print("✓ 清除成功")
        simulator.test_connectivity()
    else:
        print("✗ 清除失败")
        return False
    
    print(f"\n=== 所有测试完成 ===")
    return True

def main():
    """主函数"""
    print("网络丢包功能测试")
    print("=" * 50)
    
    # 检查权限
    if subprocess.run(['sudo', '-n', 'true'], capture_output=True).returncode != 0:
        print("错误: 需要sudo权限")
        print("请使用: sudo python3 test_network_loss.py")
        sys.exit(1)
    
    # 检查tc命令
    try:
        result = subprocess.run(['tc', '-help'], capture_output=True, text=True, timeout=5)
        if result.returncode != 0:
            print("错误: tc命令不可用")
            print("请安装iproute2: sudo apt-get install iproute2")
            sys.exit(1)
    except FileNotFoundError:
        print("错误: tc命令未找到")
        print("请安装iproute2: sudo apt-get install iproute2")
        sys.exit(1)
    
    # 运行测试
    if test_network_loss():
        print("✓ 所有测试通过")
    else:
        print("✗ 测试失败")
        sys.exit(1)

if __name__ == "__main__":
    main() 