#!/bin/bash

# strongSwan 分片重传效果测试脚本
# 用于测试全部重传和选择分片重传在限制网络上的连接效果

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查网络接口
check_interface() {
    local interface=$1
    if ! ip link show $interface >/dev/null 2>&1; then
        log_error "网络接口 $interface 不存在"
        exit 1
    fi
}

# 清理网络条件
cleanup_network() {
    local interface=$1
    log_info "清理网络条件..."
    tc qdisc del dev $interface root 2>/dev/null || true
    log_success "网络条件已清理"
}

# 设置网络条件
setup_network_condition() {
    local interface=$1
    local delay=$2
    local loss=$3
    
    log_info "设置网络条件: 延迟=${delay}ms, 丢包率=${loss}%"
    
    # 清理现有条件
    cleanup_network $interface
    
    # 设置新的网络条件
    if [[ $delay -gt 0 ]] && [[ $loss -gt 0 ]]; then
        tc qdisc add dev $interface root netem delay ${delay}ms loss ${loss}%
    elif [[ $delay -gt 0 ]]; then
        tc qdisc add dev $interface root netem delay ${delay}ms
    elif [[ $loss -gt 0 ]]; then
        tc qdisc add dev $interface root netem loss ${loss}%
    else
        log_warning "延迟和丢包率都为0，使用正常网络条件"
    fi
    
    log_success "网络条件设置完成"
}

# 重启strongSwan服务
restart_strongswan() {
    log_info "重启strongSwan服务..."
    systemctl restart strongswan
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet strongswan; then
        log_success "strongSwan服务重启成功"
    else
        log_error "strongSwan服务重启失败"
        exit 1
    fi
}

# 带超时的连接测试
test_single_connection() {
    local conn_name=$1
    local test_num=$2
    local timeout_seconds=$3
    
    log_info "测试 $test_num: 启动连接 $conn_name (超时: ${timeout_seconds}s)"
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动连接（带超时）
    local result
    local connection_status="TIMEOUT"
    local retransmission_count=0
    
    # 使用timeout命令限制连接时间
    if timeout $timeout_seconds swanctl --initiate --ike $conn_name >/dev/null 2>&1; then
        result="SUCCESS"
        connection_status="UP"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            result="TIMEOUT"
            connection_status="TIMEOUT"
        else
            result="FAILED"
            connection_status="DOWN"
        fi
    fi
    
    # 记录结束时间
    local end_time=$(date +%s.%N)
    
    # 计算连接时间（毫秒）
    local duration=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc)
    
    # 检查连接状态
    local final_status="DOWN"
    if swanctl --list-conns | grep -q "$conn_name.*INSTALLED"; then
        final_status="UP"
    fi
    
    # 统计重传次数（通过日志分析）
    local log_file="/var/log/strongswan.log"
    if [[ -f $log_file ]]; then
        # 统计最近的重传日志
        retransmission_count=$(tail -100 $log_file | grep -c "retransmit" || echo "0")
    fi
    
    # 输出结果
    if [[ $result == "SUCCESS" ]] && [[ $final_status == "UP" ]]; then
        # 使用bc进行浮点数比较
        if (( $(echo "$duration < 1000" | bc -l) )); then
            log_success "测试 $test_num: 一次连接成功，耗时 ${duration}ms"
            echo "$test_num,SUCCESS_ONE_SHOT,${duration},$final_status,0"
        else
            log_success "测试 $test_num: 重传连接成功，耗时 ${duration}ms (重传次数: $retransmission_count)"
            echo "$test_num,SUCCESS_RETRANSMIT,${duration},$final_status,$retransmission_count"
        fi
    elif [[ $result == "TIMEOUT" ]]; then
        log_error "测试 $test_num: 连接超时，耗时 ${duration}ms"
        echo "$test_num,TIMEOUT,${duration},$final_status,$retransmission_count"
    else
        log_error "测试 $test_num: 连接失败，耗时 ${duration}ms"
        echo "$test_num,FAILED,${duration},$final_status,$retransmission_count"
    fi
    
    # 断开连接
    swanctl --terminate --ike $conn_name >/dev/null 2>&1 || true
    sleep 1
}

# 分析测试结果
analyze_results() {
    local results_file=$1
    local total_tests=$2
    
    log_info "分析测试结果..."
    
    # 统计各种结果
    local success_one_shot=0
    local success_retransmit=0
    local failed_count=0
    local timeout_count=0
    local total_retransmissions=0
    
    # 统计连接时间
    local one_shot_times=()
    local retransmit_times=()
    local failed_times=()
    local timeout_times=()
    
    while IFS=',' read -r test_num result duration status retransmissions; do
        case $result in
            "SUCCESS_ONE_SHOT")
                success_one_shot=$((success_one_shot + 1))
                one_shot_times+=($duration)
                ;;
            "SUCCESS_RETRANSMIT")
                success_retransmit=$((success_retransmit + 1))
                retransmit_times+=($duration)
                total_retransmissions=$((total_retransmissions + retransmissions))
                ;;
            "FAILED")
                failed_count=$((failed_count + 1))
                failed_times+=($duration)
                ;;
            "TIMEOUT")
                timeout_count=$((timeout_count + 1))
                timeout_times+=($duration)
                ;;
        esac
    done < $results_file
    
    # 计算成功率
    local total_success=$((success_one_shot + success_retransmit))
    local success_rate=$(echo "scale=2; $total_success * 100 / $total_tests" | bc)
    local one_shot_rate=$(echo "scale=2; $success_one_shot * 100 / $total_tests" | bc)
    
    # 计算平均时间
    local avg_one_shot=0
    local avg_retransmit=0
    local avg_failed=0
    local avg_timeout=0
    
    if [[ ${#one_shot_times[@]} -gt 0 ]]; then
        local sum=0
        for time in "${one_shot_times[@]}"; do
            sum=$(echo "$sum + $time" | bc)
        done
        avg_one_shot=$(echo "scale=3; $sum / ${#one_shot_times[@]}" | bc)
    fi
    
    if [[ ${#retransmit_times[@]} -gt 0 ]]; then
        local sum=0
        for time in "${retransmit_times[@]}"; do
            sum=$(echo "$sum + $time" | bc)
        done
        avg_retransmit=$(echo "scale=3; $sum / ${#retransmit_times[@]}" | bc)
    fi
    
    if [[ ${#failed_times[@]} -gt 0 ]]; then
        local sum=0
        for time in "${failed_times[@]}"; do
            sum=$(echo "$sum + $time" | bc)
        done
        avg_failed=$(echo "scale=3; $sum / ${#failed_times[@]}" | bc)
    fi
    
    if [[ ${#timeout_times[@]} -gt 0 ]]; then
        local sum=0
        for time in "${timeout_times[@]}"; do
            sum=$(echo "$sum + $time" | bc)
        done
        avg_timeout=$(echo "scale=3; $sum / ${#timeout_times[@]}" | bc)
    fi
    
    # 输出统计结果
    echo ""
    echo "=== 测试结果统计 ==="
    echo "总测试次数: $total_tests"
    echo "一次连接成功: $success_one_shot (${one_shot_rate}%)"
    echo "重传连接成功: $success_retransmit"
    echo "连接失败: $failed_count"
    echo "连接超时: $timeout_count"
    echo "总体成功率: ${success_rate}%"
    echo ""
    echo "连接时间统计:"
    if [[ $success_one_shot -gt 0 ]]; then
        echo "一次成功平均时间: ${avg_one_shot}ms"
    fi
    if [[ $success_retransmit -gt 0 ]]; then
        echo "重传成功平均时间: ${avg_retransmit}ms"
        echo "平均重传次数: $(echo "scale=2; $total_retransmissions / $success_retransmit" | bc)"
    fi
    if [[ $failed_count -gt 0 ]]; then
        echo "失败连接平均时间: ${avg_failed}ms"
    fi
    if [[ $timeout_count -gt 0 ]]; then
        echo "超时连接平均时间: ${avg_timeout}ms"
    fi
    echo ""
    
    # 保存统计结果到文件
    local stats_file="test_stats_$(date +%Y%m%d_%H%M%S).txt"
    cat > $stats_file << EOF
strongSwan 分片重传测试统计报告
生成时间: $(date)
测试环境: $(uname -a)

测试配置:
- 网络接口: $INTERFACE
- 连接名称: $CONN_NAME
- 网络延迟: ${DELAY}ms
- 网络丢包率: ${LOSS}%
- 测试次数: $total_tests
- 连接超时: ${TIMEOUT}s

测试结果:
- 总测试次数: $total_tests
- 一次连接成功: $success_one_shot (${one_shot_rate}%)
- 重传连接成功: $success_retransmit
- 连接失败: $failed_count
- 连接超时: $timeout_count
- 总体成功率: ${success_rate}%

连接时间统计:
- 一次成功平均时间: ${avg_one_shot}ms
- 重传成功平均时间: ${avg_retransmit}ms
- 失败连接平均时间: ${avg_failed}ms
- 超时连接平均时间: ${avg_timeout}ms
- 平均重传次数: $(echo "scale=2; $total_retransmissions / $success_retransmit" | bc)

详细测试数据:
$(cat $results_file)
EOF
    
    log_success "统计报告已保存到: $stats_file"
}

# 显示帮助信息
show_help() {
    cat << EOF
strongSwan 分片重传效果测试脚本

用法: $0 [选项] <连接名称>

选项:
    -i, --interface <接口>    指定网络接口 (默认: 自动检测)
    -d, --delay <毫秒>        设置网络延迟 (默认: 0)
    -l, --loss <百分比>       设置丢包率 (默认: 0)
    -n, --num <次数>          测试次数 (默认: 100)
    -t, --timeout <秒>        连接超时时间 (默认: 30)
    -h, --help               显示此帮助信息

示例:
    $0 site-to-site
    $0 -i eth0 -d 100 -l 10 site-to-site
    $0 -d 200 -l 15 -n 50 -t 60 site-to-site

说明:
    - 脚本会自动重启strongSwan服务
    - 使用swanctl命令建立连接
    - 统计每次连接的时间
    - 区分一次成功和重传成功
    - 设置连接超时机制
    - 生成详细的测试报告

EOF
}

# 获取默认网络接口
get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    # 默认参数
    local interface=""
    local conn_name=""
    local delay=0
    local loss=0
    local test_count=100
    local timeout_seconds=30
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -d|--delay)
                delay="$2"
                shift 2
                ;;
            -l|--loss)
                loss="$2"
                shift 2
                ;;
            -n|--num)
                test_count="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout_seconds="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$conn_name" ]]; then
                    conn_name="$1"
                else
                    log_error "未知参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查必要参数
    if [[ -z "$conn_name" ]]; then
        log_error "请指定连接名称"
        show_help
        exit 1
    fi
    
    # 获取默认网络接口
    if [[ -z "$interface" ]]; then
        interface=$(get_default_interface)
        log_info "使用默认网络接口: $interface"
    fi
    
    # 检查网络接口
    check_interface $interface
    
    # 检查连接是否存在
    if ! swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接 '$conn_name' 不存在，请检查配置"
        log_info "可用的连接:"
        swanctl --list-conns | grep -E "^[[:space:]]*[^[:space:]]+" | head -10
        exit 1
    fi
    
    # 检查参数有效性
    if [[ ! $delay =~ ^[0-9]+$ ]] || [[ $delay -lt 0 ]]; then
        log_error "延迟参数无效: $delay"
        exit 1
    fi
    
    if [[ ! $loss =~ ^[0-9]+$ ]] || [[ $loss -lt 0 ]] || [[ $loss -gt 100 ]]; then
        log_error "丢包率参数无效: $loss (应为0-100)"
        exit 1
    fi
    
    if [[ ! $test_count =~ ^[0-9]+$ ]] || [[ $test_count -lt 1 ]]; then
        log_error "测试次数参数无效: $test_count"
        exit 1
    fi
    
    if [[ ! $timeout_seconds =~ ^[0-9]+$ ]] || [[ $timeout_seconds -lt 1 ]]; then
        log_error "超时参数无效: $timeout_seconds"
        exit 1
    fi
    
    # 保存参数到全局变量（用于报告）
    INTERFACE=$interface
    CONN_NAME=$conn_name
    DELAY=$delay
    LOSS=$loss
    TIMEOUT=$timeout_seconds
    
    log_info "=== 开始分片重传效果测试 ==="
    log_info "网络接口: $interface"
    log_info "连接名称: $conn_name"
    log_info "网络延迟: ${delay}ms"
    log_info "网络丢包率: ${loss}%"
    log_info "测试次数: $test_count"
    log_info "连接超时: ${timeout_seconds}s"
    echo ""
    
    # 设置网络条件
    setup_network_condition $interface $delay $loss
    
    # 重启strongSwan服务
    restart_strongswan
    
    # 创建结果文件
    local results_file="/tmp/fragment_test_results_$(date +%Y%m%d_%H%M%S).txt"
    echo "测试编号,结果,连接时间(ms),状态,重传次数" > $results_file
    
    # 开始测试
    log_info "开始执行 $test_count 次连接测试..."
    echo ""
    
    local success_one_shot=0
    local success_retransmit=0
    local failed_count=0
    local timeout_count=0
    
    for ((i=1; i<=$test_count; i++)); do
        # 执行单次测试
        local result=$(test_single_connection $conn_name $i $timeout_seconds)
        echo "$result" >> $results_file
        
        # 统计结果
        if echo "$result" | grep -q "SUCCESS_ONE_SHOT"; then
            success_one_shot=$((success_one_shot + 1))
        elif echo "$result" | grep -q "SUCCESS_RETRANSMIT"; then
            success_retransmit=$((success_retransmit + 1))
        elif echo "$result" | grep -q "TIMEOUT"; then
            timeout_count=$((timeout_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
        
        # 显示进度
        if [[ $((i % 10)) -eq 0 ]]; then
            local total_success=$((success_one_shot + success_retransmit))
            log_info "进度: $i/$test_count (一次成功: $success_one_shot, 重传成功: $success_retransmit, 失败: $failed_count, 超时: $timeout_count)"
        fi
        
        # 短暂等待
        sleep 0.5
    done
    
    echo ""
    log_info "测试完成！"
    
    # 分析结果
    analyze_results $results_file $test_count
    
    # 清理网络条件
    cleanup_network $interface
    
    log_success "测试完成，结果已保存"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 