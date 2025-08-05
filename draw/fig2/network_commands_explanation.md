# 网络设置命令详细说明

## 核心命令

### 1. 清除网络条件
```bash
# 清除所有qdisc设置
tc qdisc del dev ens33 root 2>/dev/null || true
tc qdisc del dev ens33 ingress 2>/dev/null || true
```

### 2. 设置突发丢包
```bash
# 基本语法
tc qdisc add dev <interface> root netem loss <rate>% <burst_size>

# 具体示例
tc qdisc add dev ens33 root netem loss 5% 3
```

## 命令参数详解

### tc qdisc add dev ens33 root netem loss 5% 3

#### 参数说明：
- **`tc`**: Traffic Control，Linux流量控制工具
- **`qdisc`**: Queueing Discipline，队列规则
- **`add`**: 添加规则
- **`dev ens33`**: 指定网络接口
- **`root`**: 根队列规则
- **`netem`**: Network Emulator，网络模拟器
- **`loss 5% 3`**: 丢包设置

#### 丢包参数：
- **`5%`**: 基础丢包率5%
- **`3`**: 突发大小，当丢包发生时可能连续丢失1-3个包

## 实际执行的命令

### 当运行 `sudo ./set_network_conditions.sh -l 5 -b 3` 时：

1. **清除现有设置**:
   ```bash
   tc qdisc del dev ens33 root 2>/dev/null || true
   tc qdisc del dev ens33 ingress 2>/dev/null || true
   ```

2. **设置新的丢包规则**:
   ```bash
   tc qdisc add dev ens33 root netem loss 5% 3
   ```

### 当运行 `sudo ./set_network_conditions.sh -l 10 -b 5` 时：

1. **清除现有设置**:
   ```bash
   tc qdisc del dev ens33 root 2>/dev/null || true
   tc qdisc del dev ens33 ingress 2>/dev/null || true
   ```

2. **设置新的丢包规则**:
   ```bash
   tc qdisc add dev ens33 root netem loss 10% 5
   ```

## 查看当前设置

### 查看所有qdisc规则：
```bash
tc qdisc show dev ens33
```

### 输出示例：
```
qdisc netem 8001: root refcnt 2 limit 1000 loss 5% 3%
```

### 解析输出：
- **`qdisc netem`**: 使用netem队列规则
- **`8001`**: qdisc的句柄ID
- **`root`**: 根队列规则
- **`refcnt 2`**: 引用计数
- **`limit 1000`**: 队列长度限制
- **`loss 5% 3%`**: 丢包设置（5%基础丢包率，3%突发丢包）

## 不同配置的命令对比

### 配置1: 5%丢包率，突发大小1
```bash
tc qdisc add dev ens33 root netem loss 5% 1
```
- **效果**: 相对稳定的5%丢包率
- **实际丢包**: 4-6%之间

### 配置2: 5%丢包率，突发大小3 (默认)
```bash
tc qdisc add dev ens33 root netem loss 5% 3
```
- **效果**: 2-8%丢包率波动
- **实际丢包**: 有突发丢包现象

### 配置3: 5%丢包率，突发大小5
```bash
tc qdisc add dev ens33 root netem loss 5% 5
```
- **效果**: 1-10%丢包率波动
- **实际丢包**: 突发丢包更严重

## 清除设置

### 清除所有网络条件：
```bash
tc qdisc del dev ens33 root
```

### 脚本中的清除命令：
```bash
tc qdisc del dev ens33 root 2>/dev/null || true
tc qdisc del dev ens33 ingress 2>/dev/null || true
```

## 其他netem参数

### 延迟设置：
```bash
# 设置50ms延迟
tc qdisc add dev ens33 root netem delay 50ms

# 设置延迟和丢包
tc qdisc add dev ens33 root netem delay 50ms loss 5% 3
```

### 带宽限制：
```bash
# 限制带宽为1Mbps
tc qdisc add dev ens33 root tbf rate 1mbit burst 32kbit latency 400ms
```

### 包损坏：
```bash
# 设置2%的包损坏率
tc qdisc add dev ens33 root netem corrupt 2%
```

### 包重复：
```bash
# 设置1%的包重复率
tc qdisc add dev ens33 root netem duplicate 1%
```

## 验证设置

### 检查设置是否生效：
```bash
# 查看qdisc规则
tc qdisc show dev ens33

# 查看统计信息
tc -s qdisc show dev ens33
```

### 测试丢包效果：
```bash
# 使用ping测试丢包
ping -c 100 192.168.31.136

# 使用iperf测试
iperf3 -c 192.168.31.136 -t 30
```

## 注意事项

1. **权限要求**: 需要root权限执行tc命令
2. **接口名称**: 确保使用正确的网络接口名称
3. **参数范围**: 丢包率0-100%，突发大小必须为正整数
4. **清除设置**: 测试完成后及时清除网络条件
5. **两端设置**: 确保测试两端设置相同的网络条件 