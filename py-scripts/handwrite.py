#!/usr/bin/env python3
"""
最小化strongSwan连接管理模块
用于学习Python编程和strongSwan连接管理
"""

import subprocess
import json
import time
import sys
import os
import argparse

class SimpleVPNConnector:
    """最小化VPN连接管理器"""
    
    def __init__(self, config_file: str = "vpn_config.json"):
        """初始化连接管理器"""
        print(f"{config_file}")
        self.config_file = config_file
        self.config = self.load_config()
        # 添加连接记录字典
        self.record_json_path = "connection_records.json"
        self.connection_records = []  # 存储连接记录信息（数组格式）
        self.load_connection_records()  # 加载历史记录
    
    def load_config(self):
        """加载配置文件 - 待实现"""
        # TODO: 实现配置文件加载逻辑
        # 1. 检查配置文件是否存在 (使用 os.path.exists())
        # 2. 如果存在，读取JSON文件内容 (使用 open() 和 json.load())
        # 3. 如果文件不存在或格式错误，返回默认配置
        # 4. 返回配置字典
        if os.path.exists(self.config_file):
            # print(f"file {self.config_file} exist!")
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    config = json.load(f)
                    print(f"json success!")
                    return config
            except json.JSONDecodeError as e:
                print(f"json format error : {e}")
                return self.get_default_config()
                
        else:
            print(f"配置文件 {self.config_file} 不存在，使用默认配置")
            return self.get_default_config()
    
    def get_default_config(self):
        """获取默认配置"""
        return {
            "connections": {
                "host-host": {
                    "remote_host": "192.168.230.24",
                    "description": "主机到主机连接"
                },
                "net-net": {
                    "remote_host": "192.168.31.18",
                    "description": "网络到网络连接"
                }
            }
        }

    
    def run_command(self, command):
        """执行系统命令 - 待实现"""
        # TODO: 实现命令执行逻辑
        # 1. 使用 subprocess.run() 执行命令
        # 2. 捕获输出 (capture_output=True, text=True)
        # 3. 检查执行结果 (check=True)
        # 4. 如果执行失败，打印错误信息并抛出异常
        # 5. 返回执行结果
        run_cmd = ' '.join(command)
        print(f"{run_cmd}")
        try:
            res = subprocess.run(command, capture_output=True, text=True, check=True)
            return res 
        except subprocess.CalledProcessError as e:
            print(f"命令执行失败: {' '.join(command)}")
            print(f"错误信息: {e.stderr if e.stderr else e}")

    def check_swanctl_installed(self):
        """检查swanctl是否安装 - 待实现"""
        # TODO: 实现安装检查逻辑
        # 1. 使用 subprocess.run() 执行 'which swanctl' 命令
        # 2. 检查命令的返回码 (returncode)
        # 3. 如果返回码为0，表示已安装，返回True
        # 4. 如果返回码不为0或发生异常，返回False
        try:
            res = subprocess.run(['which', 'swanctl'])
            return res.returncode == 0
        except Exception:
            return False

    def get_connection_status(self, connection_name=None):
        """获取连接状态 - 待实现"""
        # TODO: 实现状态检查逻辑
        # 1. 使用 run_command() 执行 'swanctl --list-sas' 命令
        # 2. 获取命令输出内容
        # 3. 创建状态字典，包含 'active' 和 'details' 字段
        # 4. 如果指定了连接名称，检查输出中是否包含该名称
        # 5. 如果包含，设置 'active' 为True，否则为False
        # 6. 返回状态字典
        try:
            res = self.run_command(['sudo', 'swanctl', '--list-sas'])
            status_text = res.stdout
            # print(f"res : {res.args}")
            # print(f"text : {status_text}")
            lines = status_text.split('\n')
            if len(lines) > 4:

                # for i in range(len(lines)):
                #     print(f"lines {i} : {lines[i]}")
                
                # handle first line
                lines0 = lines[0]
                if ':' in lines0:
                    conns_name = lines0.split(':')[0]

                    detail_part = lines0.split(':')[1]
                    # print(f"{conns_name}, {detail_part}")

                    detail_parts = detail_part.split(',')
                    detail_parts_remove_space = [elem.strip() for elem in detail_parts]
                    
                    # print(f"{detail_parts}")
                    # print(f"{detail_parts_remove_space}")
                proposals = [elem.strip() for elem in lines[3].split('/')]
                # print(f"{proposals}")

                status = {
                    "connections"   : conns_name,
                    "established"   : True if detail_parts_remove_space[1] == "ESTABLISHED" else False,
                    "proposals"     : proposals,
                    "details"       : status_text
                }
            else:
                status = {
                    "connections"   : "",
                    "established"   : False,
                    "proposals"     : "",
                    "details"       : ""
                }
            print(f"{status}")
            return status
        except Exception as e:
            print(f"{e}")
        
    
    def start_connection(self, connection_name):
        """启动连接 - 待实现"""
        # TODO: 实现连接启动逻辑
        # 1. 打印启动信息
        # 2. 使用 run_command() 执行 'swanctl --load-all' 加载配置
        # 3. 使用 run_command() 执行 'swanctl --initiate --child 连接名' 启动连接
        # 4. 等待3秒让连接建立 (使用 time.sleep(3))
        # 5. 使用 get_connection_status() 检查连接状态
        # 6. 如果状态为活跃，打印成功信息并返回True
        # 7. 如果状态不活跃，打印失败信息并返回False
        try:
            print(f"Starting connections {connection_name}....\n")
            self.run_command(['sudo', 'swanctl', '--load-all'])
            self.run_command(['sudo', 'swanctl', '--initiate', '--ike', connection_name])

            time.sleep(3)
            res = self.get_connection_status()

            if res['established']:
                print(f"\nSuccess! {res}")
                # 添加统计记录
                self.record_connection_start(connection_name)
                return True
            else:
                print(f"\nFailure! {res}")
                return False

        except Exception as e:
            print(f"Exception : {e}")
    
    def stop_connection(self, connection_name):
        """停止连接 - 待实现"""
        # TODO: 实现连接停止逻辑
        # 1. 打印停止信息
        # 2. 使用 run_command() 执行 'swanctl --terminate --child 连接名' 停止连接
        # 3. 记录连接结束时间
        # 4. 打印成功信息
        # 5. 返回True表示成功
        try:
            print(f"Stoping connections {connection_name}....\n")
            # self.run_command(['sudo', 'swanctl', '--load-all'])
            self.run_command(['sudo', 'swanctl', '--terminate', '--ike', connection_name])
            # print(self.get_connection_status())
            print(f"连接 {connection_name} 已停止")
            # 记录连接结束时间
            self.record_connection_end(connection_name)
            return True
        
        except Exception as e:
            print(f"停止连接失败: {e}")
            return False
    
    def list_connections(self):
        """列出所有连接 - 待实现"""
        # TODO: 实现连接列表逻辑
        # 1. 从 self.config 中获取 'connections' 字典
        # 2. 使用 dict.keys() 获取所有连接名称
        # 3. 使用 list() 转换为列表
        # 4. 返回连接名称列表
        conn_dict = self.config['connections']
        # print(f"{conn_dict}")
        keyView = conn_dict.keys()
        # print(f"{keyView}")
        print(f"conn_list: {list(keyView)}")
        return [key for key in conn_dict.keys()]
        # return list()
# ==================== 连接记录功能（用于作图分析） ====================

    def load_connection_records(self):
        """加载连接记录数据 - 待实现"""
        # TODO: 实现连接记录加载逻辑
        # 1. 检查记录文件是否存在 (connection_records.json)
        # 2. 如果存在，读取JSON文件内容
        # 3. 如果不存在，创建空的记录数组
        # 4. 更新 self.connection_records
        if os.path.exists(self.record_json_path):
            try:
                with open(self.record_json_path, 'r', encoding='utf-8') as f:
                    self.connection_records = json.load(f)
                    print(f"连接记录加载成功，共 {len(self.connection_records)} 条记录")
            except json.JSONDecodeError as e:
                print(f"JSON格式错误: {e}")
                self.connection_records = []
        else:
            print(f"记录文件不存在，创建新的记录数组")
            self.connection_records = []


    def save_connection_records(self):
        """保存连接记录数据 - 待实现"""
        # TODO: 实现连接记录保存逻辑
        # 1. 将 self.connection_records 转换为JSON
        # 2. 写入到 connection_records.json 文件
        # 3. 处理写入错误
        try:
            with open(self.record_json_path, 'w', encoding='utf-8') as f:
                json.dump(self.connection_records, f, indent=2, ensure_ascii=False)
            print(f"连接记录保存成功，共 {len(self.connection_records)} 条记录")
        except Exception as e:
            print(f"保存记录失败: {e}")




    def record_connection_start(self, connection_name):
        """记录连接开始时间（毫秒精度）- 待实现"""
        # TODO: 实现连接开始记录逻辑
        # 1. 获取当前时间戳（毫秒精度）
        # 2. 生成唯一的会话ID（建议格式：connection_name_timestamp）
        # 3. 创建新的连接记录条目（包含session_id, event_type, timestamp, connection_name, datetime）
        # 4. 确保 self.connection_records 字典存在
        # 5. 确保该连接的记录列表存在
        # 6. 添加记录到列表
        # 7. 保存记录数据
        # 8. 返回会话ID
        ts = int(time.time() * 1000)
        id = '_'.join([connection_name,str(ts)])
        self.connection_records = {
                "session_id": id,
                "start_timestamp_ms": ts,
                "end_timestamp_ms": None,
                "duration_ms": None,
                "status": "completed",
                "connection_name": connection_name
        }
        return id


    def record_connection_end(self):
        """记录连接结束时间（毫秒精度）- 待实现"""
        # TODO: 实现连接结束记录逻辑
        # 1. 获取当前时间戳（毫秒精度）
        # 2. 查找对应的开始记录（通过连接名和最近的开始记录）
        # 3. 计算连接持续时间（毫秒）
        # 4. 创建结束记录条目（包含session_id, event_type, timestamp, duration, connection_name, datetime）
        # 5. 添加记录到列表
        # 6. 保存记录数据
        # 7. 返回持续时间
        ts = int(time.time() * 1000)
        self.connection_records = {
                "end_timestamp_ms": ts,
                "duration_ms": ts - self.connection_records["start_timestamp_ms"],
        }
        return 


    def get_connection_records(self, connection_name=None):
        """获取连接记录数据（用于作图）- 待实现"""
        # TODO: 实现连接记录获取逻辑
        # 1. 加载连接记录数据
        # 2. 如果指定了 connection_name，过滤该连接的记录
        # 3. 如果没有指定，返回所有连接的记录
        # 4. 返回格式化的记录数据（时间戳、持续时间、连接状态等）
        # 5. 按时间戳排序
        pass


    def export_records_for_plotting(self, connection_name=None, filename=None):
        """导出连接记录用于作图分析 - 待实现"""
        # TODO: 实现记录导出逻辑
        # 1. 获取连接记录数据
        # 2. 转换为适合作图的格式（CSV或JSON）
        # 3. 如果未指定文件名，自动生成（格式：connection_records_YYYYMMDD_HHMMSS.csv）
        # 4. 包含时间戳、持续时间、连接状态等信息
        # 5. 保存到指定文件
        pass

    def analyze_connection_performance(self, connection_name=None):
        """分析连接性能统计 - 待实现"""
        # TODO: 实现性能分析逻辑
        # 1. 获取连接记录数据
        # 2. 计算平均连接时间、成功率等统计信息
        # 3. 计算最长/最短连接时间
        # 4. 计算连接次数统计
        # 5. 返回分析结果字典
        pass

    def get_recent_connection_start(self, connection_name):
        """获取最近的连接开始记录 - 待实现"""
        # TODO: 实现最近开始记录获取逻辑
        # 1. 加载连接记录数据
        # 2. 查找指定连接的最新开始记录
        # 3. 返回开始记录或None
        pass

    def format_duration_ms(self, milliseconds):
        """格式化毫秒时长显示 - 待实现"""
        # TODO: 实现毫秒时长格式化逻辑
        # 1. 将毫秒转换为秒、分钟、小时等
        # 2. 处理不同时长范围
        # 3. 返回格式化的时长字符串
        pass


    def get_timestamp_ms(self):
        """获取当前时间戳（毫秒精度）- 待实现"""
        # TODO: 实现毫秒级时间戳获取逻辑
        # 1. 使用 time.time() 获取秒级时间戳
        # 2. 转换为毫秒精度
        # 3. 返回毫秒级时间戳
        return int(1000 * time.time())

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
        
def test_swanctl_installed():
    connector = SimpleVPNConnector()
    print(f"{connector.check_swanctl_installed()}")

def test_list_connections():
    connector = SimpleVPNConnector()
    print(f"{connector.list_connections()}")
    
def test_run_command(cmd):
    connector = SimpleVPNConnector()
    res = connector.run_command(cmd)
    print(f"stdout: {res.stdout}")
    print(f"res: {res}")

def test_get_connection_status():
    connector = SimpleVPNConnector()
    res = connector.get_connection_status()
    print(f"res: {res}")

def test_start_connection():
    connector = SimpleVPNConnector()
    # connector.start_connection("net-net")
    # connector.stop_connection("net-net")
    print(f"{connector.record_connection_start('net-net')}")
    print(f"{connector.connection_records}")
    time.sleep(2)
    connector.record_connection_end()
    print(f"{connector.connection_records}")
    print(f"加载前记录: {connector.connection_records}")
    
    # 添加测试记录
    test_record = {
        "session_id": "sess_000",
        "start_timestamp_ms": 1705123456789,
        "end_timestamp_ms": 1705123459789,
        "duration_ms": 3000,
        "status": "completed",
        "connection_name": "net-net"        
    }
    connector.connection_records.append(test_record)
    connector.save_connection_records()
    
    print(f"保存后记录: {connector.connection_records}")
    # return

def test_connection_recording():
    """测试连接记录功能"""
    print("=== 测试连接记录功能 ===")
    connector = SimpleVPNConnector()
    
    # 测试时间戳获取
    print("\n1. 测试时间戳获取:")
    timestamp = connector.get_timestamp_ms()
    print(f"当前时间戳: {timestamp}ms")
    
    # 测试记录开始
    print("\n2. 测试记录连接开始:")
    session_id = connector.record_connection_start("test-connection")
    print(f"会话ID: {session_id}")
    
    # 测试记录结束
    print("\n3. 测试记录连接结束:")
    duration = connector.record_connection_end("test-connection")
    print(f"连接持续时间: {duration}ms")
    
    # 测试获取记录
    print("\n4. 测试获取连接记录:")
    records = connector.get_connection_records("test-connection")
    print(f"记录数量: {len(records) if records else 0}")
    
    # 测试导出记录
    print("\n5. 测试导出记录:")
    connector.export_records_for_plotting("test-connection", "test_records.csv") 


def main():
    """主函数 - 待实现"""
    test_start_connection()
    # TODO: 实现主程序逻辑
    # 1. 打印程序标题
    # parser = argparse.ArgumentParser(description="简化版strongSwan连接管理器")
    # parser.add_argument("--config", "-c", default="vpn_config.json", help="配置文件路径")
    # parser.add_argument("--action", "-a", choices=["start", "stop", "restart", "status", "monitor", "info", "interactive"], 
    #                    help="执行的操作")
    # parser.add_argument("--connection", "-n", help="连接名称")
    # parser.add_argument("--duration", "-d", type=int, default=60, help="监控时长(秒)")
    # parser.parse_args()
    # # 2. 创建 SimpleVPNConnector 实例
    # connector = SimpleVPNConnector()
    # # 3. 检查 swanctl 是否安装
    # if not connector.check_swanctl_installed():
    #     print(f"You need to install swanctl!")
    #     sys.exit(1)
    # # 4. 获取并显示可用连接列表
    # list_conns = connector.list_connections()
    # # 5. 让用户选择连接和操作 (使用 input())
    # conn_name  = input("input conn_name : ")
    # while conn_name not in list_conns:
    #     print("input conn name error")
    #     conn_name  = input("input conn_name : ")
    # ops = ['start', 'stop', 'status', 'records', 'export', 'exit']
    # while True:
    # # 6. 根据用户选择执行相应操作 (start/stop/status)
    #     op = input("input op(start/stop/status/records/export/exit) :")
    #     while op not in ops:
    #         print("input error")
    #         op = input("input op(start/stop/status/records/export/exit) :")
    # # 7. 处理用户输入错误
    #     if op == 'start':
    #         connector.start_connection(conn_name)
    #     elif op == 'stop':
    #         connector.stop_connection(conn_name)
    #     elif op == 'status':
    #         connector.get_connection_status()
    #     elif op == 'records':
    #         # 新增：查看连接记录
    #         records = connector.get_connection_records(conn_name)
    #         print(f"连接 {conn_name} 的记录数量: {len(records) if records else 0}")
    #     elif op == 'export':
    #         # 新增：导出连接记录
    #         filename = f"connection_records_{conn_name}_{int(time.time())}.csv"
    #         connector.export_records_for_plotting(conn_name, filename)
    #         print(f"记录已导出到: {filename}")
    #     else:
    #         sys.exit()
    

    

# ==================== 连接记录功能（实时追加模式） ====================
# 实现顺序建议：
# 1. get_timestamp_ms() - 获取毫秒级时间戳
# 2. load_connection_records() - 加载记录数据
# 3. save_connection_records() - 保存记录数据
# 4. record_connection_start() - 记录连接开始
# 5. record_connection_end() - 记录连接结束
# 6. get_connection_records() - 获取记录数据
# 7. export_records_for_plotting() - 导出记录
# 8. analyze_connection_performance() - 性能分析
# 9. get_recent_connection_start() - 获取最近开始记录
# 10. format_duration_ms() - 格式化时长显示

# 注意：这些函数已经移动到类内部，请使用类中的方法


if __name__ == "__main__":
    main()
