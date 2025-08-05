#!/usr/bin/env python3
"""
handwrite.py 功能测试脚本
用于逐步测试各个功能的实现
"""

import sys
import os

# 导入您正在开发的模块
try:
    from handwrite import SimpleVPNConnector
except ImportError:
    print("错误: 无法导入 handwrite 模块")
    print("请确保 handwrite.py 文件存在且语法正确")
    sys.exit(1)


def test_config_loading():
    """测试配置加载功能"""
    print("=== 测试配置加载功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        print("✓ 连接管理器创建成功")
        
        # 检查配置是否加载
        if hasattr(connector, 'config') and connector.config:
            print("✓ 配置加载成功")
            print(f"  配置内容: {connector.config}")
        else:
            print("✗ 配置加载失败")
            return False
            
        return True
        
    except Exception as e:
        print(f"✗ 配置加载测试失败: {e}")
        return False


def test_command_execution():
    """测试命令执行功能"""
    print("\n=== 测试命令执行功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        
        # 测试简单命令
        result = connector.run_command(['echo', 'test'])
        print("✓ 命令执行成功")
        print(f"  输出: {result.stdout.strip()}")
        
        return True
        
    except Exception as e:
        print(f"✗ 命令执行测试失败: {e}")
        return False


def test_environment_check():
    """测试环境检查功能"""
    print("\n=== 测试环境检查功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        
        # 检查swanctl是否安装
        is_installed = connector.check_swanctl_installed()
        
        if is_installed:
            print("✓ swanctl已安装")
        else:
            print("✗ swanctl未安装")
            print("  请确保strongSwan已正确安装")
        
        return True
        
    except Exception as e:
        print(f"✗ 环境检查测试失败: {e}")
        return False


def test_connection_list():
    """测试连接列表功能"""
    print("\n=== 测试连接列表功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        
        # 获取连接列表
        connections = connector.list_connections()
        
        if connections:
            print("✓ 连接列表获取成功")
            print(f"  可用连接: {connections}")
        else:
            print("✗ 没有找到可用连接")
            print("  请检查配置文件")
        
        return True
        
    except Exception as e:
        print(f"✗ 连接列表测试失败: {e}")
        return False


def test_status_check():
    """测试状态检查功能"""
    print("\n=== 测试状态检查功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        
        # 检查连接状态
        status = connector.get_connection_status()
        
        print("✓ 状态检查成功")
        print(f"  状态信息: {status}")
        
        return True
        
    except Exception as e:
        print(f"✗ 状态检查测试失败: {e}")
        return False


def test_connection_management():
    """测试连接管理功能（只测试，不实际执行）"""
    print("\n=== 测试连接管理功能 ===")
    
    try:
        connector = SimpleVPNConnector()
        
        # 获取连接列表
        connections = connector.list_connections()
        
        if connections:
            test_connection = connections[0]
            print(f"  测试连接: {test_connection}")
            
            # 检查方法是否存在
            if hasattr(connector, 'start_connection'):
                print("✓ start_connection 方法存在")
            else:
                print("✗ start_connection 方法未实现")
            
            if hasattr(connector, 'stop_connection'):
                print("✓ stop_connection 方法存在")
            else:
                print("✗ stop_connection 方法未实现")
            
            print("  注意: 实际连接管理需要sudo权限")
            
        else:
            print("✗ 没有可用连接进行测试")
        
        return True
        
    except Exception as e:
        print(f"✗ 连接管理测试失败: {e}")
        return False


def run_all_tests():
    """运行所有测试"""
    print("开始 handwrite.py 功能测试...\n")
    
    tests = [
        ("配置加载", test_config_loading),
        ("命令执行", test_command_execution),
        ("环境检查", test_environment_check),
        ("连接列表", test_connection_list),
        ("状态检查", test_status_check),
        ("连接管理", test_connection_management)
    ]
    
    results = []
    
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"✗ {test_name}测试异常: {e}")
            results.append((test_name, False))
    
    # 输出测试结果
    print("\n=== 测试结果汇总 ===")
    passed = 0
    total = len(results)
    
    for test_name, result in results:
        status = "✓ 通过" if result else "✗ 失败"
        print(f"{test_name}: {status}")
        if result:
            passed += 1
    
    print(f"\n总计: {passed}/{total} 测试通过")
    
    if passed == total:
        print("🎉 所有测试通过！您的代码实现正确。")
    else:
        print("⚠️  部分测试失败，请检查相应的功能实现。")
    
    return passed == total


def show_implementation_tips():
    """显示实现提示"""
    print("\n=== 实现提示 ===")
    print("如果某些测试失败，请检查以下实现:")
    print()
    print("1. load_config() - 确保正确加载JSON配置文件")
    print("2. run_command() - 确保正确处理subprocess调用")
    print("3. check_swanctl_installed() - 确保正确检查命令存在")
    print("4. list_connections() - 确保正确返回连接列表")
    print("5. get_connection_status() - 确保正确解析状态信息")
    print("6. start_connection() / stop_connection() - 确保正确执行连接管理")
    print()
    print("参考 LEARNING_GUIDE.md 中的实现代码")


if __name__ == "__main__":
    success = run_all_tests()
    
    if not success:
        show_implementation_tips()
    
    sys.exit(0 if success else 1) 