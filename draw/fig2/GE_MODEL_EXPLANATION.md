# GE模型参数设置详解

## 🤔 为什么需要Python计算器？

### 问题背景
GE模型有**两套参数系统**：

1. **直观参数** (我们想要的)：
   - 错误率 (0-100%)
   - 突发长度 (平均连续丢包数)
   - 坏状态时间比例 (0-100%)

2. **底层参数** (Linux tc需要的)：
   - p: 好状态到坏状态的概率
   - r: 坏状态到好状态的概率  
   - h: 坏状态无错误概率
   - k: 好状态错误概率

### 为什么不能直接设置？
```bash
# ❌ 这样是不行的！
tc qdisc add dev ens33 root netem loss random 5% 突发长度5 坏状态时间40%

# ✅ 必须这样！
tc qdisc add dev ens33 root netem loss random 5.71% 8.57% 12.50%
```

## 📊 参数映射关系

### 三参数模型映射
```
输入参数 → 计算 → 输出参数
错误率(35%) + 突发长度(5) + 坏状态时间(40%) 
    ↓
p=5.71% + r=8.57% + h=12.50%
```

### 数学关系
```
错误率 = (p * h) / (p + r)
突发长度 = 1 / r
坏状态时间 = p / (p + r)
```

## 🎯 X轴量化方案

### 方案1: 使用错误率作为X轴 (推荐)
```python
# X轴: 错误率 (0%, 2%, 5%, 8%, 10%, 12%, 15%, 18%, 20%)
# Y轴: HCT (毫秒)

x_values = [0, 2, 5, 8, 10, 12, 15, 18, 20]  # 错误率%
y_values = [hct_0, hct_2, hct_5, hct_8, hct_10, hct_12, hct_15, hct_18, hct_20]
```

### 方案2: 使用GE模型参数作为X轴
```python
# X轴: p值 (底层参数)
# Y轴: HCT (毫秒)

x_values = [p_0, p_2, p_5, p_8, p_10, p_12, p_15, p_18, p_20]
y_values = [hct_0, hct_2, hct_5, hct_8, hct_10, hct_12, hct_15, hct_18, hct_20]
```

## 🔧 实际使用流程

### 步骤1: 确定测试参数
```bash
# 我们想要测试这些错误率
错误率列表 = [0%, 2%, 5%, 8%, 10%, 12%, 15%, 18%, 20%]
突发长度 = 5 (固定)
坏状态时间 = 40% (固定)
```

### 步骤2: 计算GE参数
```bash
# 对每个错误率计算对应的GE参数
./ge_parameter_calculator.py --model 3param --error-rate 0.02 --burst-length 5 --bad-state-time 0.4 --tc-command
./ge_parameter_calculator.py --model 3param --error-rate 0.05 --burst-length 5 --bad-state-time 0.4 --tc-command
./ge_parameter_calculator.py --model 3param --error-rate 0.08 --burst-length 5 --bad-state-time 0.4 --tc-command
# ... 继续其他错误率
```

### 步骤3: 设置网络条件
```bash
# 使用计算出的参数设置网络
sudo tc qdisc add dev ens33 root netem loss random 2.86% 4.29% 6.25%  # 2%错误率
sudo tc qdisc add dev ens33 root netem loss random 7.14% 10.71% 15.63% # 5%错误率
sudo tc qdisc add dev ens33 root netem loss random 11.43% 17.14% 25.00% # 8%错误率
# ... 继续其他参数
```

### 步骤4: 收集数据
```bash
# 收集性能数据，X轴使用错误率
sudo ./connection_test.sh -l "2" -n 50 -o test_2percent.csv
sudo ./connection_test.sh -l "5" -n 50 -o test_5percent.csv
sudo ./connection_test.sh -l "8" -n 50 -o test_8percent.csv
# ... 继续其他测试
```

## 📈 绘图数据格式

### CSV文件格式
```csv
错误率(%),测试序号,结果,HCT(ms),重传次数
0,1,success,150,0
0,2,success,145,0
...
2,1,success,160,1
2,2,failed,0,3
...
```

### 绘图代码示例
```python
import pandas as pd
import matplotlib.pyplot as plt

# 读取数据
data = pd.read_csv('test_results.csv')

# 按错误率分组计算平均HCT
avg_hct = data.groupby('错误率(%)')['HCT(ms)'].mean()

# 绘制性能曲线
plt.figure(figsize=(10, 6))
plt.plot(avg_hct.index, avg_hct.values, 'bo-', linewidth=2, markersize=8)
plt.xlabel('错误率 (%)')
plt.ylabel('平均HCT (ms)')
plt.title('IPsec性能 vs 网络错误率')
plt.grid(True)
plt.show()
```

## 🎯 推荐的测试参数

### 基础性能测试
```bash
错误率: [0, 2, 5, 8, 10, 12, 15, 18, 20]
突发长度: 5 (固定)
坏状态时间: 0.4 (固定)
每个配置测试次数: 50
```

### 拐点精确定位
```bash
错误率: [8, 8.5, 9, 9.5, 10, 10.5, 11, 11.5, 12]
突发长度: 5 (固定)
坏状态时间: 0.4 (固定)
每个配置测试次数: 100
```

## 🔍 参数验证

### 验证GE参数是否正确
```bash
# 设置网络条件
sudo tc qdisc add dev ens33 root netem loss random 5.71% 8.57% 12.50%

# 验证实际错误率
ping -c 1000 192.168.31.136 | grep -o "packet loss" | wc -l
# 应该接近35%的错误率
```

### 查看当前网络设置
```bash
# 查看当前tc规则
sudo tc qdisc show dev ens33

# 清除网络设置
sudo tc qdisc del dev ens33 root
```

## 💡 总结

1. **Python计算器的作用**: 将直观的错误率转换为Linux tc需要的底层参数
2. **X轴量化**: 使用错误率作为X轴，这是最直观和有意义的方式
3. **工作流程**: 确定错误率 → 计算GE参数 → 设置网络 → 收集数据 → 绘图分析
4. **数据格式**: CSV文件包含错误率、测试结果、HCT等关键信息

这样就能准确地将GE模型的参数量化到X轴，用于绘制性能曲线和识别拐点！ 