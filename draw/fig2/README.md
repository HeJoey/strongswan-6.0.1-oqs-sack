# strongSwan 突发丢包率性能测试工具

这个工具包包含两个独立的脚本，用于测试strongSwan IPsec连接在不同网络条件下的性能表现。

## 文件说明

### 1. `set_network_conditions.sh` - 网络条件设置脚本
用于设置网络接口的突发丢包率，可以传到对端使用。

### 2. `connection_test.sh` - 连接测试脚本
用于测试IPsec连接性能，测量握手完成时间(HCT)和重传次数。

## 使用方法

### 步骤1: 设置网络条件

在两端分别设置网络条件：

```bash
# 设置10%突发丢包率，突发大小3
sudo ./set_network_conditions.sh -l 10 -b 3

# 设置5%丢包率，使用默认突发大小
sudo ./set_network_conditions.sh -l 5

# 清除网络条件
sudo ./set_network_conditions.sh -c

# 查看当前网络条件
sudo ./set_network_conditions.sh -s
```

### 步骤2: 运行连接测试

在本地运行连接测试：

```bash
# 运行10次测试（默认）
sudo ./connection_test.sh

# 运行50次测试
sudo ./connection_test.sh -n 50

# 指定连接名称和超时时间
sudo ./connection_test.sh -c net-net -t 30 -n 20

# 详细输出模式
sudo ./connection_test.sh -v -n 10

# 指定输出文件
sudo ./connection_test.sh -o my_results.csv
```

## 测试流程示例

### 完整测试流程

1. **准备阶段**
   ```bash
   # 两端都清除网络条件
   sudo ./set_network_conditions.sh -c
   ```

2. **设置网络条件**
   ```bash
   # 端A设置5%丢包率
   sudo ./set_network_conditions.sh -l 5
   
   # 端B设置5%丢包率
   sudo ./set_network_conditions.sh -l 5
   ```

3. **运行测试**
   ```bash
   # 端A运行连接测试
   sudo ./connection_test.sh -n 50 -o test_5pct.csv
   ```

4. **重复测试不同丢包率**
   ```bash
   # 设置10%丢包率
   sudo ./set_network_conditions.sh -l 10
   sudo ./connection_test.sh -n 50 -o test_10pct.csv
   
   # 设置15%丢包率
   sudo ./set_network_conditions.sh -l 15
   sudo ./connection_test.sh -n 50 -o test_15pct.csv
   ```

## 输出文件格式

### 连接测试报告格式
```csv
# IPsec连接测试报告
# 生成时间: 2025-07-19 15:30:00
# 连接名称: net-net
# 测试次数: 50
# 连接超时: 60s

## 测试结果摘要
总测试数: 50
成功连接: 48
连接超时: 2
成功率: 96.00%

## 握手完成时间 (HCT) 统计
平均HCT: 0.053s
最小HCT: 0.027s
最大HCT: 0.386s

## 重传统计
平均重传次数: 0.12

## 详细测试结果
测试序号,结果,HCT(s),重传次数
1,SUCCESS,0.059,0
2,SUCCESS,0.037,0
3,TIMEOUT,0,0
...
```

## 参数说明

### set_network_conditions.sh 参数
- `-i, --interface`: 网络接口名称 (默认: ens33)
- `-l, --loss`: 丢包率百分比 (0-100)
- `-b, --burst`: 突发大小 (默认: 3)
- `-c, --clear`: 清除所有网络条件设置
- `-s, --show`: 显示当前网络条件
- `-h, --help`: 显示帮助信息

### connection_test.sh 参数
- `-c, --connection`: 连接名称 (默认: net-net)
- `-t, --timeout`: 连接超时时间 (默认: 60秒)
- `-n, --tests`: 测试次数 (默认: 10)
- `-o, --output`: 输出文件 (默认: 自动生成)
- `-v, --verbose`: 详细输出模式
- `-h, --help`: 显示帮助信息

## 注意事项

1. **权限要求**: 两个脚本都需要root权限运行
2. **依赖检查**: 脚本会自动检查tc命令和strongSwan服务
3. **网络接口**: 确保指定的网络接口存在
4. **连接配置**: 确保strongSwan连接配置正确
5. **测试间隔**: 建议在测试之间留出足够间隔，避免影响结果

## 故障排除

### 常见问题

1. **tc命令不可用**
   ```bash
   # Ubuntu/Debian
   sudo apt-get install iproute2
   
   # CentOS/RHEL
   sudo yum install iproute
   ```

2. **strongSwan服务未运行**
   ```bash
   sudo systemctl start strongswan
   sudo systemctl enable strongswan
   ```

3. **连接配置不存在**
   ```bash
   # 查看可用连接
   swanctl --list-conns
   ```

4. **网络接口不存在**
   ```bash
   # 查看可用网络接口
   ip link show
   ```

## 数据收集建议

为了获得可靠的测试数据，建议：

1. **测试次数**: 每个条件至少测试50次
2. **测试间隔**: 每次测试间隔1-2秒
3. **环境稳定**: 确保测试期间网络环境稳定
4. **重复验证**: 在不同时间段重复测试
5. **数据备份**: 及时备份测试结果文件 