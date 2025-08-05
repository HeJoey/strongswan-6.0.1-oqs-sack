#!/bin/bash

# GE模型工作流程演示脚本
# 展示从参数计算到数据收集的完整过程

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[$(date '+%H:%M:%S')]${NC} $1"
}

# 演示GE参数计算
demo_parameter_calculation() {
    echo "=========================================="
    echo "          GE参数计算演示"
    echo "=========================================="
    echo ""
    
    # 测试参数列表
    error_rates=(0.02 0.05 0.08 0.10 0.12 0.15 0.18 0.20)
    burst_length=5
    bad_state_time=0.4
    
    echo "📊 测试参数:"
    echo "   错误率列表: ${error_rates[*]}"
    echo "   突发长度: $burst_length"
    echo "   坏状态时间: $bad_state_time"
    echo ""
    
    echo "🧮 计算GE参数:"
    echo ""
    
    for rate in "${error_rates[@]}"; do
        percentage=$(echo "$rate * 100" | bc -l | cut -d. -f1)
        log_step "计算错误率 ${rate} (${percentage}%) 的GE参数..."
        
        # 计算GE参数
        result=$(./ge_parameter_calculator.py --model 3param --error-rate $rate --burst-length $burst_length --bad-state-time $bad_state_time --tc-command 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo "   ✅ 错误率 ${percentage}% → $result"
        else
            echo "   ❌ 错误率 ${percentage}% → 参数超出范围"
        fi
        echo ""
    done
}

# 演示网络设置
demo_network_setup() {
    echo "=========================================="
    echo "          网络设置演示"
    echo "=========================================="
    echo ""
    
    log_step "演示网络条件设置..."
    echo ""
    
    echo "1️⃣ 清除现有网络设置:"
    echo "   sudo ./set_realistic_network.sh -c"
    echo ""
    
    echo "2️⃣ 设置5%错误率的GE模型:"
    echo "   sudo ./set_realistic_network.sh -l 5 -m gilbert -b 5 -t 0.4"
    echo ""
    
    echo "3️⃣ 查看当前网络设置:"
    echo "   sudo ./set_realistic_network.sh -s"
    echo ""
    
    echo "4️⃣ 验证网络条件:"
    echo "   ping -c 10 192.168.31.136"
    echo ""
}

# 演示数据收集
demo_data_collection() {
    echo "=========================================="
    echo "          数据收集演示"
    echo "=========================================="
    echo ""
    
    log_step "演示性能数据收集..."
    echo ""
    
    echo "📊 数据收集命令:"
    echo "   sudo ./connection_test.sh -l \"5\" -n 10 -o demo_5percent.csv"
    echo ""
    
    echo "📈 生成的CSV数据格式:"
    echo "   错误率(%),测试序号,结果,HCT(ms),重传次数"
    echo "   5,1,success,150,0"
    echo "   5,2,success,145,1"
    echo "   5,3,failed,0,3"
    echo "   ..."
    echo ""
    
    echo "🎯 X轴量化:"
    echo "   X轴: 错误率 (5%)"
    echo "   Y轴: HCT (毫秒)"
    echo "   数据点: 平均HCT = 147.5ms"
    echo ""
}

# 演示完整工作流程
demo_complete_workflow() {
    echo "=========================================="
    echo "          完整工作流程演示"
    echo "=========================================="
    echo ""
    
    log_step "演示从参数到绘图的完整流程..."
    echo ""
    
    echo "🔄 工作流程步骤:"
    echo ""
    
    echo "步骤1: 确定测试参数"
    echo "   错误率: 5%"
    echo "   突发长度: 5"
    echo "   坏状态时间: 40%"
    echo ""
    
    echo "步骤2: 计算GE参数"
    echo "   ./ge_parameter_calculator.py --model 3param --error-rate 0.05 --burst-length 5 --bad-state-time 0.4 --tc-command"
    echo "   输出: tc qdisc add dev ens33 root netem loss random 7.14% 10.71% 15.63%"
    echo ""
    
    echo "步骤3: 设置网络条件 (两端同步)"
    echo "   端A: sudo tc qdisc add dev ens33 root netem loss random 7.14% 10.71% 15.63%"
    echo "   端B: sudo tc qdisc add dev ens33 root netem loss random 7.14% 10.71% 15.63%"
    echo ""
    
    echo "步骤4: 收集性能数据 (只在测试端)"
    echo "   sudo ./connection_test.sh -l \"5\" -n 50 -o test_5percent.csv"
    echo ""
    
    echo "步骤5: 重复测试不同参数"
    echo "   错误率: 0%, 2%, 5%, 8%, 10%, 12%, 15%, 18%, 20%"
    echo "   生成文件: test_0percent.csv, test_2percent.csv, ..."
    echo ""
    
    echo "步骤6: 数据分析和绘图"
    echo "   X轴: 错误率 [0, 2, 5, 8, 10, 12, 15, 18, 20]"
    echo "   Y轴: 平均HCT [hct_0, hct_2, hct_5, hct_8, hct_10, hct_12, hct_15, hct_18, hct_20]"
    echo ""
}

# 演示参数验证
demo_parameter_validation() {
    echo "=========================================="
    echo "          参数验证演示"
    echo "=========================================="
    echo ""
    
    log_step "演示如何验证GE参数设置是否正确..."
    echo ""
    
    echo "🔍 验证方法:"
    echo ""
    
    echo "1️⃣ 查看tc规则:"
    echo "   sudo tc qdisc show dev ens33"
    echo "   应该显示: loss random 7.14% 10.71% 15.63%"
    echo ""
    
    echo "2️⃣ 测试实际错误率:"
    echo "   ping -c 1000 192.168.31.136 | grep -o 'packet loss' | wc -l"
    echo "   应该接近: 50个丢包 (5%错误率)"
    echo ""
    
    echo "3️⃣ 使用ping统计:"
    echo "   ping -c 100 192.168.31.136"
    echo "   查看输出中的丢包率"
    echo ""
    
    echo "4️⃣ 清除网络设置:"
    echo "   sudo tc qdisc del dev ens33 root"
    echo ""
}

# 显示X轴量化说明
show_x_axis_quantification() {
    echo "=========================================="
    echo "          X轴量化说明"
    echo "=========================================="
    echo ""
    
    echo "🎯 X轴量化方案:"
    echo ""
    
    echo "✅ 推荐方案: 使用错误率作为X轴"
    echo "   X轴: [0, 2, 5, 8, 10, 12, 15, 18, 20] (错误率%)"
    echo "   Y轴: [hct_0, hct_2, hct_5, hct_8, hct_10, hct_12, hct_15, hct_18, hct_20] (平均HCT)"
    echo ""
    
    echo "📊 数据收集策略:"
    echo "   每个错误率测试50次连接"
    echo "   计算平均HCT作为Y轴值"
    echo "   识别拐点区域的性能突变"
    echo ""
    
    echo "🔍 拐点识别:"
    echo "   观察HCT曲线的突变点"
    echo "   通常在高错误率区域 (8-12%)"
    echo "   使用Kneedle算法自动识别"
    echo ""
}

# 主函数
main() {
    case "${1:-all}" in
        "calc")
            demo_parameter_calculation
            ;;
        "network")
            demo_network_setup
            ;;
        "data")
            demo_data_collection
            ;;
        "workflow")
            demo_complete_workflow
            ;;
        "validation")
            demo_parameter_validation
            ;;
        "xaxis")
            show_x_axis_quantification
            ;;
        "all")
            demo_parameter_calculation
            echo ""
            demo_network_setup
            echo ""
            demo_data_collection
            echo ""
            demo_complete_workflow
            echo ""
            demo_parameter_validation
            echo ""
            show_x_axis_quantification
            ;;
        *)
            echo "GE模型工作流程演示脚本"
            echo ""
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  calc       演示参数计算"
            echo "  network    演示网络设置"
            echo "  data       演示数据收集"
            echo "  workflow   演示完整工作流程"
            echo "  validation 演示参数验证"
            echo "  xaxis      显示X轴量化说明"
            echo "  all        显示所有演示"
            echo ""
            echo "示例:"
            echo "  $0 calc      # 查看参数计算演示"
            echo "  $0 workflow  # 查看完整工作流程"
            echo "  $0 all       # 查看所有演示"
            ;;
    esac
}

# 运行主函数
main "$@" 