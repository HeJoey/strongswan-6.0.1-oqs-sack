# Python基础学习指南

## 🎯 学习目标
通过实现strongSwan连接管理脚本，学习Python编程基础。

## 📚 Python基础概念

### 1. 类和对象 (Class & Object)

#### 什么是类？
类就像一个模板，定义了对象的属性和方法。

```python
class SimpleVPNConnector:
    """这是一个类，用来管理VPN连接"""
    
    def __init__(self, config_file):
        """这是构造函数，创建对象时自动调用"""
        self.config_file = config_file  # 这是对象的属性
        self.config = self.load_config()
    
    def load_config(self):
        """这是类的方法，用来加载配置"""
        pass
```

#### 如何使用类？
```python
# 创建对象
connector = SimpleVPNConnector("config.json")

# 调用对象的方法
connector.load_config()
connector.start_connection("host-host")
```

### 2. 文件操作 (File Operations)

#### 读取文件
```python
# 检查文件是否存在
if os.path.exists("config.json"):
    # 打开并读取文件
    with open("config.json", "r", encoding="utf-8") as f:
        content = f.read()  # 读取所有内容
        data = json.load(f)  # 解析JSON内容
```

#### 写入文件
```python
# 写入文件
with open("output.txt", "w") as f:
    f.write("Hello World")
```

### 3. JSON数据处理

#### 什么是JSON？
JSON是一种数据格式，类似于Python的字典。

```python
# JSON字符串
json_string = '{"name": "host-host", "ip": "192.168.1.1"}'

# 解析JSON
import json
data = json.loads(json_string)
print(data["name"])  # 输出: host-host

# 从文件读取JSON
with open("config.json", "r") as f:
    config = json.load(f)
```

### 4. 异常处理 (Exception Handling)

#### 为什么需要异常处理？
当程序遇到错误时，异常处理可以防止程序崩溃。

```python
try:
    # 可能出错的代码
    result = subprocess.run(["swanctl", "--list-sas"])
except subprocess.CalledProcessError as e:
    # 出错时的处理
    print(f"命令执行失败: {e}")
except Exception as e:
    # 其他错误的处理
    print(f"发生错误: {e}")
```

### 5. 系统命令调用 (Subprocess)

#### 执行系统命令
```python
import subprocess

# 执行简单命令
result = subprocess.run(["echo", "Hello"], capture_output=True, text=True)
print(result.stdout)  # 输出: Hello

# 执行复杂命令
result = subprocess.run(["swanctl", "--list-sas"], 
                       capture_output=True, text=True, check=True)
```

#### 参数说明
- `capture_output=True`: 捕获命令输出
- `text=True`: 输出为文本格式
- `check=True`: 命令失败时抛出异常

### 6. 字典操作 (Dictionary)

#### 创建和访问字典
```python
# 创建字典
config = {
    "connections": {
        "host-host": {"ip": "192.168.1.1"},
        "net-net": {"ip": "192.168.1.2"}
    }
}

# 访问字典
print(config["connections"]["host-host"]["ip"])  # 输出: 192.168.1.1

# 安全访问 (避免KeyError)
ip = config.get("connections", {}).get("host-host", {}).get("ip", "unknown")
```

#### 字典常用方法
```python
# 获取所有键
keys = config.keys()  # ['connections']

# 获取所有值
values = config.values()

# 检查键是否存在
if "connections" in config:
    print("存在connections键")
```

### 7. 列表操作 (List)

#### 创建和操作列表
```python
# 创建列表
connections = ["host-host", "net-net"]

# 添加元素
connections.append("new-connection")

# 检查元素是否存在
if "host-host" in connections:
    print("host-host存在")

# 列表推导式
connection_names = list(config["connections"].keys())
```

### 8. 字符串操作 (String)

#### 字符串格式化
```python
# f-string (推荐)
name = "host-host"
print(f"连接名称: {name}")

# format方法
print("连接名称: {}".format(name))

# %操作符
print("连接名称: %s" % name)
```

#### 字符串方法
```python
text = "  hello world  "
print(text.strip())      # 去除首尾空格
print(text.upper())      # 转大写
print(text.lower())      # 转小写
print(text.split())      # 分割字符串
```

### 9. 条件判断 (if-elif-else)

```python
# 简单判断
if connection_name in status_text:
    print("连接存在")
else:
    print("连接不存在")

# 多重判断
if result.returncode == 0:
    print("命令执行成功")
elif result.returncode == 1:
    print("命令执行失败")
else:
    print("未知错误")
```

### 10. 循环 (Loop)

#### for循环
```python
# 遍历列表
for connection in connections:
    print(f"连接: {connection}")

# 遍历字典
for name, config in connections.items():
    print(f"连接名: {name}, 配置: {config}")
```

#### while循环
```python
# 监控连接状态
start_time = time.time()
while time.time() - start_time < 60:  # 监控60秒
    status = get_connection_status()
    print(f"状态: {status}")
    time.sleep(5)  # 等待5秒
```

## 🛠️ 实用技巧

### 1. 调试技巧
```python
# 使用print调试
print(f"调试信息: {variable}")

# 使用assert断言
assert len(connections) > 0, "连接列表不能为空"
```

### 2. 代码组织
```python
# 函数应该做一件事
def load_config():
    """只负责加载配置"""
    pass

def save_config():
    """只负责保存配置"""
    pass
```

### 3. 命名规范
```python
# 变量和函数名使用小写字母和下划线
connection_name = "host-host"
def start_connection():
    pass

# 类名使用大驼峰命名
class SimpleVPNConnector:
    pass

# 常量使用大写字母
DEFAULT_CONFIG_FILE = "config.json"
```

## 📝 学习建议

### 1. 循序渐进
- 先理解基本概念
- 再实现简单功能
- 最后组合复杂功能

### 2. 多练习
- 修改现有代码
- 添加新功能
- 处理错误情况

### 3. 使用工具
- 使用print调试
- 阅读错误信息
- 查看Python文档

### 4. 实践项目
- 从简单开始
- 逐步增加复杂度
- 解决实际问题

## 🎯 下一步

1. **理解基础概念** - 阅读本指南
2. **实现简单功能** - 从load_config开始
3. **测试验证** - 使用test_handwrite.py
4. **逐步完善** - 添加更多功能
5. **实际应用** - 管理VPN连接

记住：编程是实践的艺术，多写代码，多调试，多思考！ 