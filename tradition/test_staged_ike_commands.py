#!/usr/bin/env python3
"""
测试分阶段IKE命令
验证新添加的ikeinit、ikeinter、ikeauth命令
"""

import subprocess
import time
import sys

class StagedIkeTester:
    """分阶段IKE测试器"""
    
    def __init__(self):
        self.connection_name = "net-net"
    
    def run_command(self, command: str, timeout: int = 30) -> tuple:
        """运行命令并返回结果"""
        try:
            result = subprocess.run(command, shell=True, capture_output=True, 
                                  text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "Command timeout"
        except Exception as e:
            return -1, "", f"Error: {e}"
    
    def test_ikeinit(self):
        """测试IKE_SA_INIT阶段"""
        print("=== 测试 IKE_SA_INIT 阶段 ===")
        command = f"sudo swanctl --ikeinit --ike {self.connection_name}"
        print(f"执行命令: {command}")
        
        returncode, stdout, stderr = self.run_command(command, timeout=35)
        
        print(f"返回码: {returncode}")
        print(f"标准输出: {stdout}")
        if stderr:
            print(f"错误输出: {stderr}")
        
        if returncode == 0:
            print("✅ IKE_SA_INIT 成功")
            return True
        else:
            print("❌ IKE_SA_INIT 失败")
            return False
    
    def test_ikeinter(self):
        """测试IKE_INTERMEDIATE阶段"""
        print("\n=== 测试 IKE_INTERMEDIATE 阶段 ===")
        command = f"sudo swanctl --ikeinter --ike {self.connection_name}"
        print(f"执行命令: {command}")
        
        returncode, stdout, stderr = self.run_command(command, timeout=35)
        
        print(f"返回码: {returncode}")
        print(f"标准输出: {stdout}")
        if stderr:
            print(f"错误输出: {stderr}")
        
        if returncode == 0:
            print("✅ IKE_INTERMEDIATE 成功")
            return True
        else:
            print("❌ IKE_INTERMEDIATE 失败")
            return False
    
    def test_ikeauth(self):
        """测试IKE_AUTH阶段"""
        print("\n=== 测试 IKE_AUTH 阶段 ===")
        command = f"sudo swanctl --ikeauth --ike {self.connection_name}"
        print(f"执行命令: {command}")
        
        returncode, stdout, stderr = self.run_command(command, timeout=35)
        
        print(f"返回码: {returncode}")
        print(f"标准输出: {stdout}")
        if stderr:
            print(f"错误输出: {stderr}")
        
        if returncode == 0:
            print("✅ IKE_AUTH 成功")
            return True
        else:
            print("❌ IKE_AUTH 失败")
            return False
    
    def test_full_connection(self):
        """测试完整连接"""
        print("\n=== 测试完整连接 ===")
        command = f"sudo swanctl --initiate --ike {self.connection_name}"
        print(f"执行命令: {command}")
        
        returncode, stdout, stderr = self.run_command(command, timeout=35)
        
        print(f"返回码: {returncode}")
        print(f"标准输出: {stdout}")
        if stderr:
            print(f"错误输出: {stderr}")
        
        if returncode == 0:
            print("✅ 完整连接成功")
            return True
        else:
            print("❌ 完整连接失败")
            return False
    
    def cleanup(self):
        """清理连接"""
        print("\n=== 清理连接 ===")
        command = f"sudo swanctl --terminate --ike {self.connection_name}"
        print(f"执行命令: {command}")
        
        returncode, stdout, stderr = self.run_command(command, timeout=10)
        
        print(f"返回码: {returncode}")
        if returncode == 0:
            print("✅ 连接清理成功")
        else:
            print("⚠️  连接清理失败或连接不存在")
    
    def run_staged_test(self):
        """运行分阶段测试"""
        print("=== 分阶段IKE命令测试 ===")
        print(f"连接名称: {self.connection_name}")
        print(f"开始时间: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        
        # 首先清理可能存在的连接
        self.cleanup()
        time.sleep(2)
        
        # 测试各个阶段
        results = {}
        
        # 测试IKE_SA_INIT
        results['ikeinit'] = self.test_ikeinit()
        time.sleep(2)
        
        # 测试IKE_INTERMEDIATE
        results['ikeinter'] = self.test_ikeinter()
        time.sleep(2)
        
        # 测试IKE_AUTH
        results['ikeauth'] = self.test_ikeauth()
        time.sleep(2)
        
        # 测试完整连接
        results['full'] = self.test_full_connection()
        
        # 清理
        self.cleanup()
        
        # 输出结果
        print(f"\n=== 测试结果汇总 ===")
        for stage, success in results.items():
            status = "✅ 成功" if success else "❌ 失败"
            print(f"{stage:>10}: {status}")
        
        success_count = sum(results.values())
        total_count = len(results)
        print(f"\n成功率: {success_count}/{total_count} ({success_count/total_count*100:.1f}%)")
        
        return results

def main():
    """主函数"""
    tester = StagedIkeTester()
    
    try:
        results = tester.run_staged_test()
        
        # 根据结果给出建议
        if all(results.values()):
            print("\n🎉 所有测试都通过了！分阶段IKE命令工作正常。")
        elif results.get('full', False) and not any([results.get('ikeinit', False), 
                                                   results.get('ikeinter', False), 
                                                   results.get('ikeauth', False)]):
            print("\n⚠️  完整连接成功，但分阶段命令失败。")
            print("这可能是因为分阶段命令需要特殊的实现支持。")
        else:
            print("\n❌ 部分测试失败。请检查strongSwan配置和网络连接。")
        
    except KeyboardInterrupt:
        print("\n\n⚠️  测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试过程中发生错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main() 