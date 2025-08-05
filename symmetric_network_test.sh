#!/bin/bash

# 对称网络条件测试脚本
# 自动在本机和对端设置相同的网络条件，确保测试严谨性

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

# 检查SSH连接
check_ssh_connection() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    
    log_info "检查SSH连接到 $remote_user@$remote_host..."
    
    # 使用sshpass检查连接
    if ! command -v sshpass >/dev/null 2>&1; then
        log_error "请安装sshpass: sudo apt-get install sshpass"
        exit 1
    fi
    
    if sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$remote_user@$remote_host" "echo 'SSH连接成功'" >/dev/null 2>&1; then
        log_success "SSH连接正常"
        return 0
    else
        log_error "SSH连接失败，请检查主机地址、用户名和密码"
        return 1
    fi
}

# 在远程主机执行命令
execute_remote_command() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    local command=$4
    
    # 使用 -S 选项让 sudo 从标准输入读取密码
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "echo '$remote_pass' | sudo -S $command"
}

# 获取远程主机的网络接口
get_remote_interface() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    
    # 获取网络接口不需要sudo权限
    sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "$remote_user@$remote_host" "ip route | grep default | awk '{print \$5}' | head -1"
}

# 清理网络条件
cleanup_network() {
    local interface=$1
    log_info "清理本机网络条件..."
    sudo tc qdisc del dev $interface root 2>/dev/null || true
    log_success "本机网络条件已清理"
}

# 清理远程网络条件
cleanup_remote_network() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    local remote_interface=$4
    
    log_info "清理对端网络条件..."
    execute_remote_command "$remote_host" "$remote_user" "$remote_pass" "tc qdisc del dev $remote_interface root 2>/dev/null || true"
    log_success "对端网络条件已清理"
}

# 设置网络条件
setup_network_condition() {
    local interface=$1
    local condition_type=$2
    local value=$3
    
    log_info "设置本机网络条件: $condition_type = $value"
    
    case $condition_type in
        "loss")
            sudo tc qdisc add dev $interface root netem loss $value%
            ;;
        "delay")
            sudo tc qdisc add dev $interface root netem delay ${value}ms
            ;;
        "bandwidth")
            sudo tc qdisc add dev $interface root tbf rate $value burst 32kbit latency 400ms
            ;;
        "corruption")
            sudo tc qdisc add dev $interface root netem corrupt $value%
            ;;
        "duplication")
            sudo tc qdisc add dev $interface root netem duplicate $value%
            ;;
        "reordering")
            sudo tc qdisc add dev $interface root netem delay 10ms reorder 25% 50%
            ;;
        "combined")
            # 组合条件：延迟+丢包
            IFS='+' read -r delay_val loss_val <<< "$value"
            sudo tc qdisc add dev $interface root netem delay ${delay_val}ms loss ${loss_val}%
            ;;
        *)
            log_error "不支持的网络条件类型: $condition_type"
            exit 1
            ;;
    esac
    
    log_success "本机网络条件设置完成"
}

# 设置远程网络条件
setup_remote_network_condition() {
    local remote_host=$1
    local remote_user=$2
    local remote_pass=$3
    local remote_interface=$4
    local condition_type=$5
    local value=$6
    
    log_info "设置对端网络条件: $condition_type = $value"
    
    local remote_command=""
    case $condition_type in
        "loss")
            remote_command="tc qdisc add dev $remote_interface root netem loss $value%"
            ;;
        "delay")
            remote_command="tc qdisc add dev $remote_interface root netem delay ${value}ms"
            ;;
        "bandwidth")
            remote_command="tc qdisc add dev $remote_interface root tbf rate $value burst 32kbit latency 400ms"
            ;;
        "corruption")
            remote_command="tc qdisc add dev $remote_interface root netem corrupt $value%"
            ;;
        "duplication")
            remote_command="tc qdisc add dev $remote_interface root netem duplicate $value%"
            ;;
        "reordering")
            remote_command="tc qdisc add dev $remote_interface root netem delay 10ms reorder 25% 50%"
            ;;
        "combined")
            # 组合条件：延迟+丢包
            IFS='+' read -r delay_val loss_val <<< "$value"
            remote_command="tc qdisc add dev $remote_interface root netem delay ${delay_val}ms loss ${loss_val}%"
            ;;
        *)
            log_error "不支持的网络条件类型: $condition_type"
            exit 1
            ;;
    esac
    
    execute_remote_command "$remote_host" "$remote_user" "$remote_pass" "$remote_command"
    log_success "对端网络条件设置完成"
}

# 显示网络条件
show_network_status() {
    local interface=$1
    local remote_host=$2
    local remote_user=$3
    local remote_pass=$4
    local remote_interface=$5
    
    log_info "=== 当前网络条件 ==="
    echo "本机 ($interface):"
    sudo tc qdisc show dev $interface | grep -E "(netem|tbf)" || echo "  无特殊网络条件"
    
    echo ""
    echo "对端 ($remote_host:$remote_interface):"
    execute_remote_command "$remote_host" "$remote_user" "$remote_pass" "tc qdisc show dev $remote_interface | grep -E '(netem|tbf)'" || echo "  无特殊网络条件"
    echo ""
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

# 运行测试场景
run_test_scenario() {
    local conn_name=$1
    local remote_host=$2
    local remote_user=$3
    local remote_pass=$4
    local interface=$5
    local remote_interface=$6
    local condition_type=$7
    local value=$8
    local scenario_name=$9
    local test_count=${10:-5}
    local timeout_seconds=${11:-30}
    
    log_info "=== 测试场景: $scenario_name ==="
    log_info "网络条件: $condition_type = $value"
    log_info "测试次数: $test_count"
    echo ""
    
    # 清理现有网络条件
    cleanup_network $interface
    cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass" "$remote_interface"
    
    # 设置对称网络条件
    if [[ "$condition_type" != "normal" ]]; then
        setup_network_condition $interface $condition_type $value
        setup_remote_network_condition "$remote_host" "$remote_user" "$remote_pass" "$remote_interface" $condition_type $value
    fi
    
    # 显示网络条件
    show_network_status $interface "$remote_host" "$remote_user" "$remote_pass" "$remote_interface"
    
    # 执行测试
    local success_count=0
    local total_duration=0
    
    for ((i=1; i<=$test_count; i++)); do
        echo "测试 $i/$test_count:"
        if test_connection $conn_name $timeout_seconds; then
            success_count=$((success_count + 1))
        fi
        
        # 清理连接
        sudo swanctl --terminate --ike $conn_name >/dev/null 2>&1 || true
        sleep 2
        echo ""
    done
    
    # 计算结果
    local success_rate=0
    if [[ $test_count -gt 0 ]]; then
        success_rate=$(echo "scale=2; $success_count * 100 / $test_count" | bc)
    fi
    
    log_info "=== 场景结果: $scenario_name ==="
    log_info "成功次数: $success_count/$test_count"
    log_info "成功率: ${success_rate}%"
    echo ""
    
    # 记录结果
    echo "$scenario_name,$condition_type,$value,$test_count,$success_count,$success_rate" >> "/tmp/symmetric_test_results.txt"
}

# 显示帮助信息
show_help() {
    cat << EOF
对称网络条件测试脚本

用法: $0 [选项] <连接名称>

选项:
    -r, --remote <host>       对端主机IP地址
    -u, --user <user>         对端用户名
    -p, --pass <password>     对端密码
    -i, --interface <接口>    本机网络接口 (默认: 自动检测)
    -n, --num <次数>          每个场景的测试次数 (默认: 5)
    -t, --timeout <秒>        连接超时时间 (默认: 30)
    -c, --cleanup             清理网络条件
    -h, --help               显示此帮助信息

示例:
    $0 -r 192.168.31.135 -u sun -p 123456 net-net
    $0 -r 192.168.31.135 -u sun -p 123456 -n 10 -t 60 net-net
    $0 -c

说明:
    - 脚本会自动在本机和对端设置相同的网络条件
    - 确保测试的严谨性和对称性
    - 支持多种网络条件：延迟、丢包、带宽限制等
    - 自动生成测试报告

EOF
}

# 主函数
main() {
    check_root
    
    local conn_name=""
    local remote_host=""
    local remote_user=""
    local remote_pass=""
    local interface=""
    local test_count=5
    local timeout_seconds=30
    local cleanup_mode=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--remote)
                remote_host="$2"
                shift 2
                ;;
            -u|--user)
                remote_user="$2"
                shift 2
                ;;
            -p|--pass)
                remote_pass="$2"
                shift 2
                ;;
            -i|--interface)
                interface="$2"
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
            -c|--cleanup)
                cleanup_mode=true
                shift
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
    
    # 获取默认网络接口
    if [[ -z "$interface" ]]; then
        interface=$(get_default_interface)
        log_info "使用默认网络接口: $interface"
    fi
    
    # 清理模式
    if [[ "$cleanup_mode" == true ]]; then
        cleanup_network $interface
        if [[ -n "$remote_host" && -n "$remote_user" && -n "$remote_pass" ]]; then
            local remote_interface=$(get_remote_interface "$remote_host" "$remote_user" "$remote_pass")
            cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass" "$remote_interface"
        fi
        exit 0
    fi
    
    # 检查必要参数
    if [[ -z "$conn_name" ]]; then
        log_error "请指定连接名称"
        show_help
        exit 1
    fi
    
    if [[ -z "$remote_host" || -z "$remote_user" || -z "$remote_pass" ]]; then
        log_error "请指定对端主机信息 (-r, -u, -p)"
        show_help
        exit 1
    fi
    
    log_info "=== 对称网络条件测试 ==="
    log_info "本机接口: $interface"
    log_info "对端主机: $remote_user@$remote_host"
    log_info "连接名称: $conn_name"
    log_info "测试次数: $test_count"
    log_info "连接超时: ${timeout_seconds}s"
    echo ""
    
    # 检查SSH连接
    if ! check_ssh_connection "$remote_host" "$remote_user" "$remote_pass"; then
        exit 1
    fi
    
    # 获取远程接口
    local remote_interface=$(get_remote_interface "$remote_host" "$remote_user" "$remote_pass")
    log_info "对端接口: $remote_interface"
    echo ""
    
    # 检查连接是否存在
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接 '$conn_name' 不存在，请检查配置"
        exit 1
    fi
    
    # 创建结果文件
    echo "场景名称,条件类型,条件值,测试次数,成功次数,成功率" > "/tmp/symmetric_test_results.txt"
    
    # 定义测试场景
    local scenarios=(
        "正常网络:normal:0"
        "轻微延迟:delay:50"
        "中等延迟:delay:200"
        "严重延迟:delay:500"
        "轻微丢包:loss:5"
        "中等丢包:loss:15"
        "严重丢包:loss:30"
        "延迟+丢包:combined:100+10"
        "带宽限制:bandwidth:1mbit"
    )
    
    # 执行测试场景
    for scenario in "${scenarios[@]}"; do
        IFS=':' read -r name condition_type value <<< "$scenario"
        run_test_scenario "$conn_name" "$remote_host" "$remote_user" "$remote_pass" "$interface" "$remote_interface" "$condition_type" "$value" "$name" "$test_count" "$timeout_seconds"
    done
    
    # 清理网络条件
    cleanup_network $interface
    cleanup_remote_network "$remote_host" "$remote_user" "$remote_pass" "$remote_interface"
    
    # 生成报告
    local report_file="symmetric_test_report_$(date +%Y%m%d_%H%M%S).txt"
    cat > $report_file << EOF
strongSwan 对称网络条件测试报告
生成时间: $(date)
测试环境: 
- 本机: $(hostname) ($interface)
- 对端: $remote_user@$remote_host ($remote_interface)
- 连接: $conn_name

测试配置:
- 每个场景测试次数: $test_count
- 连接超时: ${timeout_seconds}s
- 网络条件: 双向对称设置

测试结果:
$(cat /tmp/symmetric_test_results.txt)

说明:
- 所有网络条件都在本机和对端同时设置
- 确保了测试的严谨性和对称性
- 结果更能反映真实网络环境下的性能
EOF
    
    log_success "对称网络条件测试完成！"
    log_success "报告已保存到: $report_file"
    
    # 显示简要结果
    echo ""
    echo "=== 测试结果汇总 ==="
    tail -n +2 /tmp/symmetric_test_results.txt | while IFS=',' read -r name condition_type value count success rate; do
        printf "%-15s: 成功率 %-6s (%s/%s)\n" "$name" "${rate}%" "$success" "$count"
    done
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 