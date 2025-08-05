# 突发丢包率设置使用说明

## 概述

本目录提供了多种设置突发丢包率的方法，用于模拟真实网络环境下的IPsec连接测试。

## 脚本说明

### 1. set_realistic_network.sh (推荐)
**用途**: 使用netem状态模型设置真实网络条件
**特点**: 支持多种网络模型，更接近真实网络环境

**突发丢包设置**:
```bash
# 设置5%突发丢包率
sudo ./set_realistic_network.sh -l 5 -m burst

# 设置10%突发丢包率
sudo ./set_realistic_network.sh -l 10 -m burst

# 设置5%丢包率+10ms延迟
sudo ./set_realistic_network.sh -l 5 -d 10 -m burst

# 查看当前设置
sudo ./set_realistic_network.sh -s

# 清除网络条件
sudo ./set_realistic_network.sh -c
```

### 2. set_network_conditions.sh (基础版)
**用途**: 基础网络条件设置
**特点**: 简单易用，支持丢包和延迟

**突发丢包设置**:
```bash
# 设置5%丢包率，默认突发大小3
sudo ./set_network_conditions.sh -l 5

# 设置10%丢包率，突发大小5
sudo ./set_network_conditions.sh -l 10 -b 5

# 设置5ms延迟
sudo ./set_network_conditions.sh -d 5
```

### 3. test_burst_loss.sh (测试脚本)
**用途**: 自动测试不同突发丢包率的效果
**特点**: 自动收集数据，生成统计报告

**使用方法**:
```bash
# 测试默认丢包率 (0%, 5%, 10%, 15%, 20%)
sudo ./test_burst_loss.sh

# 测试指定丢包率
sudo ./test_burst_loss.sh -l '0 5 10' -t 30

# 指定输出文件
sudo ./test_burst_loss.sh -o my_test.csv
```

## 网络模型对比

### 突发丢包模型 (burst)
- **语法**: `tc qdisc add dev ens33 root netem loss 5% 2`
- **特点**: 简单的突发丢包，适合模拟网络拥塞
- **参数**: 丢包率 + 突发大小
- **适用**: 基础网络拥塞测试

### 马尔可夫链模型 (markov)
- **语法**: `tc qdisc add dev ens33 root netem loss 5% 25%`
- **特点**: 基于状态转换的丢包
- **参数**: 丢包率 + 相关性
- **适用**: 模拟网络状态变化

### Gilbert-Elliot模型 (gilbert)
- **语法**: `tc qdisc add dev ens33 root netem loss random 5% 30%`
- **特点**: 两状态马尔可夫链，模拟好/坏状态切换
- **参数**: 丢包率 + 相关性
- **适用**: 模拟网络质量波动

### 4状态模型 (4state)
- **语法**: `tc qdisc add dev ens33 root netem loss state 0.1 0.3 0.2 0.4 0.05`
- **特点**: 4状态马尔可夫链，最复杂的真实网络模拟
- **参数**: 5个状态转换概率
- **适用**: 复杂网络环境模拟

## 实际使用建议

### 对于IPsec性能测试：

1. **主要测试**: 使用Gilbert-Elliot模型
   ```bash
   sudo ./set_realistic_network.sh -l 5 -m gilbert
   ```

2. **对比测试**: 使用突发丢包模型
   ```bash
   sudo ./set_realistic_network.sh -l 5 -m burst
   ```

3. **复杂环境**: 使用4状态模型
   ```bash
   sudo ./set_realistic_network.sh -m 4state
   ```

### 测试流程：

1. **设置网络条件**:
   ```bash
   # 在两端分别设置相同的网络条件
   sudo ./set_realistic_network.sh -l 5 -m burst
   ```

2. **运行IPsec测试**:
   ```bash
   # 使用connection_test.sh收集数据
   sudo ./connection_test.sh -l "5" -n 50 -o test_5percent.csv
   ```

3. **重复测试**:
   - 对每个丢包率重复上述步骤
   - 建议测试: 0%, 5%, 10%, 15%, 20%

## 输出数据格式

### test_burst_loss.sh 输出:
```
# 突发丢包率测试结果
# 生成时间: Sat 20 Jul 05:36:23 +00 2025
# 目标IP: 192.168.31.136
# 格式: 丢包率(%),测试序号,发送包数,接收包数,丢包数,实际丢包率(%),平均延迟(ms)
0,1,10,10,0,0.00,0.018
0,2,10,10,0,0.00,0.026
5,1,10,9,1,10.00,0.045
5,2,10,8,2,20.00,0.052
```

### connection_test.sh 输出:
```
# 格式: 丢包率(%),测试序号,结果,HCT(ms),重传次数
0,1,SUCCESS,78.772796000,0
0,2,SUCCESS,94.772949000,0
5,1,SUCCESS,104.202326000,0
5,2,TIMEOUT,0,0
```

## 注意事项

1. **权限要求**: 所有脚本都需要root权限运行
2. **两端设置**: 必须在测试两端都设置相同的网络条件
3. **测试间隔**: 建议每个丢包率测试完成后稍作等待
4. **数据收集**: 及时保存测试数据，避免丢失
5. **网络接口**: 默认使用ens33，可通过参数修改

## 故障排除

### 常见问题：
1. **权限错误**: 使用sudo运行脚本
2. **接口不存在**: 检查网络接口名称
3. **设置失败**: 检查tc命令是否可用
4. **测试失败**: 确保两端网络连通性正常

### 调试命令：
```bash
# 查看当前网络条件
sudo ./set_realistic_network.sh -s

# 查看网络接口
ip link show

# 测试连通性
ping -c 3 192.168.31.136

# 查看tc规则
tc qdisc show dev ens33
``` 