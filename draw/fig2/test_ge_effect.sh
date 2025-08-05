#!/bin/bash

# GE模型效果测试脚本
# 通过实际测试验证GE模型的作用

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

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[$(date '+%H:%M:%S')]${NC} $1"
}

# 检查网络接口
check_interface() {
    log_step "检查网络接口..."
    
    # 获取默认网络接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$INTERFACE" ]; then
        log_error "无法找到默认网络接口"
        exit 1
    fi
    
    log_success "使用网络接口: $INTERFACE"
    echo $INTERFACE
}

# 清除网络设置
clear_network() {
    local interface=$1
    log_step "清除网络设置..."
    
    sudo tc qdisc del dev $interface root 2>/dev/null || true
    log_success "网络设置已清除"
}

# 测试基础连通性
test_connectivity() {
    log_step "测试基础网络连通性..."
    
    if ping -c 3 192.168.31.137 >/dev/null 2>&1; then
        log_success "网络连通正常"
        return 0
    else
        log_error "网络连通失败"
        return 1
    fi
}

# 测试简单丢包
test_simple_loss() {
    local interface=$1
    local loss_rate=$2
    
    log_step "测试简单丢包: ${loss_rate}%"
    
    # 设置简单丢包
    sudo tc qdisc add dev $interface root netem loss $loss_rate%
    
    # 测试丢包率
    log_info "发送100个ping包测试丢包率..."
    ping_result=$(ping -c 100 192.168.31.137 2>/dev/null | grep "packet loss" || echo "100% packet loss")
    echo "   结果: $ping_result"
    
    # 清除设置
    clear_network $interface
    echo ""
}

# 测试GE模型
test_ge_model() {
    local interface=$1
    local error_rate=$2
    local burst_length=$3
    local bad_state_time=$4
    
    log_step "测试GE模型: 错误率=${error_rate*100}%, 突发长度=$burst_length, 坏状态时间=${bad_state_time*100}%"
    
    # 计算GE参数
    log_info "计算GE参数..."
    ge_result=$(./ge_parameter_calculator.py --model 3param --error-rate $error_rate --burst-length $burst_length --bad-state-time $bad_state_time --tc-command 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "GE参数计算失败，参数超出范围"
        return 1
    fi
    
    # 提取tc命令
    tc_cmd=$(echo "$ge_result" | grep "tc qdisc" | sed 's/^  //')
    log_info "GE参数: $tc_cmd"
    
    # 设置GE模型
    log_info "设置GE模型网络条件..."
    eval "sudo $tc_cmd"
    
    # 测试丢包率
    log_info "发送100个ping包测试GE模型丢包率..."
    ping_result=$(ping -c 100 192.168.31.1 2>/dev/null | grep "packet loss" || echo "100% packet loss")
    echo "   结果: $ping_result"
    
    # 清除设置
    clear_network $interface
    echo ""
}

# 测试IPsec连接
test_ipsec_connection() {
    local label=$1
    local num_tests=$2
    
    log_step "测试IPsec连接: 标签=$label, 测试次数=$num_tests"
    
    # 运行连接测试
    if [ -f "./connection_test.sh" ]; then
        log_info "运行IPsec连接测试..."
        sudo ./connection_test.sh -l "$label" -n $num_tests -o "test_${label}_percent.csv"
        
        if [ -f "test_${label}_percent.csv" ]; then
            log_success "测试完成，数据保存到 test_${label}_percent.csv"
            
            # 显示统计信息
            log_info "测试结果统计:"
            total=$(wc -l < "test_${label}_percent.csv")
            success=$(grep -c "success" "test_${label}_percent.csv" || echo "0")
            failed=$(grep -c "failed" "test_${label}_percent.csv" || echo "0")
            
            echo "   总测试数: $((total-1))"  # 减去标题行
            echo "   成功次数: $success"
            echo "   失败次数: $failed"
            echo "   成功率: $(echo "scale=1; $success * 100 / ($total - 1)" | bc)%"
            
            # 计算平均HCT
            if [ $success -gt 0 ]; then
                avg_hct=$(grep "success" "test_${label}_percent.csv" | awk -F',' '{sum+=$4} END {print sum/NR}')
                echo "   平均HCT: ${avg_hct}ms"
            fi
        else
            log_error "测试失败，未生成数据文件"
        fi
    else
        log_warning "connection_test.sh 不存在，跳过IPsec测试"
    fi
    
    echo ""
}

# 主测试函数
main_test() {
    echo "=========================================="
    echo "          GE模型效果测试"
    echo "=========================================="
    echo ""
    
    # 检查网络接口
    INTERFACE=$(check_interface)
    
    # 测试基础连通性
    if ! test_connectivity; then
        log_error "基础网络连通性测试失败，退出测试"
        exit 1
    fi
    
    echo "=========================================="
    echo "          测试1: 理想网络条件"
    echo "=========================================="
    clear_network $INTERFACE
    test_connectivity
    test_ipsec_connection "0" 10
    
    echo "=========================================="
    echo "          测试2: 简单丢包模型"
    echo "=========================================="
    test_simple_loss $INTERFACE 5
    test_simple_loss $INTERFACE 10
    test_simple_loss $INTERFACE 15
    
    echo "=========================================="
    echo "          测试3: GE模型"
    echo "=========================================="
    
    # 测试不同的GE参数
    test_ge_model $INTERFACE 0.35 5 0.4  # 35%错误率
    test_ge_model $INTERFACE 0.40 5 0.4  # 40%错误率
    test_ge_model $INTERFACE 0.45 5 0.4  # 45%错误率
    
    echo "=========================================="
    echo "          测试4: IPsec性能对比"
    echo "=========================================="
    
    # 测试理想网络下的IPsec性能
    log_step "测试理想网络下的IPsec性能..."
    clear_network $INTERFACE
    test_ipsec_connection "0" 20
    
    # 测试GE模型下的IPsec性能
    log_step "测试GE模型下的IPsec性能..."
    test_ge_model $INTERFACE 0.35 5 0.4
    test_ipsec_connection "35" 20
    
    echo "=========================================="
    echo "          测试完成"
    echo "=========================================="
    log_success "所有测试完成！"
    echo ""
    echo "📊 生成的数据文件:"
    ls -la test_*_percent.csv 2>/dev/null || echo "   无数据文件生成"
    echo ""
    echo "📈 可以查看CSV文件分析结果:"
    echo "   cat test_0_percent.csv"
    echo "   cat test_35_percent.csv"
}

# 快速测试函数
quick_test() {
    echo "=========================================="
    echo "          GE模型快速测试"
    echo "=========================================="
    echo ""
    
    INTERFACE=$(check_interface)
    
    log_step "快速验证GE模型效果..."
    echo ""
    
    # 测试理想网络
    log_info "1. 测试理想网络条件"
    clear_network $INTERFACE
    ping_result=$(ping -c 20 192.168.31.1 2>/dev/null | grep "packet loss" || echo "100% packet loss")
    echo "   Ping结果: $ping_result"
    echo ""
    
    # 测试GE模型
    log_info "2. 测试GE模型 (35%错误率)"
    ge_result=$(./ge_parameter_calculator.py --model 3param --error-rate 0.35 --burst-length 5 --bad-state-time 0.4 --tc-command 2>/dev/null)
    tc_cmd=$(echo "$ge_result" | grep "tc qdisc" | sed 's/^  //')
    echo "   GE参数: $tc_cmd"
    
    eval "sudo $tc_cmd"
    ping_result=$(ping -c 20 192.168.31.1 2>/dev/null | grep "packet loss" || echo "100% packet loss")
    echo "   Ping结果: $ping_result"
    
    clear_network $INTERFACE
    echo ""
    
    log_success "快速测试完成！"
}

# 参数解析
case "${1:-main}" in
    "quick")
        quick_test
        ;;
    "main")
        main_test
        ;;
    *)
        echo "GE模型效果测试脚本"
        echo ""
        echo "用法: $0 [选项]"
        echo ""
        echo "选项:"
        echo "  quick    快速测试 (验证GE模型基本功能)"
        echo "  main     完整测试 (包含IPsec性能测试)"
        echo ""
        echo "示例:"
        echo "  $0 quick    # 快速验证GE模型"
        echo "  $0 main     # 完整测试流程"
        ;;
esac 