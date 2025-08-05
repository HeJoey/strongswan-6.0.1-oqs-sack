# strongSwan 突发丢包率性能测试工具集

本工具集用于测试strongSwan IPsec在不同突发丢包率条件下的性能表现，专门用于生成论文中的图5和图6。

## 📁 文件说明

### 核心脚本

1. **`burst_loss_test.sh`** - 主测试脚本
   - 自动测试不同突发丢包率下的连接性能
   - 收集连接成功率、握手完成时间(HCT)、重传次数等数据
   - 生成适合绘图的CSV数据文件

2. **`set_network_conditions.sh`** - 网络条件设置脚本
   - 快速设置指定的丢包率
   - 支持突发丢包和随机丢包模式
   - 提供网络条件清理和状态查看功能

3. **`retransmission_stats.sh`** - 重传统计专用脚本
   - 专门统计IKE消息的重传次数和模式
   - 支持实时监控和历史日志分析
   - 生成详细的重传统计报告

## 🚀 快速开始

### 1. 完整突发丢包率测试

```bash
# 使用默认参数运行完整测试
sudo ./burst_loss_test.sh

# 自定义测试次数 (每个丢包率测试50次)
sudo ./burst_loss_test.sh -n 50

# 指定网络接口
sudo ./burst_loss_test.sh -i enp0s3
```

### 2. 设置特定网络条件

```bash
# 设置10%突发丢包率
sudo ./set_network_conditions.sh -b 10

# 设置15%随机丢包率
sudo ./set_network_conditions.sh 15

# 清理网络条件设置
sudo ./set_network_conditions.sh -c

# 查看当前网络条件
sudo ./set_network_conditions.sh -s
```

### 3. 重传数据统计

```bash
# 执行重传统计测试
sudo ./retransmission_stats.sh

# 实时监控重传活动
sudo ./retransmission_stats.sh -l

# 分析现有日志
sudo ./retransmission_stats.sh -r
```

## 📊 生成的数据文件

### 主要输出文件

1. **`burst_loss_results_TIMESTAMP/`** - 主测试结果目录
   - `burst_loss_results.csv` - 原始测试数据
   - `summary_statistics.csv` - 汇总统计数据 (用于图5)
   - `hct_boxplot_data.csv` - 箱形图数据 (用于图6)
   - `statistics_X%_txt` - 各丢包率的详细统计

2. **重传统计文件**
   - `retransmission_stats_TIMESTAMP.csv` - 重传数据
   - `retransmission_stats_TIMESTAMP_report.txt` - 重传报告

### 数据格式说明

#### summary_statistics.csv (图表数据)
```csv
# 丢包率(%),成功率(%),HCT均值(s),HCT中位数(s),HCT标准差(s),平均重传次数
0,100.00,2.456,2.234,0.345,0.00
5,96.67,3.123,2.876,0.567,1.23
10,90.00,4.234,3.456,0.789,2.45
...
```

#### hct_boxplot_data.csv (箱形图数据)
```csv
# 丢包率(%),HCT(s)
0,2.234
0,2.456
0,2.123
5,2.876
5,3.234
...
```

## 📈 数据可视化建议

### 图5: 连接成功率 vs 突发丢包率
**推荐样式**: 带标记的曲线图
- X轴: 突发丢包率 (%)
- Y轴: 连接成功率 (%)
- 数据源: `summary_statistics.csv` 第1,2列

### 图6: 握手完成时间(HCT) vs 突发丢包率
**推荐样式**: 箱形图 (Box Plot)
- X轴: 突发丢包率 (%)
- Y轴: HCT (秒)
- 数据源: `hct_boxplot_data.csv`

### 图7: IKE消息平均重传次数 vs 突发丢包率
**推荐样式**: 带误差棒的曲线图
- X轴: 突发丢包率 (%)
- Y轴: 平均重传次数
- 数据源: `summary_statistics.csv` 第1,6列

## ⚙️ 高级配置

### 自定义丢包率范围

编辑 `burst_loss_test.sh` 中的 `LOSS_RATES` 数组:
```bash
readonly LOSS_RATES=(0 2 5 8 10 15 20 25 30 35 40 45 50)
```

### 突发模式配置

在 `burst_loss_test.sh` 中修改突发大小:
```bash
readonly BURST_SIZE=3  # 连续丢包数量
```

### 测试参数调整

```bash
# 修改默认测试次数
readonly DEFAULT_TESTS_PER_LOSS_RATE=30

# 修改连接超时时间
readonly DEFAULT_CONNECTION_TIMEOUT=60
```

## 🔧 故障排除

### 常见问题

1. **权限问题**
   ```bash
   # 确保以root权限运行
   sudo ./burst_loss_test.sh
   ```

2. **网络接口不存在**
   ```bash
   # 查看可用接口
   ip link show
   # 使用正确的接口名
   sudo ./set_network_conditions.sh -i 你的接口名 10
   ```

3. **strongSwan未运行**
   ```bash
   # 启动strongSwan
   sudo systemctl start strongswan
   # 检查状态
   sudo systemctl status strongswan
   ```

4. **连接配置问题**
   ```bash
   # 检查连接配置
   swanctl --list-conns
   # 确保连接名称正确
   sudo ./burst_loss_test.sh -c 你的连接名
   ```

### 调试技巧

1. **查看实时日志**
   ```bash
   sudo journalctl -u strongswan -f
   ```

2. **检查网络条件**
   ```bash
   sudo ./set_network_conditions.sh -s
   ```

3. **监控重传活动**
   ```bash
   sudo ./retransmission_stats.sh -l
   ```

## 📋 测试建议

### 完整性能评估流程

1. **基线测试** (无丢包)
   ```bash
   sudo ./set_network_conditions.sh 0
   sudo ./retransmission_stats.sh -n 20
   ```

2. **低丢包率测试** (2-10%)
   ```bash
   for rate in 2 5 8 10; do
     sudo ./set_network_conditions.sh -b $rate
     sudo ./retransmission_stats.sh -n 15
     sleep 30
   done
   ```

3. **高丢包率测试** (15-50%)
   ```bash
   sudo ./burst_loss_test.sh -n 30
   ```

4. **数据分析**
   - 使用生成的CSV文件创建图表
   - 对比不同算法的性能差异
   - 分析重传模式和效率

## 📝 注意事项

1. **测试环境**: 确保测试期间网络环境稳定
2. **数据量**: 高丢包率下测试时间会显著增加
3. **资源占用**: 大量测试可能产生大量日志数据
4. **算法选择**: 不同后量子算法的分片大小差异很大
5. **清理**: 测试完成后记得清理网络条件设置

## 🎯 预期结果

- **连接成功率**: 随丢包率增加而下降
- **握手完成时间**: 随丢包率增加而增长，分布变得更分散
- **重传次数**: 与丢包率正相关，体现网络恢复能力

这些数据将清晰展示strongSwan在恶劣网络条件下的表现，特别是后量子密码学场景中的大分片处理能力。 