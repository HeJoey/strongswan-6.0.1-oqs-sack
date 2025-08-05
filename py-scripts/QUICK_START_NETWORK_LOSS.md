# 网络丢包模拟器 - 快速开始

## 快速测试

### 1. 检查依赖
```bash
# 检查tc命令
tc --version

# 如果没有，安装iproute2
sudo apt-get install iproute2
```

### 2. 查看网络接口
```bash
# 查看可用接口
ip link show

# 或者查看默认路由接口
ip route get 8.8.8.8
```

### 3. 基本测试
```bash
# 设置5%丢包率
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0

# 测试网络连通性
sudo python3 network_loss_simulator.py --interface eth0 --test

# 清除设置
sudo python3 network_loss_simulator.py --interface eth0 --clear
```

### 4. 自动测试
```bash
# 运行完整测试
sudo python3 test_network_loss.py
```

## 与strongSwan结合测试

### 测试流程
```bash
# 1. 设置网络丢包
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0

# 2. 启动strongSwan连接
sudo swanctl --initiate --ike net-net

# 3. 观察日志中的重传统计
# 查看是否有 INTERMEDIATE_TRANSMISSION_STATS 输出

# 4. 清除网络设置
sudo python3 network_loss_simulator.py --interface eth0 --clear
```

### 不同丢包率测试
```bash
# 轻度丢包 (2%)
sudo python3 network_loss_simulator.py --interface eth0 --loss 2.0
sudo swanctl --initiate --ike net-net

# 中度丢包 (5%)
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
sudo swanctl --initiate --ike net-net

# 重度丢包 (10%)
sudo python3 network_loss_simulator.py --interface eth0 --loss 10.0
sudo swanctl --initiate --ike net-net
```

## 常用命令

### 查看状态
```bash
# 查看当前网络配置
sudo python3 network_loss_simulator.py --interface eth0 --status
```

### 保存配置
```bash
# 保存当前配置
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --save

# 加载保存的配置
sudo python3 network_loss_simulator.py --interface eth0 --load
```

### 高级设置
```bash
# 丢包率 + 延迟
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --delay 100

# 丢包率 + 延迟 + 抖动
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0 --delay 100 --jitter 20
```

## 故障排除

### 权限问题
```bash
# 确保使用sudo
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
```

### 接口不存在
```bash
# 查看可用接口
ip link show

# 使用正确的接口名称
sudo python3 network_loss_simulator.py --interface ens33 --loss 5.0
```

### 设置失败
```bash
# 先清除现有设置
sudo python3 network_loss_simulator.py --interface eth0 --clear

# 再重新设置
sudo python3 network_loss_simulator.py --interface eth0 --loss 5.0
```

## 注意事项

1. **需要sudo权限** - 设置网络参数需要管理员权限
2. **影响整个接口** - 设置会影响接口的所有流量
3. **测试环境使用** - 建议在测试环境中使用
4. **记得清除** - 测试完成后记得清除网络设置
5. **备份配置** - 重要配置建议先备份 