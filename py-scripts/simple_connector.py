#!/usr/bin/env python3
"""
简化版strongSwan连接管理器
专门用于控制已配置的swanctl连接
"""

import subprocess
import json
import time
import sys
import os
import argparse
from typing import Dict, List


class SimpleSwanConnector:
    """简化版strongSwan连接管理器"""
    
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
                return {}
    
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
    
    def check_swanctl_installed(self) -> bool:
        """检查swanctl是否已安装"""
        try:
            result = subprocess.run(['which', 'swanctl'], capture_output=True, text=True)
            return result.returncode == 0
        except Exception:
            return False
    
    def check_connection_config(self, connection_name: str) -> bool:
        """检查连接配置是否存在"""
        try:
            swanctl_conf = self.config.get("settings", {}).get("swanctl_conf", "/etc/swanctl/swanctl.conf")
            if os.path.exists(swanctl_conf):
                with open(swanctl_conf, 'r') as f:
                    content = f.read()
                    if connection_name in content:
                        print(f"✓ 连接 {connection_name} 配置已存在")
                        return True
                    else:
                        print(f"✗ 连接 {connection_name} 在配置中未找到")
                        return False
            else:
                print(f"✗ 配置文件 {swanctl_conf} 不存在")
                return False
        except Exception as e:
            print(f"检查配置失败: {e}")
            return False
    
    def get_connection_status(self, connection_name: str = None) -> Dict:
        """获取连接状态"""
        try:
            result = self.run_command(['swanctl', '--list-sas'])
            status_text = result.stdout
            
            status = {
                "connections": [],
                "active": False,
                "details": status_text
            }
            
            if connection_name:
                if connection_name in status_text:
                    status["active"] = True
                    status["connection_name"] = connection_name
            
            return status
        except Exception as e:
            return {"error": str(e), "active": False}
    
    def start_connection(self, connection_name: str) -> bool:
        """启动连接"""
        try:
            print(f"正在启动连接 {connection_name}...")
            
            # 检查配置是否存在
            if not self.check_connection_config(connection_name):
                return False
            
            # 加载所有配置
            self.run_command(['swanctl', '--load-all'])
            
            # 启动连接
            self.run_command(['swanctl', '--initiate', '--child', connection_name])
            
            # 等待连接建立
            time.sleep(3)
            
            # 检查连接状态
            status = self.get_connection_status(connection_name)
            if status.get("active", False):
                print(f"✓ 连接 {connection_name} 已成功建立")
                return True
            else:
                print(f"✗ 连接 {connection_name} 建立失败")
                return False
                
        except Exception as e:
            print(f"启动连接失败: {e}")
            return False
    
    def stop_connection(self, connection_name: str) -> bool:
        """停止连接"""
        try:
            print(f"正在停止连接 {connection_name}...")
            self.run_command(['swanctl', '--terminate', '--child', connection_name])
            print(f"✓ 连接 {connection_name} 已停止")
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
    
    def show_connection_info(self, connection_name: str):
        """显示连接信息"""
        connections = self.config.get("connections", {})
        if connection_name in connections:
            conn_info = connections[connection_name]
            print(f"\n连接信息: {connection_name}")
            print(f"  远程主机: {conn_info.get('remote_host', 'N/A')}")
            print(f"  描述: {conn_info.get('description', 'N/A')}")
            print(f"  类型: {conn_info.get('type', 'N/A')}")
            
            # 检查配置状态
            self.check_connection_config(connection_name)
            
            # 检查连接状态
            status = self.get_connection_status(connection_name)
            print(f"  当前状态: {'活跃' if status.get('active') else '断开'}")
        else:
            print(f"连接 {connection_name} 不存在")
    
    def monitor_connection(self, connection_name: str, duration: int = 60):
        """监控连接状态"""
        print(f"开始监控连接 {connection_name}，持续 {duration} 秒...")
        start_time = time.time()
        
        while time.time() - start_time < duration:
            status = self.get_connection_status(connection_name)
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            
            if status.get("active", False):
                print(f"[{timestamp}] ✓ 连接 {connection_name} 状态: 正常")
            else:
                print(f"[{timestamp}] ✗ 连接 {connection_name} 状态: 断开")
            
            time.sleep(self.config.get("settings", {}).get("check_interval", 5))
    
    def interactive_mode(self):
        """交互模式"""
        print("=== 简化版strongSwan连接管理器 ===")
        
        while True:
            print("\n可用操作:")
            print("1. 列出连接")
            print("2. 显示连接信息")
            print("3. 启动连接")
            print("4. 停止连接")
            print("5. 重启连接")
            print("6. 查看状态")
            print("7. 监控连接")
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
                        self.show_connection_info(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "3":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        self.start_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "4":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        self.stop_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "5":
                connections = self.list_connections()
                if connections:
                    conn_name = input(f"选择连接 ({', '.join(connections)}): ").strip()
                    if conn_name in connections:
                        self.restart_connection(conn_name)
                    else:
                        print("无效的连接名称")
                else:
                    print("没有配置的连接")
            
            elif choice == "6":
                status = self.get_connection_status()
                print("连接状态:")
                print(status.get("details", "无法获取状态"))
            
            elif choice == "7":
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
            
            elif choice == "8":
                print("退出程序")
                break
            
            else:
                print("无效的选择")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="简化版strongSwan连接管理器")
    parser.add_argument("--config", "-c", default="vpn_config.json", help="配置文件路径")
    parser.add_argument("--action", "-a", choices=["start", "stop", "restart", "status", "monitor", "info", "interactive"], 
                       help="执行的操作")
    parser.add_argument("--connection", "-n", help="连接名称")
    parser.add_argument("--duration", "-d", type=int, default=60, help="监控时长(秒)")
    
    args = parser.parse_args()
    
    # 创建连接管理器
    connector = SimpleSwanConnector(args.config)
    
    # 检查swanctl是否安装
    if not connector.check_swanctl_installed():
        print("错误: 未检测到swanctl，请确保strongSwan已正确安装")
        sys.exit(1)
    
    # 执行操作
    if args.action == "interactive" or not args.action:
        connector.interactive_mode()
    elif args.action == "start":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        connector.start_connection(args.connection)
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
    elif args.action == "info":
        if not args.connection:
            print("错误: 需要指定连接名称")
            sys.exit(1)
        connector.show_connection_info(args.connection)


if __name__ == "__main__":
    main() 