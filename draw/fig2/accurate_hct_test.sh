#!/bin/bash

# 准确的HCT测试脚本
# 专门用于测量握手完成时间

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# 等待连接建立
wait_for_connection() {
    local conn_name=$1
    local timeout=$2
    local start_time=$(date +%s)
    
    while true; do
        if sudo swanctl --list-sas | grep -q "$conn_name.*ESTABLISHED"; then
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        
        sleep 0.1  # 更频繁的检查
    done
}

# 计算HCT
calculate_hct() {
    local start_time=$1
    local end_time=$2
    echo "scale=3; $end_time - $start_time" | bc
}

# 执行单次HCT测试
perform_hct_test() {
    local conn_name=$1
    local test_num=$2
    
    log_info "测试 $test_num: 准备连接 '$conn_name'"
    
    # 确保连接完全断开
    sudo swanctl --terminate --child "$conn_name" >/dev/null 2>&1 || true
    sleep 3  # 等待连接完全断开
    
    # 检查连接是否已断开（允许一些时间）
    for i in {1..10}; do
        if ! sudo swanctl --list-sas | grep -q "$conn_name.*ESTABLISHED"; then
            break
        fi
        sleep 0.5
    done
    
    # 最终检查
    if sudo swanctl --list-sas | grep -q "$conn_name.*ESTABLISHED"; then
        log_error "测试 $test_num: 连接未能完全断开"
        return 1
    fi
    
    log_info "测试 $test_num: 启动连接"
    
    # 记录精确的开始时间
    local start_time=$(date +%s.%N)
    
    # 启动连接
    if ! sudo swanctl --initiate --child "$conn_name" >/dev/null 2>&1; then
        log_error "测试 $test_num: 连接启动失败"
        return 1
    fi
    
    # 等待连接建立
    if wait_for_connection "$conn_name" 30; then
        local end_time=$(date +%s.%N)
        local hct=$(calculate_hct "$start_time" "$end_time")
        
        log_success "测试 $test_num: HCT = ${hct}s"
        echo "$hct"
        return 0
    else
        log_error "测试 $test_num: 连接超时"
        return 1
    fi
}

# 主函数
main() {
    local conn_name="net-net"
    local test_count=5
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--connection)
                conn_name="$2"
                shift 2
                ;;
            -n|--tests)
                test_count="$2"
                shift 2
                ;;
            -h|--help)
                echo "用法: $0 [-c CONNECTION] [-n COUNT]"
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "需要root权限"
        exit 1
    fi
    
    # 检查连接配置
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接配置 '$conn_name' 不存在"
        exit 1
    fi
    
    log_info "开始准确HCT测试"
    log_info "连接名称: $conn_name"
    log_info "测试次数: $test_count"
    echo ""
    
    # 执行测试
    local hct_values=()
    local success_count=0
    
    for ((i=1; i<=test_count; i++)); do
        if hct=$(perform_hct_test "$conn_name" "$i"); then
            hct_values+=("$hct")
            ((success_count++))
        fi
        
        echo ""
    done
    
    # 计算统计
    if [[ $success_count -gt 0 ]]; then
        echo "=== HCT测试结果 ==="
        echo "成功测试数: $success_count/$test_count"
        echo ""
        
        # 计算统计值
        local hct_sum=0
        local hct_min=${hct_values[0]}
        local hct_max=${hct_values[0]}
        
        for hct in "${hct_values[@]}"; do
            hct_sum=$(echo "$hct_sum + $hct" | bc)
            if (( $(echo "$hct < $hct_min" | bc -l) )); then
                hct_min=$hct
            fi
            if (( $(echo "$hct > $hct_max" | bc -l) )); then
                hct_max=$hct
            fi
        done
        
        local hct_mean=$(echo "scale=3; $hct_sum / $success_count" | bc)
        
        echo "HCT统计:"
        echo "  平均值: ${hct_mean}s"
        echo "  最小值: ${hct_min}s"
        echo "  最大值: ${hct_max}s"
        echo ""
        
        echo "详细HCT值:"
        for ((i=0; i<success_count; i++)); do
            echo "  测试 $((i+1)): ${hct_values[i]}s"
        done
    else
        log_error "所有测试都失败了"
        exit 1
    fi
}

main "$@" 