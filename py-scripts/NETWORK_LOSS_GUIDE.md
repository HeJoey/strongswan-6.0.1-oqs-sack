# 网络丢包率模拟器使用指南

## 概述

`network_loss_simulator.py` 是一个用于模拟网络丢包和延迟的工具，专门为测试strongSwan的选择性重传机制而设计。

## 安装依赖

确保系统已安装 `iproute2` 包：

```bash
# Ubuntu/Debian
sudo apt-get install iproute2

# CentOS/RHEL
sudo yum install iproute

# 检查tc命令是否可用
tc --version
```

## 基本用法

### 1. 设置网络丢包率

```bash
# 设置5%丢包率
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0

# 设置10%丢包率和50ms延迟
sudo python3 network_loss_simulator.py --interface eth0 --loss 10.0 --delay 50

# 设置丢包率、延迟和抖动
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --delay 100 --jitter 20
```

### 2. 查看当前状态

```bash
# 查看当前网络配置
sudo python3 network_loss_simulator.py --interface eth0 --status
```

### 3. 测试网络连通性

```bash
# 测试网络连通性
sudo python3 network_loss_simulator.py --interface eth0 --test
```

### 4. 清除网络设置

```bash
# 清除所有网络丢包设置
sudo python3 network_loss_simulator.py --interface eth0 --clear
```

### 5. 保存和加载配置

```bash
# 保存当前配置
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --save

# 加载保存的配置
sudo python3 network_loss_simulator.py --interface eth0 --load
```

## 参数说明

- `--interface, -i`: 网络接口名称（必需）
- `--loss, -l`: 丢包率百分比 (0.0-100.0)
- `--delay, -d`: 延迟毫秒数
- `--jitter, -j`: 抖动毫秒数
- `--clear, -c`: 清除网络丢包设置
- `--status, -s`: 显示当前网络状态
- `--test, -t`: 测试网络连通性
- `--save`: 保存当前配置
- `--load`: 加载保存的配置
- `--config-file`: 配置文件路径

## 测试场景示例

### 场景1: 轻度丢包测试
```bash
# 设置2%丢包率，测试基本重传机制
sudo python3 network_loss_simulator.py --interface eth0 --loss 2.0
sudo swanctl --initiate --ike net-net
```

### 场景2: 中度丢包测试
```bash
# 设置5%丢包率，测试选择性重传
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
sudo swanctl --initiate --ike net-net
```

### 场景3: 重度丢包测试
```bash
# 设置10%丢包率，测试极限情况
sudo python3 network_loss_simulator.py --interface eth0 --loss 10.0
sudo swanctl --initiate --ike net-net
```

### 场景4: 丢包+延迟测试
```bash
# 设置5%丢包率和100ms延迟
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --delay 100
sudo swanctl --initiate --ike net-net
```

## 注意事项

1. **需要sudo权限**: 设置网络参数需要管理员权限
2. **接口名称**: 使用 `ip link show` 查看正确的接口名称
3. **影响范围**: 设置会影响整个接口的所有流量
4. **测试环境**: 建议在测试环境中使用，避免影响生产网络
5. **清除设置**: 测试完成后记得清除网络设置

## 故障排除

### 1. tc命令不可用
```bash
# 安装iproute2
sudo apt-get install iproute2
```

### 2. 接口不存在
```bash
# 查看可用接口
ip link show
```

### 3. 权限不足
```bash
# 确保使用sudo运行
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
```

### 4. 设置失败
```bash
# 先清除现有设置
sudo python3 network_loss_simulator.py --interface eth0 --clear
# 再重新设置
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
```

## 与strongSwan测试结合

1. **设置网络丢包**
2. **启动strongSwan连接**
3. **观察日志输出**
4. **分析重传数据**
5. **清除网络设置**

```bash
# 完整测试流程
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
sudo swanctl --initiate --ike net-net
# 观察日志中的重传统计
sudo python3 network_loss_simulator.py --interface eth0 --clear
``` 