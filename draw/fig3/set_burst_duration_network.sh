#!/bin/bash

# 基于平均突发持续时间的网络设置脚本
# 方案A: X轴 = 平均突发持续时间 (ms)

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
    # 获取默认网络接口
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$INTERFACE" ]; then
        log_error "无法找到默认网络接口"
        return 1
    fi
    
    printf "%s" "$INTERFACE"
}

# 清除网络设置
clear_network() {
    local interface=$1
    log_step "清除网络设置..."
    
    sudo tc qdisc del dev $interface root 2>/dev/null || true
    log_success "网络设置已清除"
}

# 设置理想网络条件
set_ideal_network() {
    local interface=$1
    log_step "设置理想网络条件..."
    
    clear_network $interface
    log_success "理想网络条件已设置 (无丢包)"
}

# 设置基于突发持续时间的GE模型
set_burst_duration_network() {
    local interface=$1
    local burst_duration=$2
    local p_value=${3:-0.01}
    local time_slot=${4:-10.0}
    
    log_step "设置基于突发持续时间的GE模型: ${burst_duration}ms"
    
    # 计算GE参数
    log_info "计算GE模型参数..."
    ge_result=$(./burst_duration_calculator.py --burst-duration $burst_duration --p-value $p_value --time-slot $time_slot --tc-command --verbose 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "GE参数计算失败"
        return 1
    fi
    
    # 提取tc命令
    tc_cmd=$(echo "$ge_result" | grep "tc qdisc" | sed 's/^  //')
    if [ -z "$tc_cmd" ]; then
        log_error "无法提取tc命令"
        echo "$ge_result"
        return 1
    fi
    log_info "GE参数: $tc_cmd"
    
    # 提取q值用于显示
    q_value=$(echo "$ge_result" | grep "恢复概率 q" | awk '{print $4}')
    
    # 清除现有设置
    clear_network $interface
    
    # 设置GE模型
    log_info "应用GE模型网络条件..."
    eval "sudo $tc_cmd"
    
    log_success "基于突发持续时间的GE模型已设置"
    
    # 显示设置的参数
    echo ""
    log_info "设置的参数详情:"
    echo "   目标突发持续时间: ${burst_duration}ms"
    echo "   转移概率 p (G→B): ${p_value} (${p_value}%)"
    echo "   恢复概率 q (B→G): ${q_value} (${q_value}%)"
    echo "   坏状态丢包率 (1-h): 1.0 (100%)"
    echo "   好状态丢包率 (1-k): 0.0 (0%)"
    echo "   执行的tc命令: $tc_cmd"
    echo ""
}

# 显示当前网络设置
show_network_status() {
    local interface="$1"
    log_step "显示当前网络设置..."
    
    if [ -z "$interface" ]; then
        log_error "网络接口参数为空"
        return 1
    fi
    
    # 获取tc设置
    local tc_output=$(sudo tc qdisc show dev "$interface" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$tc_output" ]; then
        echo "   原始tc输出: $tc_output"
        echo ""
        
        # 解析参数
        if [[ $tc_output == *"loss gemodel"* ]]; then
            # 提取参数值
            local p_val=$(echo "$tc_output" | grep -o 'p [0-9.]*%' | awk '{print $2}' | sed 's/%//')
            local r_val=$(echo "$tc_output" | grep -o 'r [0-9.]*%' | awk '{print $2}' | sed 's/%//')
            local h_val=$(echo "$tc_output" | grep -o '1-h [0-9.]*%' | awk '{print $2}' | sed 's/%//')
            local k_val=$(echo "$tc_output" | grep -o '1-k [0-9.]*%' | awk '{print $2}' | sed 's/%//')
            
            echo "   参数解析:"
            echo "     p (G→B转移概率): ${p_val}% (${p_val}% = $(echo "scale=4; $p_val/100" | bc -l))"
            echo "     r (B→G恢复概率): ${r_val}% (${r_val}% = $(echo "scale=4; $r_val/100" | bc -l))"
            echo "     1-h (坏状态丢包率): ${h_val}% (${h_val}% = $(echo "scale=4; $h_val/100" | bc -l))"
            echo "     1-k (好状态丢包率): ${k_val}% (${k_val}% = $(echo "scale=4; $k_val/100" | bc -l))"
            echo ""
            
            # 计算突发持续时间
            if [ -n "$r_val" ] && [ "$r_val" != "0" ]; then
                # 突发持续时间 = 时间槽长度 / 恢复概率
                # 时间槽长度默认为10ms，恢复概率r以百分比表示
                local time_slot_ms=10.0
                local r_decimal=$(echo "scale=6; $r_val/100" | bc -l)
                local burst_duration=$(echo "scale=2; $time_slot_ms/$r_decimal" | bc -l)
                echo "   计算得到的突发持续时间: ${burst_duration}ms"
                echo "    (基于公式: 突发持续时间 = 时间槽长度 / 恢复概率)"
                echo "    (时间槽长度: ${time_slot_ms}ms, 恢复概率: ${r_decimal})"
            fi
        else
            echo "   当前设置不是GE模型"
        fi
    else
        log_warning "无法显示网络设置，可能没有设置或接口不存在"
        return 1
    fi
}

# 测试网络连通性
test_connectivity() {
    local target=${1:-"192.168.31.1"}
    local count=${2:-10}
    
    log_step "测试网络连通性: $target (${count}个包)"
    
    ping_result=$(ping -c $count $target 2>/dev/null | grep "packet loss" || echo "100% packet loss")
    echo "   结果: $ping_result"
    
    # 分析突发丢包模式
    if [[ $ping_result != *"100% packet loss"* ]]; then
        log_info "分析突发丢包模式..."
        ping -c $count $target 2>/dev/null | grep -E "icmp_seq=[0-9]+" | head -5
    fi
}

# 主函数
main() {
    echo "=========================================="
    echo "      基于突发持续时间的网络设置"
    echo "=========================================="
    echo ""
    echo "🎯 方案A: X轴 = 平均突发持续时间 (ms)"
    echo "核心问题: '网络中断多长时间，IPsec连接会失败？'"
    echo ""
    
    # 检查网络接口
    INTERFACE=$(check_interface)
    
    if [ -z "$INTERFACE" ]; then
        log_error "无法获取网络接口"
        exit 1
    fi
    
    case "${1:-help}" in
        "clear")
            clear_network $INTERFACE
            ;;
        "ideal")
            set_ideal_network $INTERFACE
            ;;
        "burst")
            if [ -z "$2" ]; then
                log_error "请指定突发持续时间 (毫秒)"
                echo "用法: $0 burst <持续时间ms> [p值] [时间槽ms]"
                exit 1
            fi
            set_burst_duration_network $INTERFACE $2 $3 $4
            ;;
        "status")
            show_network_status "$INTERFACE"
            ;;
        "test")
            test_connectivity $2 $3
            ;;
        "demo")
            echo "=========================================="
            echo "          演示不同突发持续时间"
            echo "=========================================="
            echo ""
            
            # 测试理想网络
            log_step "1. 测试理想网络条件"
            set_ideal_network $INTERFACE
            test_connectivity
            echo ""
            
            # 测试不同突发持续时间
            burst_durations=(10 50 100 200 500 1000)
            
            for duration in "${burst_durations[@]}"; do
                log_step "2. 测试突发持续时间: ${duration}ms"
                set_burst_duration_network $INTERFACE $duration
                test_connectivity
                echo ""
            done
            
            # 恢复理想网络
            log_step "3. 恢复理想网络条件"
            set_ideal_network $INTERFACE
            ;;
        *)
            echo "基于突发持续时间的网络设置脚本"
            echo ""
            echo "用法: $0 [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  clear                   清除网络设置"
            echo "  ideal                   设置理想网络条件"
            echo "  burst <持续时间ms>      设置基于突发持续时间的GE模型"
            echo "  status                  显示当前网络设置"
            echo "  test [目标] [包数]      测试网络连通性"
            echo "  demo                    演示不同突发持续时间"
            echo ""
            echo "参数说明:"
            echo "  <持续时间ms>: 平均突发持续时间 (毫秒)"
            echo "  [p值]: 状态G→B的转移概率 (默认0.01，即1%)"
            echo "  [时间槽ms]: 时间槽长度 (默认10.0ms，按照技术文档建议)"
            echo ""
            echo "示例:"
            echo "  $0 clear                           # 清除网络设置"
            echo "  $0 ideal                           # 设置理想网络"
            echo "  $0 burst 100                       # 设置100ms突发持续时间"
            echo "  $0 burst 200 0.01 10.0             # 设置200ms突发持续时间，p=0.01，时间槽=10ms"
            echo "  $0 status                          # 查看当前设置"
            echo "  $0 test 192.168.31.1 20           # 测试连通性"
            echo "  $0 demo                            # 演示不同突发持续时间"
            echo ""
            echo "科学意义:"
            echo "  - 直接考验IKEv2协议的超时和重传机制"
            echo "  - 揭示协议层面的深层脆弱性"
            echo "  - 回答核心问题: '网络中断多长时间，IPsec连接会失败？'"
            ;;
    esac
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 