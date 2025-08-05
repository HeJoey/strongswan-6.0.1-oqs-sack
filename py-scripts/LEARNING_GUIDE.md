# Python编程学习指南 - strongSwan连接管理

## 🎯 学习目标
通过逐步实现一个strongSwan连接管理脚本，学习Python编程基础和系统命令调用。

## 📋 学习步骤

### 第一步：配置文件加载功能

#### 目标
实现 `load_config()` 方法，能够读取JSON配置文件。

#### 学习要点
- JSON文件读取
- 异常处理
- 默认值设置

#### 实现代码
```python
def load_config(self):
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
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("配置加载测试:")
    print(f"配置文件: {connector.config_file}")
    print(f"配置内容: {connector.config}")
```

### 第二步：系统命令执行功能

#### 目标
实现 `run_command()` 方法，能够安全地执行系统命令。

#### 学习要点
- subprocess模块使用
- 命令执行错误处理
- 输出捕获

#### 实现代码
```python
def run_command(self, command, capture_output=True):
    """执行系统命令"""
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
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("命令执行测试:")
    try:
        result = connector.run_command(['echo', 'Hello World'])
        print(f"命令输出: {result.stdout}")
    except Exception as e:
        print(f"命令执行失败: {e}")
```

### 第三步：环境检查功能

#### 目标
实现 `check_swanctl_installed()` 方法，检查strongSwan是否安装。

#### 学习要点
- 系统命令检查
- 返回值处理

#### 实现代码
```python
def check_swanctl_installed(self):
    """检查swanctl是否安装"""
    try:
        result = subprocess.run(['which', 'swanctl'], capture_output=True, text=True)
        return result.returncode == 0
    except Exception:
        return False
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("环境检查测试:")
    if connector.check_swanctl_installed():
        print("✓ swanctl已安装")
    else:
        print("✗ swanctl未安装")
```

### 第四步：连接状态检查功能

#### 目标
实现 `get_connection_status()` 方法，检查VPN连接状态。

#### 学习要点
- 命令输出解析
- 状态判断逻辑

#### 实现代码
```python
def get_connection_status(self, connection_name=None):
    """获取连接状态"""
    try:
        result = self.run_command(['swanctl', '--list-sas'])
        status_text = result.stdout
        
        status = {
            "active": False,
            "details": status_text
        }
        
        if connection_name and connection_name in status_text:
            status["active"] = True
            status["connection_name"] = connection_name
        
        return status
    except Exception as e:
        return {"error": str(e), "active": False}
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("状态检查测试:")
    status = connector.get_connection_status("host-host")
    print(f"连接状态: {status}")
```

### 第五步：连接管理功能

#### 目标
实现 `start_connection()` 和 `stop_connection()` 方法。

#### 学习要点
- 连接启动流程
- 连接停止流程
- 状态验证

#### 实现代码
```python
def start_connection(self, connection_name):
    """启动连接"""
    try:
        print(f"正在启动连接 {connection_name}...")
        
        # 加载配置
        self.run_command(['swanctl', '--load-all'])
        
        # 启动连接
        self.run_command(['swanctl', '--initiate', '--child', connection_name])
        
        # 等待连接建立
        time.sleep(3)
        
        # 检查状态
        status = self.get_connection_status(connection_name)
        if status.get("active", False):
            print(f"✓ 连接 {connection_name} 启动成功")
            return True
        else:
            print(f"✗ 连接 {connection_name} 启动失败")
            return False
            
    except Exception as e:
        print(f"启动连接失败: {e}")
        return False

def stop_connection(self, connection_name):
    """停止连接"""
    try:
        print(f"正在停止连接 {connection_name}...")
        self.run_command(['swanctl', '--terminate', '--child', connection_name])
        print(f"✓ 连接 {connection_name} 已停止")
        return True
    except Exception as e:
        print(f"停止连接失败: {e}")
        return False
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("连接管理测试:")
    
    # 启动连接（需要sudo权限）
    # connector.start_connection("host-host")
    
    # 停止连接（需要sudo权限）
    # connector.stop_connection("host-host")
```

### 第六步：连接列表功能

#### 目标
实现 `list_connections()` 方法，列出所有可用连接。

#### 学习要点
- 字典操作
- 列表生成

#### 实现代码
```python
def list_connections(self):
    """列出所有连接"""
    return list(self.config.get("connections", {}).keys())
```

#### 测试方法
```python
# 在main()函数中添加测试代码
def main():
    connector = SimpleVPNConnector()
    print("连接列表测试:")
    connections = connector.list_connections()
    print(f"可用连接: {connections}")
```

### 第七步：主程序逻辑

#### 目标
实现 `main()` 函数，提供用户界面。

#### 学习要点
- 命令行参数处理
- 用户交互
- 程序流程控制

#### 实现代码
```python
def main():
    """主函数"""
    print("=== strongSwan连接管理器 ===")
    
    # 创建连接管理器
    connector = SimpleVPNConnector()
    
    # 检查环境
    if not connector.check_swanctl_installed():
        print("错误: swanctl未安装")
        return
    
    # 显示可用连接
    connections = connector.list_connections()
    print(f"可用连接: {connections}")
    
    # 简单交互
    if connections:
        choice = input(f"选择要操作的连接 ({', '.join(connections)}): ").strip()
        if choice in connections:
            action = input("选择操作 (start/stop/status): ").strip()
            
            if action == "start":
                connector.start_connection(choice)
            elif action == "stop":
                connector.stop_connection(choice)
            elif action == "status":
                status = connector.get_connection_status(choice)
                print(f"状态: {status}")
            else:
                print("无效的操作")
        else:
            print("无效的连接名称")
    else:
        print("没有可用的连接")
```

## 🧪 测试建议

### 1. 逐步测试
- 每实现一个功能就测试一次
- 使用print语句查看中间结果
- 确保每个步骤都正常工作

### 2. 错误处理
- 测试文件不存在的情况
- 测试命令执行失败的情况
- 测试权限不足的情况

### 3. 实际使用
- 在测试环境中运行
- 使用sudo权限测试连接管理功能
- 观察实际效果

## 📚 学习资源

### Python基础
- 类和对象
- 异常处理
- 文件操作
- 系统命令调用

### strongSwan相关
- swanctl命令使用
- 配置文件格式
- 连接状态检查

## 🎯 进阶目标

完成基础功能后，可以尝试：
1. 添加交互模式
2. 实现连接监控
3. 添加配置文件编辑
4. 实现日志记录
5. 添加更多错误处理

## 💡 提示

- 每次只实现一个功能
- 多使用print调试
- 注意权限问题
- 保持代码简洁
- 多测试各种情况 