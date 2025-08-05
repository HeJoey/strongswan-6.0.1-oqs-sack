# strongSwan 分片重传网络测试脚本使用说明

## 概述

`fragment_retransmission_test.sh` 是一个专门用于测试strongSwan分片重传效果的自动化测试脚本。该脚本可以模拟各种网络条件（延迟、丢包），并测试IPsec连接在不同网络条件下的建立效果。

## 功能特性

- ✅ 自动设置网络条件（延迟、丢包率）
- ✅ 自动重启strongSwan服务
- ✅ 使用swanctl命令建立连接
- ✅ 统计每次连接建立时间
- ✅ 执行多次测试（默认100次）
- ✅ 生成详细的测试报告
- ✅ 实时显示测试进度

## 使用方法

### 基本用法

```bash
# 使用默认参数测试（无网络限制，100次测试）
sudo ./fragment_retransmission_test.sh <连接名称>

# 示例
sudo ./fragment_retransmission_test.sh site-to-site
```

### 高级用法

```bash
# 指定网络接口和网络条件
sudo ./fragment_retransmission_test.sh -i eth0 -d 100 -l 10 site-to-site

# 设置不同的测试次数
sudo ./fragment_retransmission_test.sh -d 200 -l 15 -n 50 site-to-site

# 只设置延迟，不设置丢包
sudo ./fragment_retransmission_test.sh -d 150 site-to-site

# 只设置丢包，不设置延迟
sudo ./fragment_retransmission_test.sh -l 20 site-to-site
```

### 参数说明

| 参数 | 长参数 | 说明 | 默认值 |
|------|--------|------|--------|
| `-i` | `--interface` | 指定网络接口 | 自动检测 |
| `-d` | `--delay` | 网络延迟（毫秒） | 0 |
| `-l` | `--loss` | 丢包率（百分比） | 0 |
| `-n` | `--num` | 测试次数 | 100 |
| `-h` | `--help` | 显示帮助信息 | - |

## 测试场景示例

### 1. 正常网络条件测试
```bash
# 测试在正常网络条件下的连接效果
sudo ./fragment_retransmission_test.sh site-to-site
```

### 2. 轻微网络问题测试
```bash
# 测试轻微延迟和丢包
sudo ./fragment_retransmission_test.sh -d 50 -l 5 site-to-site
```

### 3. 中等网络问题测试
```bash
# 测试中等延迟和丢包
sudo ./fragment_retransmission_test.sh -d 200 -l 15 site-to-site
```

### 4. 严重网络问题测试
```bash
# 测试严重延迟和丢包
sudo ./fragment_retransmission_test.sh -d 500 -l 30 site-to-site
```

### 5. 快速测试（少量次数）
```bash
# 快速测试，只执行10次
sudo ./fragment_retransmission_test.sh -d 100 -l 10 -n 10 site-to-site
```

## 输出说明

### 实时输出
脚本运行时会显示：
- 网络条件设置状态
- strongSwan服务重启状态
- 每次连接的测试结果
- 测试进度（每10次显示一次）

### 测试报告
脚本会生成两个文件：

1. **详细测试数据** (`/tmp/fragment_test_results_YYYYMMDD_HHMMSS.txt`)
   - 包含每次测试的详细信息
   - 格式：测试编号,结果,连接时间(ms),状态

2. **统计报告** (`test_stats_YYYYMMDD_HHMMSS.txt`)
   - 测试配置信息
   - 成功率统计
   - 连接时间统计（平均、最短、最长）

### 示例输出
```
=== 测试结果统计 ===
总测试次数: 100
成功次数: 85
失败次数: 15
成功率: 85.00%

连接时间统计 (仅成功连接):
平均连接时间: 1250.500ms
最短连接时间: 850.200ms
最长连接时间: 2100.300ms
```

## 注意事项

### 1. 权限要求
- 脚本需要root权限运行
- 需要能够执行tc命令设置网络条件
- 需要能够重启strongSwan服务

### 2. 网络接口
- 脚本会自动检测默认网络接口
- 可以通过 `-i` 参数指定特定接口
- 确保指定的接口存在且可用

### 3. 连接配置
- 确保指定的连接名称在strongSwan配置中存在
- 确保连接配置正确且对端可达
- 建议在测试前手动验证连接配置

### 4. 系统要求
- 需要安装 `bc` 命令（用于浮点计算）
- 需要安装 `tc` 命令（用于网络条件设置）
- 需要strongSwan服务正常运行

## 故障排除

### 1. 权限错误
```bash
# 确保以root权限运行
sudo ./fragment_retransmission_test.sh site-to-site
```

### 2. 网络接口不存在
```bash
# 查看可用网络接口
ip link show

# 指定正确的接口
sudo ./fragment_retransmission_test.sh -i eth0 site-to-site
```

### 3. strongSwan服务启动失败
```bash
# 检查strongSwan服务状态
sudo systemctl status strongswan

# 查看strongSwan日志
sudo tail -f /var/log/strongswan.log
```

### 4. 连接建立失败
```bash
# 检查连接配置
sudo swanctl --list-conns

# 手动测试连接
sudo swanctl --initiate --ike site-to-site
```

### 5. 网络条件设置失败
```bash
# 检查tc命令是否可用
which tc

# 检查网络接口状态
ip link show eth0
```

## 测试建议

### 1. 测试顺序
建议按以下顺序进行测试：
1. 正常网络条件（基线测试）
2. 轻微网络问题
3. 中等网络问题
4. 严重网络问题

### 2. 测试次数
- 快速验证：10-20次
- 标准测试：50-100次
- 详细测试：200-500次

### 3. 网络条件设置
- 延迟：0-1000ms
- 丢包率：0-50%
- 建议组合：延迟+丢包率

### 4. 结果分析
- 比较不同网络条件下的成功率
- 分析连接时间的变化趋势
- 观察分片重传机制的效果

## 示例测试流程

```bash
# 1. 基线测试（正常网络）
sudo ./fragment_retransmission_test.sh site-to-site

# 2. 轻微网络问题测试
sudo ./fragment_retransmission_test.sh -d 50 -l 5 site-to-site

# 3. 中等网络问题测试
sudo ./fragment_retransmission_test.sh -d 200 -l 15 site-to-site

# 4. 严重网络问题测试
sudo ./fragment_retransmission_test.sh -d 500 -l 30 site-to-site

# 5. 查看所有测试报告
ls -la test_stats_*.txt
```

## 脚本特点

- **自动化程度高**：一键完成网络条件设置、服务重启、连接测试
- **统计详细**：记录每次连接的时间和结果
- **报告完整**：生成详细的测试报告和统计数据
- **使用简单**：支持多种参数组合，适应不同测试需求
- **错误处理**：包含完善的错误检查和提示信息 