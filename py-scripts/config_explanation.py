#!/usr/bin/env python3
"""
配置加载说明
解释为什么需要加载配置文件，以及配置的作用
"""

import json
import os


def show_config_purpose():
    """展示配置的作用"""
    print("=== 为什么需要加载配置？ ===")
    print()
    
    print("1. 配置文件存储了连接信息：")
    config = {
        "connections": {
            "host-host": {
                "remote_host": "192.168.230.234",
                "description": "主机到主机连接"
            },
            "net-net": {
                "remote_host": "192.168.31.138", 
                "description": "网络到网络连接"
            }
        }
    }
    
    print("   配置文件告诉程序：")
    print("   - 有哪些VPN连接可以管理")
    print("   - 每个连接的远程主机地址")
    print("   - 每个连接的描述信息")
    print()
    
    print("2. 程序需要知道要管理哪些连接：")
    connections = list(config["connections"].keys())
    print(f"   可用连接: {connections}")
    print()
    
    print("3. 程序需要知道每个连接的详细信息：")
    for name, info in config["connections"].items():
        print(f"   连接名: {name}")
        print(f"   远程主机: {info['remote_host']}")
        print(f"   描述: {info['description']}")
        print()


def show_without_config():
    """展示没有配置的情况"""
    print("=== 如果没有配置文件会怎样？ ===")
    print()
    
    print("1. 程序不知道有哪些连接：")
    print("   - 不知道要启动哪个连接")
    print("   - 不知道要停止哪个连接")
    print("   - 不知道连接的目标地址")
    print()
    
    print("2. 程序只能硬编码连接信息：")
    print("   - 每次修改连接都要改代码")
    print("   - 不能动态添加新连接")
    print("   - 不够灵活")
    print()


def show_with_config():
    """展示有配置的情况"""
    print("=== 有了配置文件的好处 ===")
    print()
    
    print("1. 程序可以动态读取连接信息：")
    print("   - 不需要修改代码就能添加新连接")
    print("   - 可以随时修改连接配置")
    print("   - 配置和代码分离")
    print()
    
    print("2. 程序可以列出所有可用连接：")
    config = {
        "connections": {
            "host-host": {"remote_host": "192.168.230.234"},
            "net-net": {"remote_host": "192.168.31.138"},
            "office-vpn": {"remote_host": "10.0.0.1"}  # 新增连接
        }
    }
    
    connections = list(config["connections"].keys())
    print(f"   可用连接: {connections}")
    print()
    
    print("3. 程序可以根据配置执行操作：")
    for name in connections:
        print(f"   - 可以启动 {name} 连接")
        print(f"   - 可以停止 {name} 连接")
        print(f"   - 可以检查 {name} 状态")


def show_practical_example():
    """展示实际使用示例"""
    print("\n=== 实际使用示例 ===")
    print()
    
    # 模拟加载配置
    config_file = "vpn_config.json"
    
    if os.path.exists(config_file):
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        print("1. 程序启动时加载配置：")
        print(f"   配置文件: {config_file}")
        print(f"   找到连接: {list(config['connections'].keys())}")
        print()
        
        print("2. 用户选择要操作的连接：")
        connections = list(config['connections'].keys())
        print(f"   可用连接: {connections}")
        print()
        
        print("3. 程序根据配置执行操作：")
        for name in connections:
            remote_host = config['connections'][name]['remote_host']
            print(f"   连接 {name} -> {remote_host}")
            print(f"   执行: swanctl --initiate --child {name}")
        print()
        
        print("4. 如果用户想添加新连接：")
        print("   只需要修改配置文件，不需要改代码！")
        print("   这就是配置加载的价值所在")


def main():
    """主函数"""
    show_config_purpose()
    show_without_config()
    show_with_config()
    show_practical_example()
    
    print("\n=== 总结 ===")
    print("配置文件的作用：")
    print("1. 存储连接信息（不需要硬编码在代码中）")
    print("2. 让程序知道有哪些连接可以管理")
    print("3. 提供每个连接的详细信息")
    print("4. 允许用户修改连接而不需要改代码")
    print("5. 使程序更加灵活和可维护")


if __name__ == "__main__":
    main() 