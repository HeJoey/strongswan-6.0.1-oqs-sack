# 绘图数据生成工具

这个工具专门用于生成strongSwan IKE SA建立性能测试的绘图数据，支持生成图4、图5、图6所需的数据。

## 文件说明

### 1. `generate_plot_data.sh` - 绘图数据生成脚本
- 自动设置网络条件（突发丢包率）
- 测试IKE SA建立性能
- 生成原始数据和统计摘要
- 专门为三个关键图设计

### 2. `set_network_conditions.sh` - 网络条件设置脚本
- 可以传到对端使用
- 设置突发丢包率

## 三个关键图的数据需求

### 图4：握手成功率 vs. 突发丢包率
- **样式**: 带数据标记的曲线图 (Line Graph with Markers)
- **数据**: 成功率百分比
- **来源**: `*_summary.csv` 中的成功率列

### 图5：握手完成时间(HCT) vs. 突发丢包率
- **样式**: 箱形图 (Box Plot)
- **数据**: HCT分布数据
- **来源**: `*_data.csv` 中的HCT列

### 图6：IKE消息平均重传次数 vs. 突发丢包率
- **样式**: 带误差棒的曲线图 (Line Graph with Error Bars)
- **数据**: 平均重传次数和标准差
- **来源**: `*_summary.csv` 中的重传统计列

## 使用方法

### 基本用法
```bash
# 使用默认设置生成数据
sudo ./generate_plot_data.sh

# 指定输出文件
sudo ./generate_plot_data.sh -o my_data.csv
```

### 自定义测试参数
```bash
# 测试特定丢包率
sudo ./generate_plot_data.sh -l "0 5 10 15" -n 50

# 测试更多丢包率
sudo ./generate_plot_data.sh -l "0 2 5 8 10 12 15 18 20" -n 30
```

### 参数说明
- `-l, --loss-rates`: 丢包率列表 (默认: 0 5 10 15 20)
- `-n, --tests-per-loss`: 每个丢包率的测试次数 (默认: 50)
- `-c, --connection`: 连接名称 (默认: net-net)
- `-o, --output`: 输出文件 (默认: plot_data.csv)

## 输出文件格式

### 1. 原始数据文件 (`*_data.csv`)
```csv
# 绘图数据文件
# 格式: 丢包率(%),测试序号,结果,HCT(ms),重传次数
0,1,SUCCESS,78.8,0
0,2,SUCCESS,94.8,0
0,3,SUCCESS,146.2,0
5,1,SUCCESS,104.2,0
5,2,SUCCESS,97.0,0
5,3,SUCCESS,146.6,0
```

### 2. 统计摘要文件 (`*_summary.csv`)
```csv
# 统计摘要
# 格式: 丢包率(%),成功率(%),HCT均值(ms),HCT中位数(ms),HCT标准差(ms),平均重传次数,重传标准差
0,100.00,106.6,94.8,35.3,0.00,0.00
5,100.00,115.9,104.2,26.8,0.00,0.00
```

## 测试流程示例

### 完整测试流程
```bash
# 1. 生成绘图数据（本地）
sudo ./generate_plot_data.sh -l "0 5 10 15 20" -n 50 -o kem_performance_data.csv

# 2. 查看生成的文件
ls -la kem_performance_data.csv kem_performance_data_summary.csv

# 3. 检查数据质量
head -10 kem_performance_data.csv
cat kem_performance_data_summary.csv
```

### 快速测试
```bash
# 快速验证脚本功能
sudo ./generate_plot_data.sh -l "0 5" -n 5 -o quick_test.csv
```

## 数据质量检查

### 关键指标
1. **成功率**: 理想网络下应该接近100%
2. **HCT范围**: 正常应该在50-200ms之间
3. **重传次数**: 理想网络下应该为0

### 异常情况处理
- **成功率过低**: 检查网络连接和strongSwan配置
- **HCT异常高**: 检查网络延迟和系统负载
- **重传次数过多**: 检查网络丢包设置

## 绘图建议

### 使用Python绘图
```python
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# 读取数据
data = pd.read_csv('kem_performance_data.csv', comment='#')
summary = pd.read_csv('kem_performance_data_summary.csv', comment='#')

# 图4: 成功率曲线
plt.figure(figsize=(10, 6))
plt.plot(summary['丢包率(%)'], summary['成功率(%)'], 'o-', linewidth=2, markersize=8)
plt.xlabel('突发丢包率 (%)')
plt.ylabel('握手成功率 (%)')
plt.title('IKE SA建立成功率 vs. 突发丢包率')
plt.grid(True, alpha=0.3)
plt.show()

# 图5: HCT箱形图
plt.figure(figsize=(12, 8))
sns.boxplot(data=data, x='丢包率(%)', y='HCT(ms)')
plt.xlabel('突发丢包率 (%)')
plt.ylabel('握手完成时间 (ms)')
plt.title('IKE SA建立时间分布 vs. 突发丢包率')
plt.show()

# 图6: 重传次数曲线
plt.figure(figsize=(10, 6))
plt.errorbar(summary['丢包率(%)'], summary['平均重传次数'], 
             yerr=summary['重传标准差'], fmt='o-', capsize=5)
plt.xlabel('突发丢包率 (%)')
plt.ylabel('平均重传次数')
plt.title('IKE消息平均重传次数 vs. 突发丢包率')
plt.grid(True, alpha=0.3)
plt.show()
```

## 注意事项

1. **测试环境**: 确保网络环境稳定，避免其他网络活动干扰
2. **测试次数**: 建议每个条件至少测试30-50次以获得可靠统计
3. **数据备份**: 及时备份重要的测试数据
4. **对端设置**: 记得在对端也设置相同的网络条件
5. **时间安排**: 完整测试可能需要较长时间，建议在系统负载较低时进行

## 故障排除

### 常见问题
1. **脚本提前退出**: 检查`set -e`设置和错误处理
2. **连接失败**: 检查strongSwan服务和连接配置
3. **数据异常**: 检查网络条件和系统状态
4. **权限问题**: 确保使用sudo运行脚本 