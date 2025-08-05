# 传统分片机制性能测试工具

## 概述

这个工具用于测试strongSwan传统分片机制在不同网络丢包率下的性能表现。通过模拟1%-40%的丢包率，分析传统分片的重传行为和带宽效率。

## 文件说明

- `traditional_fragment_performance_test.py` - 主测试脚本（完整版）
- `run_test.py` - 简化启动器，提供交互式菜单
- `README.md` - 本说明文件

## 系统要求

### 必需组件
- Linux系统（支持tc命令）
- Python 3.6+
- strongSwan已安装并配置
- root权限（用于网络控制和服务重启）

### 依赖包
```bash
# 安装网络控制工具
sudo apt-get install iproute2

# 确保strongSwan运行
sudo systemctl start strongswan
sudo systemctl enable strongswan
```

## 使用方法

### 1. 快速开始
```bash
cd tradition/
sudo python3 run_test.py
```

### 2. 测试模式

#### 快速测试模式
- 测试丢包率: 0%, 5%, 10%, 20%
- 每个条件运行50次
- 运行时间: 约30分钟
- 适合验证功能和快速评估

#### 完整测试模式  
- 测试丢包率: 1%, 2%, 3%, 5%, 7%, 10%, 15%, 20%, 25%, 30%, 35%, 40%
- 每个条件运行500次
- 运行时间: 3-4小时
- 适合详细性能分析

### 3. 直接运行完整测试
```bash
sudo python3 traditional_fragment_performance_test.py
```

## 测试原理

### 测试流程
1. **网络设置**: 使用Linux tc命令设置指定的丢包率
2. **IKE连接**: 执行strongSwan IKE连接建立
3. **数据提取**: 从日志中提取传输统计数据
4. **重复测试**: 每个丢包率重复500次测试
5. **结果分析**: 统计平均值、中位数、标准差等

### 关键指标
- **total_transmitted**: 总传输数据量（字节）
- **retransmitted**: 重传次数
- **efficiency**: 传输效率 = 原始数据量 / 实际传输量 × 100%

### 理论模型
对于传统分片机制：
- 分片数量: N = 2
- 每片大小: D = 1200字节
- 丢包率: P
- 期望传输量: `(N × D) / (1-P)^N`

## 输出文件

### 详细结果文件
`traditional_fragment_detailed_[timestamp].json`
- 包含所有测试的原始数据
- 每个丢包率的理论计算
- 详细统计分析

### 汇总结果文件
`traditional_fragment_summary_[timestamp].json`
- 每个丢包率的汇总统计
- 平均传输量和效率
- 适合快速分析

## 示例输出

```
=== 最终统计报告 ===
丢包率     成功率     平均传输量      传输效率    理论值    
------------------------------------------------------------
    1%     98.0%      2450字节      98.0%      2449字节
    5%     95.2%      2535字节      94.7%      2526字节
   10%     90.4%      2667字节      90.0%      2963字节
   20%     78.6%      3058字节      78.5%      3750字节
   30%     65.2%      3686字节      65.1%      4898字节
```

## 网络接口配置

脚本会自动检测可用的网络接口，常见接口名：
- `eth0` - 传统以太网
- `enp0s3` - VirtualBox NAT
- `ens33` - VMware
- `wlan0` - 无线网络

如需手动指定接口，修改脚本中的：
```python
self.interface = "your_interface_name"
```

## 故障排除

### 常见问题

1. **权限错误**
   ```bash
   sudo python3 run_test.py
   ```

2. **tc命令未找到**
   ```bash
   sudo apt-get install iproute2
   ```

3. **strongSwan服务未运行**
   ```bash
   sudo systemctl start strongswan
   sudo systemctl status strongswan
   ```

4. **网络接口错误**
   - 检查可用接口: `ip link show`
   - 修改脚本中的接口名

### 调试选项

启用详细输出：
```bash
export DEBUG=1
sudo python3 run_test.py
```

## 注意事项

1. **测试期间网络影响**: 测试会影响本机网络连接
2. **时间要求**: 完整测试需要3-4小时，建议在维护窗口运行
3. **资源消耗**: 频繁重启服务可能消耗系统资源
4. **结果准确性**: 建议在稳定网络环境下测试

## 技术支持

如遇问题，请检查：
1. 系统日志: `journalctl -u strongswan`
2. strongSwan配置: `/etc/strongswan/`
3. 网络配置: `ip route show`

## 版本历史

- v1.0 - 初始版本，支持传统分片性能测试
- 测试环境：strongSwan 6.0.1 + Linux 6.8.0 