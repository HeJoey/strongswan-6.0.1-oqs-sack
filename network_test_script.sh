#!/bin/bash

# strongSwan 分片重传网络测试脚本
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
    local condition_type=$2
    local value=$3
    
    log_info "设置网络条件: $condition_type = $value"
    
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
        *)
            log_error "不支持的网络条件类型: $condition_type"
            exit 1
            ;;
    esac
    
    log_success "网络条件设置完成"
}

# 测试连接建立
test_connection() {
    local test_name=$1
    local conn_name=$2
    local timeout_seconds=${3:-30}
    
    log_info "开始测试: $test_name"
    
    # 清理现有连接
    sudo swanctl --terminate --ike $conn_name 2>/dev/null || true
    sleep 2
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动连接（带超时）
    log_info "启动IPsec连接: $conn_name (超时: ${timeout_seconds}s)"
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

# 监控日志
monitor_logs() {
    local test_name=$1
    local log_file="/var/log/strongswan.log"
    
    log_info "监控日志文件: $log_file"
    
    # 创建临时日志文件
    local temp_log="/tmp/strongswan_test_${test_name}_$(date +%Y%m%d_%H%M%S).log"
    
    # 清空日志文件
    > $log_file
    
    # 启动日志监控
    tail -f $log_file > $temp_log &
    local tail_pid=$!
    
    echo $tail_pid
}

# 分析测试结果
analyze_results() {
    local test_name=$1
    local log_file=$2
    
    log_info "分析测试结果: $test_name"
    
    # 统计重传次数
    local total_retransmissions=$(grep -c "retransmit" $log_file || echo "0")
    local selective_retransmissions=$(grep -c "selective.*retransmission" $log_file || echo "0")
    local fragment_retransmissions=$(grep -c "fragment.*retransmission" $log_file || echo "0")
    
    # 统计分片相关日志
    local fragment_timeouts=$(grep -c "fragment.*timeout" $log_file || echo "0")
    local fragment_progress=$(grep -c "fragment.*progress" $log_file || echo "0")
    
    # 统计连接时间
    local connection_time=$(grep "connection.*established" $log_file | tail -1 | grep -o '[0-9]\+ms' || echo "N/A")
    
    echo "=== 测试结果: $test_name ==="
    echo "总重传次数: $total_retransmissions"
    echo "选择性重传次数: $selective_retransmissions"
    echo "分片重传次数: $fragment_retransmissions"
    echo "分片超时次数: $fragment_timeouts"
    echo "分片进度记录: $fragment_progress"
    echo "连接建立时间: $connection_time"
    echo ""
}

# 生成测试报告
generate_report() {
    local report_file="network_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "生成测试报告: $report_file"
    
    cat > $report_file << EOF
strongSwan 分片重传网络测试报告
生成时间: $(date)
测试环境: $(uname -a)

测试配置:
- 网络接口: $INTERFACE
- 测试连接: $CONN_NAME
- 测试次数: $TEST_COUNT

测试结果汇总:
$(cat /tmp/test_results_*.txt 2>/dev/null || echo "无测试结果")

详细日志:
$(cat /tmp/strongswan_test_*.log 2>/dev/null || echo "无详细日志")
EOF
    
    log_success "测试报告已生成: $report_file"
}

# 主测试函数
run_network_test() {
    local interface=$1
    local conn_name=$2
    local test_scenarios=("$@")
    
    log_info "开始网络条件测试"
    log_info "网络接口: $interface"
    log_info "连接名称: $conn_name"
    
    # 确保strongSwan服务运行
    systemctl is-active --quiet strongswan || {
        log_error "strongSwan服务未运行"
        exit 1
    }
    
    # 测试计数器
    local test_count=0
    local success_count=0
    
    # 遍历测试场景
    for scenario in "${test_scenarios[@]}"; do
        test_count=$((test_count + 1))
        
        # 解析测试场景
        IFS=':' read -r condition_type value <<< "$scenario"
        
        log_info "=== 测试 $test_count: $condition_type = $value ==="
        
        # 清理网络条件
        cleanup_network $interface
        
        # 设置网络条件
        setup_network_condition $interface $condition_type $value
        
        # 监控日志
        local tail_pid=$(monitor_logs "test_${test_count}")
        
        # 等待日志监控启动
        sleep 1
        
        # 测试连接
        if test_connection "测试 $test_count" $conn_name 30; then
            success_count=$((success_count + 1))
            log_success "测试 $test_count 成功"
        else
            log_error "测试 $test_count 失败"
        fi
        
        # 停止日志监控
        kill $tail_pid 2>/dev/null || true
        
        # 分析结果
        analyze_results "测试 $test_count" "/tmp/strongswan_test_test_${test_count}_*.log" > "/tmp/test_results_${test_count}.txt"
        
        # 等待一段时间再进行下一个测试
        sleep 5
    done
    
    # 清理网络条件
    cleanup_network $interface
    
    # 生成报告
    generate_report
    
    # 输出总结
    log_info "=== 测试总结 ==="
    log_info "总测试数: $test_count"
    log_info "成功数: $success_count"
    log_info "失败数: $((test_count - success_count))"
    if [[ $test_count -gt 0 ]]; then
        local success_rate=$(echo "scale=2; $success_count * 100 / $test_count" | bc)
        log_info "成功率: ${success_rate}%"
    else
        log_info "成功率: 0%"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
strongSwan 分片重传网络测试脚本

用法: $0 [选项] <连接名称>

选项:
    -i, --interface <接口>    指定网络接口 (默认: 自动检测)
    -s, --scenarios <场景>    指定测试场景 (默认: 使用预设场景)
    -r, --remote <IP>         对端IP地址 (用于设置对端网络条件)
    -h, --help               显示此帮助信息

测试场景格式:
    <类型>:<值>
    
支持的类型:
    loss        - 丢包率 (百分比)
    delay       - 延迟 (毫秒)
    bandwidth   - 带宽限制 (如: 1mbit)
    corruption  - 数据包损坏率 (百分比)
    duplication - 数据包重复率 (百分比)
    reordering  - 数据包重排序

示例:
    $0 site-to-site
    $0 -i eth0 site-to-site
    $0 -s "loss:10,delay:100,bandwidth:1mbit" site-to-site
    $0 -r 192.168.31.135 site-to-site

预设测试场景:
    - 轻微丢包 (5%)
    - 中等丢包 (15%)
    - 严重丢包 (30%)
    - 轻微延迟 (50ms)
    - 中等延迟 (200ms)
    - 严重延迟 (500ms)
    - 带宽限制 (1Mbps)
    - 数据包损坏 (2%)
    - 数据包重复 (5%)
    - 数据包重排序

重要说明:
    - 当前脚本只在本机设置网络条件
    - 为获得更准确的测试结果，建议在对端也设置相同的网络条件
    - 使用 -r 选项指定对端IP，脚本会提供对端设置命令

EOF
}

# 主函数
main() {
    # 检查root权限
    check_root
    
    # 默认参数
    local interface=""
    local conn_name=""
    local custom_scenarios=""
    local remote_ip=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -s|--scenarios)
                custom_scenarios="$2"
                shift 2
                ;;
            -r|--remote)
                remote_ip="$2"
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
    
    # 设置测试场景
    local test_scenarios=()
    
    if [[ -n "$custom_scenarios" ]]; then
        # 使用自定义场景
        IFS=',' read -ra scenarios <<< "$custom_scenarios"
        for scenario in "${scenarios[@]}"; do
            test_scenarios+=("$scenario")
        done
    else
        # 使用预设场景
        test_scenarios=(
            "loss:5"
            "loss:15"
            "loss:30"
            "delay:50"
            "delay:200"
            "delay:500"
            "bandwidth:1mbit"
            "corruption:2"
            "duplication:5"
            "reordering"
        )
    fi
    
    # 显示对端设置说明
    if [[ -n "$remote_ip" ]]; then
        echo ""
        log_info "=== 对端网络条件设置说明 ==="
        log_info "为获得准确的测试结果，请在对端机器 ($remote_ip) 上执行以下命令："
        echo ""
        echo "1. 获取对端网络接口："
        echo "   ip route | grep default | awk '{print \$5}' | head -1"
        echo ""
        echo "2. 设置网络条件（替换 <interface> 为实际接口名）："
        for scenario in "${test_scenarios[@]}"; do
            IFS=':' read -r condition_type value <<< "$scenario"
            case $condition_type in
                "loss")
                    echo "   tc qdisc add dev <interface> root netem loss ${value}%"
                    ;;
                "delay")
                    echo "   tc qdisc add dev <interface> root netem delay ${value}ms"
                    ;;
                "bandwidth")
                    echo "   tc qdisc add dev <interface> root tbf rate $value burst 32kbit latency 400ms"
                    ;;
                "corruption")
                    echo "   tc qdisc add dev <interface> root netem corrupt ${value}%"
                    ;;
                "duplication")
                    echo "   tc qdisc add dev <interface> root netem duplicate ${value}%"
                    ;;
                "reordering")
                    echo "   tc qdisc add dev <interface> root netem delay 10ms reorder 25% 50%"
                    ;;
            esac
        done
        echo ""
        echo "3. 清理网络条件："
        echo "   tc qdisc del dev <interface> root"
        echo ""
        log_warning "请在对端设置完成后，再运行本脚本进行测试"
        echo ""
    fi
    
    # 运行测试
    run_network_test $interface $conn_name "${test_scenarios[@]}"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 