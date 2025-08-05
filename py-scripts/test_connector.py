#!/usr/bin/env python3
"""
strongSwan连接器测试脚本
用于验证基本功能是否正常工作
"""

import sys
import os
import json
from strongswan_connector import StrongSwanConnector


def test_config_loading():
    """测试配置加载功能"""
    print("=== 测试配置加载 ===")
    
    # 创建测试配置
    test_config = {
        "connections": {
            "test_vpn": {
                "remote_host": "test.vpn.com",
                "identity": "test@example.com",
                "psk": "test_key",
                "left": "%defaultroute",
                "leftsubnet": "0.0.0.0/0",
                "right": "%any",
                "rightsubnet": "0.0.0.0/0",
                "auto": "add"
            }
        },
        "settings": {
            "charon_log_level": "-1",
            "check_interval": 5
        }
    }
    
    # 写入测试配置文件
    test_config_file = "test_config.json"
    with open(test_config_file, 'w') as f:
        json.dump(test_config, f, indent=2)
    
    try:
        # 测试加载配置
        connector = StrongSwanConnector(test_config_file)
        print("✓ 配置加载成功")
        print(f"  连接数量: {len(connector.config.get('connections', {}))}")
        print(f"  连接名称: {list(connector.config.get('connections', {}).keys())}")
        
        # 清理测试文件
        os.remove(test_config_file)
        return True
        
    except Exception as e:
        print(f"✗ 配置加载失败: {e}")
        return False


def test_strongswan_check():
    """测试strongSwan安装检查"""
    print("\n=== 测试strongSwan安装检查 ===")
    
    connector = StrongSwanConnector()
    is_installed = connector.check_strongswan_installed()
    
    if is_installed:
        print("✓ strongSwan已安装")
    else:
        print("✗ strongSwan未安装或未找到")
        print("  请确保strongSwan已正确安装并添加到PATH中")
    
    return is_installed


def test_config_generation():
    """测试配置生成功能"""
    print("\n=== 测试配置生成 ===")
    
    connector = StrongSwanConnector()
    test_config = {
        "remote_host": "test.vpn.com",
        "identity": "test@example.com",
        "psk": "test_key",
        "left": "%defaultroute",
        "leftsubnet": "0.0.0.0/0",
        "right": "%any",
        "rightsubnet": "0.0.0.0/0",
        "auto": "add"
    }
    
    try:
        config_content = connector.create_connection_config("test_conn", test_config)
        print("✓ 配置生成成功")
        print("生成的配置内容:")
        print(config_content)
        return True
        
    except Exception as e:
        print(f"✗ 配置生成失败: {e}")
        return False


def test_status_check():
    """测试状态检查功能"""
    print("\n=== 测试状态检查 ===")
    
    connector = StrongSwanConnector()
    
    try:
        status = connector.get_connection_status()
        print("✓ 状态检查成功")
        print(f"状态信息长度: {len(status.get('details', ''))} 字符")
        return True
        
    except Exception as e:
        print(f"✗ 状态检查失败: {e}")
        return False


def test_command_execution():
    """测试命令执行功能"""
    print("\n=== 测试命令执行 ===")
    
    connector = StrongSwanConnector()
    
    try:
        # 测试一个简单的命令
        result = connector.run_command(['ipsec', 'version'], capture_output=True)
        print("✓ 命令执行成功")
        print(f"输出长度: {len(result.stdout)} 字符")
        return True
        
    except Exception as e:
        print(f"✗ 命令执行失败: {e}")
        print("  这可能是正常的，如果strongSwan未安装或需要管理员权限")
        return False


def run_all_tests():
    """运行所有测试"""
    print("开始strongSwan连接器测试...\n")
    
    tests = [
        ("配置加载", test_config_loading),
        ("strongSwan检查", test_strongswan_check),
        ("配置生成", test_config_generation),
        ("状态检查", test_status_check),
        ("命令执行", test_command_execution)
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
        print("🎉 所有测试通过！脚本应该可以正常工作。")
    else:
        print("⚠️  部分测试失败，请检查系统环境和strongSwan安装状态。")
    
    return passed == total


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1) 