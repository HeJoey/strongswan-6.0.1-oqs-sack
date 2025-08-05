#!/usr/bin/env python3
"""
strongSwan连接器使用示例
展示如何使用StrongSwanConnector类
"""

from strongswan_connector import StrongSwanConnector
import time


def example_basic_usage():
    """基本使用示例"""
    print("=== 基本使用示例 ===")
    
    # 创建连接器实例
    connector = StrongSwanConnector("vpn_config.json")
    
    # 检查strongSwan是否安装
    if not connector.check_strongswan_installed():
        print("strongSwan未安装，请先安装strongSwan")
        return
    
    # 列出所有连接
    connections = connector.list_connections()
    print(f"可用连接: {connections}")
    
    # 显示当前配置
    print("当前配置:")
    print(f"  配置文件: {connector.config_file}")
    print(f"  连接数量: {len(connector.config.get('connections', {}))}")
    
    return connector


def example_connection_management(connector):
    """连接管理示例"""
    print("\n=== 连接管理示例 ===")
    
    connections = connector.list_connections()
    if not connections:
        print("没有配置的连接")
        return
    
    # 选择第一个连接进行演示
    connection_name = connections[0]
    print(f"使用连接: {connection_name}")
    
    # 获取连接配置
    config = connector.config["connections"][connection_name]
    print(f"连接配置: {config}")
    
    # 检查连接状态
    print("\n检查连接状态...")
    status = connector.get_connection_status(connection_name)
    print(f"连接状态: {'活跃' if status.get('active') else '断开'}")
    
    # 注意：以下操作需要管理员权限
    print("\n注意：以下操作需要管理员权限")
    print("在实际使用中，请确保以管理员权限运行脚本")
    
    # 示例：设置连接配置（不会实际执行）
    print(f"\n示例：设置连接 {connection_name} 的配置")
    print("（实际执行需要管理员权限）")
    
    # 示例：生成配置内容
    config_content = connector.create_connection_config(connection_name, config)
    print("生成的配置内容:")
    print(config_content)


def example_monitoring(connector):
    """监控示例"""
    print("\n=== 监控示例 ===")
    
    connections = connector.list_connections()
    if not connections:
        print("没有配置的连接")
        return
    
    connection_name = connections[0]
    print(f"监控连接: {connection_name}")
    
    # 模拟监控（只监控5秒）
    print("开始监控连接状态（5秒）...")
    start_time = time.time()
    
    while time.time() - start_time < 5:
        status = connector.get_connection_status(connection_name)
        timestamp = time.strftime("%H:%M:%S")
        
        if status.get("active", False):
            print(f"[{timestamp}] 连接状态: 正常")
        else:
            print(f"[{timestamp}] 连接状态: 断开")
        
        time.sleep(1)
    
    print("监控结束")


def example_config_management(connector):
    """配置管理示例"""
    print("\n=== 配置管理示例 ===")
    
    # 显示当前配置
    print("当前配置:")
    print(f"  配置文件: {connector.config_file}")
    print(f"  连接数量: {len(connector.config.get('connections', {}))}")
    
    # 显示所有连接
    connections = connector.config.get("connections", {})
    for name, config in connections.items():
        print(f"\n连接: {name}")
        print(f"  远程主机: {config.get('remote_host', 'N/A')}")
        print(f"  身份标识: {config.get('identity', 'N/A')}")
        print(f"  本地端点: {config.get('left', 'N/A')}")
        print(f"  远程端点: {config.get('right', 'N/A')}")
    
    # 显示设置
    settings = connector.config.get("settings", {})
    print(f"\n设置:")
    print(f"  日志级别: {settings.get('charon_log_level', 'N/A')}")
    print(f"  检查间隔: {settings.get('check_interval', 'N/A')} 秒")


def example_error_handling():
    """错误处理示例"""
    print("\n=== 错误处理示例 ===")
    
    # 测试不存在的配置文件
    print("测试加载不存在的配置文件...")
    try:
        connector = StrongSwanConnector("nonexistent_config.json")
        print("✓ 成功加载默认配置")
    except Exception as e:
        print(f"✗ 加载配置失败: {e}")
    
    # 测试命令执行错误
    print("\n测试命令执行错误...")
    try:
        connector = StrongSwanConnector()
        result = connector.run_command(['nonexistent_command'])
        print("✓ 命令执行成功")
    except Exception as e:
        print(f"✗ 命令执行失败: {e}")


def main():
    """主函数"""
    print("strongSwan连接器使用示例")
    print("=" * 50)
    
    try:
        # 基本使用示例
        connector = example_basic_usage()
        
        if connector:
            # 连接管理示例
            example_connection_management(connector)
            
            # 监控示例
            example_monitoring(connector)
            
            # 配置管理示例
            example_config_management(connector)
        
        # 错误处理示例
        example_error_handling()
        
        print("\n" + "=" * 50)
        print("示例运行完成！")
        print("\n要实际使用VPN连接功能，请：")
        print("1. 编辑 vpn_config.json 文件，添加您的VPN配置")
        print("2. 以管理员权限运行脚本")
        print("3. 使用交互模式或命令行参数")
        
    except Exception as e:
        print(f"示例运行出错: {e}")


if __name__ == "__main__":
    main() 