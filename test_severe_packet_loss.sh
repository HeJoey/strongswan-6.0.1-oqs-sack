#!/bin/bash

# 严重丢包测试脚本
# 专门测试30%丢包率下的连接性能

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

# 设置严重丢包条件
setup_severe_packet_loss() {
    local interface=$1
    local loss_rate=$2
    
    log_info "设置严重丢包条件: $loss_rate% 丢包率"
    sudo tc qdisc add dev $interface root netem loss $loss_rate%
    log_success "严重丢包条件设置完成"
    
    # 显示当前网络条件
    log_info "当前网络条件:"
    sudo tc qdisc show dev $interface | grep netem
}

# 设置对端网络条件
setup_remote_packet_loss() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    local loss_rate=$4
    
    log_info "设置对端严重丢包条件: $loss_rate% 丢包率"
    
    # 获取对端网络接口
    local remote_interface=$(sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "ip route | grep default | awk '{print \$5}' | head -1")
    
    # 清理对端网络条件
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "echo '$remote_pass' | sudo -S tc qdisc del dev $remote_interface root 2>/dev/null || true"
    
    # 设置对端丢包条件
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "echo '$remote_pass' | sudo -S tc qdisc add dev $remote_interface root netem loss $loss_rate%"
    
    log_success "对端严重丢包条件设置完成"
    
    # 显示对端网络条件
    log_info "对端网络条件:"
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "echo '$remote_pass' | sudo -S tc qdisc show dev $remote_interface | grep netem"
}

# 清理对端网络条件
cleanup_remote_network() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    
    log_info "清理对端网络条件..."
    local remote_interface=$(sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "ip route | grep default | awk '{print \$5}' | head -1")
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "echo '$remote_pass' | sudo -S tc qdisc del dev $remote_interface root 2>/dev/null || true"
    log_success "对端网络条件已清理"
}

# 测试连接建立
test_connection() {
    local conn_name=$1
    local timeout_seconds=${2:-60}
    
    log_info "测试连接: $conn_name (超时: ${timeout_seconds}s)"
    
    # 清理现有连接
    sudo swanctl --terminate --ike $conn_name 2>/dev/null || true
    sleep 2
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动连接（带超时）
    timeout $timeout_seconds sudo swanctl --initiate --ike $conn_name >/dev/null 2>&1 &
    local swanctl_pid=$!
    
    # 等待连接完成或超时
    local connection_success=false
    local check_interval=2
    local elapsed=0
    
    while [[ $elapsed -lt $timeout_seconds ]]; do
        # 检查swanctl进程是否还在运行
        if ! kill -0 $swanctl_pid 2>/dev/null; then
            # 进程已结束，检查连接状态
            if sudo swanctl --list-sas | grep -q "$conn_name"; then
                connection_success=true
                break
            else
                break
            fi
        fi
        
        # 检查是否已经建立连接
        if sudo swanctl --list-sas | grep -q "$conn_name"; then
            connection_success=true
            # 终止swanctl进程
            kill $swanctl_pid 2>/dev/null || true
            break
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    # 如果超时，强制终止swanctl进程
    if kill -0 $swanctl_pid 2>/dev/null; then
        kill -9 $swanctl_pid 2>/dev/null || true
        wait $swanctl_pid 2>/dev/null || true
    fi
    
    local end_time=$(date +%s.%N)
    # 使用awk计算避免bc的字符编码问题
    local duration=$(awk "BEGIN {printf \"%.3f\", ($end_time - $start_time) * 1000}")
    
    if [[ "$connection_success" == true ]]; then
        log_success "连接建立成功，耗时: ${duration}ms"
        return 0
    else
        # 检查是否超时
        local timeout_ms=$(awk "BEGIN {printf \"%.0f\", $timeout_seconds * 1000}")
        if (( $(awk "BEGIN {print ($duration >= $timeout_ms)}") )); then
            log_error "连接建立超时 (${timeout_seconds}s)"
            return 2  # 返回2表示超时
        else
            log_error "连接建立失败，耗时: ${duration}ms"
            return 1  # 返回1表示失败
        fi
    fi
}

# 运行严重丢包测试
run_severe_packet_loss_test() {
    local conn_name=$1
    local remote_host=$2
    local remote_user=$3
    local remote_pass=$4
    local interface=$5
    local loss_rate=$6
    local test_count=$7
    local timeout_seconds=$8
    
    log_info "=== 严重丢包测试 ==="
    log_info "丢包率: $loss_rate%"
    log_info "测试次数: $test_count"
    log_info "连接超时: ${timeout_seconds}s"
    echo ""
    
    # 清理现有网络条件
    cleanup_network $interface
    cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass"
    
    # 设置严重丢包条件
    setup_severe_packet_loss $interface $loss_rate
    setup_remote_packet_loss "$remote_host" "$remote_user" "$remote_pass" $loss_rate
    
    echo ""
    log_info "开始连接测试..."
    echo ""
    
    # 执行测试
    local success_count=0
    local timeout_count=0
    local failed_count=0
    local total_duration=0
    local success_durations=()
    local timeout_durations=()
    local failed_durations=()
    
    for ((i=1; i<=$test_count; i++)); do
        echo "=== 测试 $i/$test_count ==="
        
        # 记录开始时间
        local start_time=$(date +%s.%N)
        
        # 调用test_connection函数
        test_connection $conn_name $timeout_seconds
        local result=$?
        
        # 计算持续时间
        local end_time=$(date +%s.%N)
        local duration=$(awk "BEGIN {printf \"%.3f\", ($end_time - $start_time) * 1000}")
        
        case $result in
            0)  # 成功
                success_count=$((success_count + 1))
                success_durations+=("$duration")
                total_duration=$(awk "BEGIN {printf \"%.3f\", $total_duration + $duration}")
                log_success "第 $i 次测试成功"
                ;;
            2)  # 超时
                timeout_count=$((timeout_count + 1))
                local timeout_ms=$(awk "BEGIN {printf \"%.0f\", $timeout_seconds * 1000}")
                timeout_durations+=("$timeout_ms")
                log_warning "第 $i 次测试超时"
                ;;
            1)  # 失败
                failed_count=$((failed_count + 1))
                failed_durations+=("$duration")
                log_warning "第 $i 次测试失败"
                ;;
        esac
        
        # 强制清理连接和进程
        sudo swanctl --terminate --ike $conn_name >/dev/null 2>&1 || true
        sudo pkill -f "swanctl.*$conn_name" 2>/dev/null || true
        sleep 3
        echo ""
    done
    
    # 计算统计结果
    local success_rate=0
    local avg_duration=0
    
    if [[ $test_count -gt 0 ]]; then
        success_rate=$(awk "BEGIN {printf \"%.2f\", $success_count * 100 / $test_count}")
    fi
    
    if [[ $success_count -gt 0 ]]; then
        avg_duration=$(awk "BEGIN {printf \"%.3f\", $total_duration / $success_count}")
    fi
    
    # 输出结果
    log_info "=== 严重丢包测试结果 ==="
    log_info "丢包率: $loss_rate%"
    log_info "总测试次数: $test_count"
    log_info "成功次数: $success_count"
    log_info "超时次数: $timeout_count"
    log_info "失败次数: $failed_count"
    log_info "成功率: ${success_rate}%"
    
    if [[ $success_count -gt 0 ]]; then
        log_info "平均连接时间: ${avg_duration}ms"
        log_info "成功连接时间详情:"
        for ((i=0; i<${#success_durations[@]}; i++)); do
            echo "  成功测试 $((i+1)): ${success_durations[i]}ms"
        done
    fi
    
    if [[ $timeout_count -gt 0 ]]; then
        log_info "超时测试详情:"
        for ((i=0; i<${#timeout_durations[@]}; i++)); do
            echo "  超时测试 $((i+1)): ${timeout_durations[i]}ms (达到超时限制)"
        done
    fi
    
    if [[ $failed_count -gt 0 ]]; then
        log_info "失败测试详情:"
        for ((i=0; i<${#failed_durations[@]}; i++)); do
            echo "  失败测试 $((i+1)): ${failed_durations[i]}ms"
        done
    fi
    
    # 保存结果到文件
    local result_file="severe_packet_loss_test_$(date +%Y%m%d_%H%M%S).txt"
    cat > $result_file << EOF
严重丢包测试结果报告
生成时间: $(date)
测试环境: 
- 本机: $(hostname) ($interface)
- 对端: $remote_user@$remote_host
- 连接: $conn_name

测试配置:
- 丢包率: $loss_rate% (双向对称设置)
- 测试次数: $test_count
- 连接超时: ${timeout_seconds}s

测试结果:
- 成功次数: $success_count
- 超时次数: $timeout_count
- 失败次数: $failed_count
- 成功率: ${success_rate}%
- 平均连接时间: ${avg_duration}ms

成功连接时间详情:
$(for ((i=0; i<${#success_durations[@]}; i++)); do echo "成功测试 $((i+1)): ${success_durations[i]}ms"; done)

超时测试详情:
$(for ((i=0; i<${#timeout_durations[@]}; i++)); do echo "超时测试 $((i+1)): ${timeout_durations[i]}ms (达到超时限制)"; done)

失败测试详情:
$(for ((i=0; i<${#failed_durations[@]}; i++)); do echo "失败测试 $((i+1)): ${failed_durations[i]}ms"; done)

分析:
- 在 $loss_rate% 丢包率下，IPsec连接成功率为 ${success_rate}%
- 分片重传机制在严重丢包环境下的表现
- 连接建立平均耗时 ${avg_duration}ms
EOF
    
    log_success "测试报告已保存到: $result_file"
}

# 主函数
main() {
    check_root
    
    local conn_name="net-net"
    local remote_host="192.168.31.135"
    local remote_user="sun"
    local remote_pass="123456"
    local loss_rate=30
    local test_count=5
    local timeout_seconds=90
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--conn)
                conn_name="$2"
                shift 2
                ;;
            -l|--loss)
                loss_rate="$2"
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
            --cleanup)
                local interface=$(get_default_interface)
                cleanup_network $interface
                cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass"
                exit 0
                ;;
            -h|--help)
                echo "严重丢包测试脚本"
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  -c, --conn <名称>     连接名称 (默认: net-net)"
                echo "  -l, --loss <百分比>   丢包率 (默认: 30)"
                echo "  -n, --num <次数>      测试次数 (默认: 5)"
                echo "  -t, --timeout <秒>    超时时间 (默认: 90)"
                echo "  --cleanup            清理网络条件"
                echo "  -h, --help           显示帮助"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done
    
    local interface=$(get_default_interface)
    
    log_info "=== 严重丢包测试配置 ==="
    log_info "本机接口: $interface"
    log_info "对端主机: $remote_user@$remote_host"
    log_info "连接名称: $conn_name"
    log_info "丢包率: $loss_rate%"
    log_info "测试次数: $test_count"
    log_info "连接超时: ${timeout_seconds}s"
    echo ""
    
    # 检查SSH连接
    if ! command -v sshpass >/dev/null 2>&1; then
        log_error "请安装sshpass: sudo apt-get install sshpass"
        exit 1
    fi
    
    if sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$remote_user@$remote_host" "echo 'SSH连接成功'" >/dev/null 2>&1; then
        log_success "SSH连接正常"
    else
        log_error "SSH连接失败，请检查对端信息"
        exit 1
    fi
    
    # 检查连接是否存在
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接 '$conn_name' 不存在，请检查配置"
        exit 1
    fi
    
    # 运行严重丢包测试
    run_severe_packet_loss_test "$conn_name" "$remote_host" "$remote_user" "$remote_pass" "$interface" "$loss_rate" "$test_count" "$timeout_seconds"
    
    # 清理网络条件
    cleanup_network $interface
    cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass"
    
    log_success "严重丢包测试完成！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 