#!/usr/bin/env python3
"""
简易strongSwan连接脚本
支持基本的VPN连接管理功能
"""

import subprocess
import json
import time
import sys
import os
import argparse
from typing import Dict, List, Optional


class StrongSwanConnector:
    """strongSwan连接管理器"""
    
    def __init__(self, config_file: str = "vpn_config.json"):
        self.config_file = config_file
        self.config = self.load_config()
    
    def load_config(self) -> Dict:
        """加载配置文件"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                print(f"配置文件 {self.config_file} 格式错误")
                return self.get_default_config()
        else:
            return self.get_default_config()
    
    def get_default_config(self) -> Dict:
        """获取默认配置"""
        return {
            "connections": {
                "default": {
                    "remote_host": "vpn.example.com",
                    "identity": "client@example.com",
                    "psk": "your_pre_shared_key",
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
    
    def save_config(self):
        """保存配置到文件"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=2, ensure_ascii=False)
            print(f"配置已保存到 {self.config_file}")
        except Exception as e:
            print(f"保存配置失败: {e}")
    
    def run_command(self, command: List[str], capture_output: bool = True) -> subprocess.CompletedProcess:
        """执行命令"""
        try:
            if capture_output:
                result = subprocess.run(command, capture_output=True, text=True, check=True)
            else:
                result = subprocess.run(command, check=True)
            return result
        except subprocess.CalledProcessError as e:
            print(f"命令执行失败: {' '.join(command)}")
            print(f"错误信息: {e.stderr if e.stderr else e}")
            raise
    
    def check_strongswan_installed(self) -> bool:
        """检查strongSwan是否已安装"""
        try:
            result = subprocess.run(['which', 'swanctl'], capture_output=True, text=True)
            return result.returncode == 0
        except Exception:
            return False
    
    def get_connection_status(self, connection_name: str = None) -> Dict:
        """获取连接状态"""
        try:
            result = self.run_command(['swanctl', '--list-sas'])
            status_text = result.stdout
            
            # 解析状态信息
            status = {
                "connections": [],
                "active": False,
                "details": status_text
            }
            
            if connection_name:
                # 检查特定连接
                if connection_name in status_text:
                    status["active"] = True
                    status["connection_name"] = connection_name
            
            return status
        except Exception as e:
            return {"error": str(e), "active": False}
    
    def create_connection_config(self, connection_name: str, config: Dict) -> str:
        """创建连接配置"""
        config_template = f"""
conn {connection_name}
    left={config.get('left', '%defaultroute')}
    leftsubnet={config.get('leftsubnet', '0.0.0.0/0')}
    right={config.get('right', '%any')}
    rightsubnet={config.get('rightsubnet', '0.0.0.0/0')}
    rightid={config.get('remote_host', 'vpn.example.com')}
    leftid={config.get('identity', 'client@example.com')}
    auto={config.get('auto', 'add')}
    keyexchange=ikev2
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
    keyingtries=3
    dpdaction=hold
    dpddelay=30s
    dpdtimeout=150s
"""
        return config_template
    
    def setup_connection(self, connection_name: str, config: Dict) -> bool:
        """设置连接配置（已预配置，仅检查配置是否存在）"""
        try:
            # 检查swanctl配置中是否存在该连接
            swanctl_conf = "/etc/swanctl/swanctl.conf"
            if os.path.exists(swanctl_conf):
                with open(swanctl_conf, 'r') as f:
                    content = f.read()
                    if connection_name in content:
                        print(f"连接 {connection_name} 配置已存在于swanctl.conf中")
                        return True
                    else:
                        print(f"警告: 连接 {connection_name} 在swanctl.conf中未找到")
                        return False
            else:
                print(f"警告: 未找到swanctl.conf配置文件")
                return False
            
        except Exception as e:
            print(f"检查连接配置失败: {e}")
            return False
    
    def start_connection(self, connection_name: str) -> bool:
        """启动连接"""
        try:
            print(f"正在启动连接 {connection_name}...")
            
            # 使用swanctl启动连接
            self.run_command(['swanctl', '--load-all'])
            self.run_command(['swanctl', '--initiate', '--child', connection_name])
            
            # 等待连接建立
            time.sleep(3)
            
            # 检查连接状态
            status = self.get_connection_status(connection_name)
            if status.get("active", False):
                print(f"连接 {connection_name} 已成功建立")
                return True
            else:
                print(f"连接 {connection_name} 建立失败")
                return False
                
        except Exception as e:
            print(f"启动连接失败: {e}")
            return False
    
    def stop_connection(self, connection_name: str) -> bool:
        """停止连接"""
        try:
            print(f"正在停止连接 {connection_name}...")
            self.run_command(['swanctl', '--terminate', '--child', connection_name])
            print(f"连接 {connection_name} 已停止")
            return True
        except Exception as e:
            print(f"停止连接失败: {e}")
            return False
    
    def restart_connection(self, connection_name: str) -> bool:
        """重启连接"""
        print(f"正在重启连接 {connection_name}...")
        self.stop_connection(connection_name)
        time.sleep(2)
        return self.start_connection(connection_name)
    
    def list_connections(self) -> List[str]:
        """列出所有连接"""
        return list(self.config.get("connections", {}).keys())
    
    def monitor_connection(self, connection_name: str, duration: int = 60):
        """监控连接状态"""
        print(f"开始监控连接 {connection_name}，持续 {duration} 秒...")
        start_time = time.time()
        
        while time.time() - start_time < duration:
            status = self.get_connection_status(connection_name)
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            
            if status.get("active", False):
                print(f"[{timestamp}] 连接 {connection_name} 状态: 正常")
            else:
                print(f"[{timestamp}] 连接 {connection_name} 状态: 断开")
            
            time.sleep(self.config.get("settings", {}).get("check_interval", 5))
    
    def interactive_mode(self):
        """交互模式"""
        print("=== strongSwan 连接管理器 ===")
        
        while True:
            print("\n可用操作:")
            print("1. 列出连接")
            print("2. 启动连接")
            print("3. 停止连接")
            print("4. 重启连接")
            print("5. 查看状态")
            print("6. 监控连接")
            print("7. 编辑配置")
            print("8. 退出")
            
            choice = input("\n请选择操作 (1-8): ").strip()
            
            if choice == "1":
                connections = self.list_connections()
                if connections:
                    print("可用连接:")
                    for conn in connections:
                        print(f"  - {conn}")
                else:
                    print("没有配置的连接")
            
            elif choice == "2":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        config = self.config["connections"][conn_name]
                        if self.setup_connection(conn_name, config):
                            self.start_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "3":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        self.stop_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "4":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        self.restart_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "5":
                status = self.get_connection_status()
                print("连接状态:")
                print(status.get("details", "无法获取状态"))
            
            elif choice == "6":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        duration = input("监控时长(秒，默认60): ").strip()
                        try:
                            duration = int(duration) if duration else 60
                            self.monitor_connection(conn_name, duration)
                        except ValueError:
                            print("无效的时长")
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "7":
                print("配置文件位置:", self.config_file)
                print("当前配置:")
                print(json.dumps(self.config, indent=2, ensure_ascii=False))
                self.save_config()
            
            elif choice == "8":
                print("退出程序")
                break
            
            else:
                print("无效的选择")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="strongSwan连接管理器")
    parser.add_argument("--config", "-c", default="vpn_config.json", help="配置文件路径")
    parser.add_argument("--action", "-a", choices=["start", "stop", "restart", "status", "monitor", "interactive"], 
                       help="执行的操作")
    parser.add_argument("--connection", "-n", help="连接名称")
    parser.add_argument("--duration", "-d", type=int, default=60, help="监控时长(秒)")
    
    args = parser.parse_args()
    
    # 创建连接管理器
    connector = StrongSwanConnector(args.config)
    
    # 检查strongSwan是否安装
    if not connector.check_strongswan_installed():
        print("错误: 未检测到strongSwan，请确保已正确安装")
        sys.exit(1)
    
    # 执行操作
    if args.action == "interactive" or not args.action:
        connector.interactive_mode()
    elif args.action == "start":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        if args.connection in connector.config.get("connections", {}):
            config = connector.config["connections"][args.connection]
            if connector.setup_connection(args.connection, config):
                connector.start_connection(args.connection)
        else:
            print(f"错误: 连接 {args.connection} 不存在")
    elif args.action == "stop":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        connector.stop_connection(args.connection)
    elif args.action == "restart":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        connector.restart_connection(args.connection)
    elif args.action == "status":
        status = connector.get_connection_status(args.connection)
        print(json.dumps(status, indent=2, ensure_ascii=False))
    elif args.action == "monitor":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        connector.monitor_connection(args.connection, args.duration)


if __name__ == "__main__":
    main() 