#!/usr/bin/env python3
"""
第一步实现示例：load_config方法
展示如何从零开始实现配置文件加载功能
"""

import json
import os


class SimpleVPNConnector:
    """最小化VPN连接管理器"""
    
    def __init__(self, config_file: str = "vpn_config.json"):
        """初始化连接管理器"""
        self.config_file = config_file
        self.config = self.load_config()
    
    def load_config(self):
        """加载配置文件 - 这是我们要实现的方法"""
        # 第一步：检查文件是否存在
        if os.path.exists(self.config_file):
            print(f"✓ 配置文件 {self.config_file} 存在")
            
            try:
                # 第二步：打开并读取文件
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    # 第三步：解析JSON内容
                    config = json.load(f)
                    print(f"✓ 配置文件加载成功")
                    return config
                    
            except json.JSONDecodeError as e:
                # 第四步：处理JSON格式错误
                print(f"✗ 配置文件格式错误: {e}")
                return self.get_default_config()
                
        else:
            # 第五步：文件不存在时使用默认配置
            print(f"✗ 配置文件 {self.config_file} 不存在，使用默认配置")
            return self.get_default_config()
    
    def get_default_config(self):
        """获取默认配置"""
        return {
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


def test_load_config():
    """测试load_config方法"""
    print("=== 测试load_config方法 ===")
    
    # 测试1：正常情况
    print("\n1. 测试正常配置文件:")
    connector1 = SimpleVPNConnector("vpn_config.json")
    print(f"配置内容: {connector1.config}")
    
    # 测试2：文件不存在的情况
    print("\n2. 测试不存在的配置文件:")
    connector2 = SimpleVPNConnector("nonexistent.json")
    print(f"配置内容: {connector2.config}")
    
    # 测试3：格式错误的配置文件
    print("\n3. 测试格式错误的配置文件:")
    # 创建一个格式错误的配置文件
    with open("bad_config.json", "w") as f:
        f.write('{"invalid": json}')
    
    connector3 = SimpleVPNConnector("bad_config.json")
    print(f"配置内容: {connector3.config}")
    
    # 清理测试文件
    if os.path.exists("bad_config.json"):
        os.remove("bad_config.json")


def show_implementation_steps():
    """显示实现步骤"""
    print("\n=== 实现步骤详解 ===")
    print("""
1. 检查文件是否存在
   if os.path.exists(self.config_file):
   
2. 打开并读取文件
   with open(self.config_file, 'r', encoding='utf-8') as f:
   
3. 解析JSON内容
   config = json.load(f)
   
4. 处理错误情况
   except json.JSONDecodeError as e:
   
5. 返回默认配置
   return self.get_default_config()
    """)


if __name__ == "__main__":
    test_load_config()
    show_implementation_steps() 