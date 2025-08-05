#!/bin/bash

# 简化测试脚本 - 验证修正后的脚本是否正常工作
# 用于快速测试网络条件和连接建立

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 获取默认网络接口
get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# 清理网络条件
cleanup_network() {
    local interface=$1
    log_info "清理网络条件..."
    sudo tc qdisc del dev $interface root 2>/dev/null || true
    log_success "网络条件已清理"
}

# 设置网络条件
setup_network_condition() {
    local interface=$1
    local delay=$2
    local loss=$3
    
    log_info "设置网络条件: 延迟=${delay}ms, 丢包率=${loss}%"
    
    if [[ $delay -gt 0 ]] && [[ $loss -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem delay ${delay}ms loss ${loss}%
    elif [[ $delay -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem delay ${delay}ms
    elif [[ $loss -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem loss ${loss}%
    fi
    
    log_success "网络条件设置完成"
}

# 测试连接建立
test_connection() {
    local conn_name=$1
    local timeout_seconds=${2:-30}
    
    log_info "测试连接: $conn_name (超时: ${timeout_seconds}s)"
    
    # 清理现有连接
    sudo swanctl --terminate --ike $conn_name 2>/dev/null || true
    sleep 2
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动连接（带超时）
    if timeout $timeout_seconds sudo swanctl --initiate --ike $conn_name >/dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc)
        
        # 检查连接状态
        if sudo swanctl --list-sas | grep -q "$conn_name"; then
            log_success "连接建立成功，耗时: ${duration}ms"
            return 0
        else
            log_error "连接建立失败"
            return 1
        fi
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "连接建立超时"
        else
            log_error "连接建立失败"
        fi
        return 1
    fi
}

# 主函数
main() {
    check_root
    
    local conn_name=${1:-"net-net"}
    local interface=$(get_default_interface)
    
    log_info "=== 简化测试脚本 ==="
    log_info "网络接口: $interface"
    log_info "连接名称: $conn_name"
    echo ""
    
    # 检查连接是否存在
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接 '$conn_name' 不存在，请检查配置"
        log_info "可用的连接:"
        sudo swanctl --list-conns | grep -E "^[[:space:]]*[^[:space:]]+" | head -10
        exit 1
    fi
    
    # 测试场景
    local scenarios=(
        "正常网络:0:0"
        "轻微延迟:50:0"
        "轻微丢包:0:5"
        "中等丢包:0:15"
    )
    
    local total_tests=0
    local success_count=0
    
    for scenario in "${scenarios[@]}"; do
        total_tests=$((total_tests + 1))
        
        IFS=':' read -r name delay loss <<< "$scenario"
        log_info "=== 测试 $total_tests: $name ==="
        
        # 清理网络条件
        cleanup_network $interface
        
        # 设置网络条件
        setup_network_condition $interface $delay $loss
        
        # 测试连接
        if test_connection $conn_name 30; then
            success_count=$((success_count + 1))
            log_success "测试 $total_tests 成功"
        else
            log_error "测试 $total_tests 失败"
        fi
        
        # 清理连接
        sudo swanctl --terminate --ike $conn_name >/dev/null 2>&1 || true
        sleep 2
        
        echo ""
    done
    
    # 清理网络条件
    cleanup_network $interface
    
    # 输出总结
    log_info "=== 测试总结 ==="
    log_info "总测试数: $total_tests"
    log_info "成功数: $success_count"
    log_info "失败数: $((total_tests - success_count))"
    if [[ $total_tests -gt 0 ]]; then
        local success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
        log_info "成功率: ${success_rate}%"
    else
        log_info "成功率: 0%"
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 