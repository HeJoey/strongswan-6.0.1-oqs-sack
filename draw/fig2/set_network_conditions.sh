#!/bin/bash

# 网络条件设置脚本
# 用于设置突发丢包率，可以传到对端使用

set -e

# 默认配置
DEFAULT_INTERFACE="ens33"
DEFAULT_BURST_SIZE=3
DEFAULT_DELAY=0

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "网络条件设置脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --interface INTERFACE    网络接口名称 (默认: $DEFAULT_INTERFACE)"
    echo "  -l, --loss RATE              丢包率百分比 (0-100)"
    echo "  -b, --burst SIZE             突发大小 (默认: $DEFAULT_BURST_SIZE)"
    echo "  -d, --delay MS               延迟毫秒数 (默认: $DEFAULT_DELAY)"
    echo "  -c, --clear                  清除所有网络条件设置"
    echo "  -s, --show                   显示当前网络条件"
    echo "  -h, --help                   显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l 10 -b 3                # 设置10%丢包率，突发大小3"
    echo "  $0 -l 5                      # 设置5%丢包率，使用默认突发大小"
    echo "  $0 -d 5                      # 设置5ms延迟"
    echo "  $0 -l 5 -d 10                # 设置5%丢包率和10ms延迟"
    echo "  $0 -c                        # 清除所有网络条件"
    echo "  $0 -s                        # 显示当前网络条件"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0 [选项]"
        exit 1
    fi
}

# 检查网络接口是否存在
check_interface() {
    local interface=$1
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_error "网络接口 $interface 不存在"
        echo "可用的网络接口:"
        ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | cut -d'@' -f1
        exit 1
    fi
}

# 检查tc命令是否可用
check_tc() {
    if ! command -v tc >/dev/null 2>&1; then
        log_error "tc命令不可用，请安装iproute2包"
        echo "Ubuntu/Debian: sudo apt-get install iproute2"
        echo "CentOS/RHEL: sudo yum install iproute"
        exit 1
    fi
}

# 清除网络条件设置
clear_network_conditions() {
    local interface=$1
    log_info "清除网络接口 $interface 的所有条件设置..."
    
    # 删除所有qdisc
    tc qdisc del dev "$interface" root 2>/dev/null || true
    tc qdisc del dev "$interface" ingress 2>/dev/null || true
    
    log_success "网络条件已清除"
}

# 设置网络条件（丢包和延迟）
set_network_conditions() {
    local interface=$1
    local loss_rate=$2
    local burst_size=$3
    local delay_ms=$4
    
    log_info "设置网络接口 $interface 的网络条件..."
    log_info "丢包率: ${loss_rate}%, 突发大小: ${burst_size}, 延迟: ${delay_ms}ms"
    
    # 清除现有设置
    clear_network_conditions "$interface"
    
    # 构建netem命令
    local netem_cmd="tc qdisc add dev \"$interface\" root netem"
    
    # 添加延迟
    if [[ $delay_ms -gt 0 ]]; then
        netem_cmd="$netem_cmd delay ${delay_ms}ms"
    fi
    
    # 添加丢包
    if [[ $loss_rate -gt 0 ]]; then
        if [[ $delay_ms -gt 0 ]]; then
            netem_cmd="$netem_cmd loss ${loss_rate}% ${burst_size}"
        else
            netem_cmd="$netem_cmd loss ${loss_rate}% ${burst_size}"
        fi
    fi
    
    # 执行命令
    eval $netem_cmd
    
    if [[ $? -eq 0 ]]; then
        if [[ $loss_rate -eq 0 && $delay_ms -eq 0 ]]; then
            log_success "设置为理想网络条件 (无丢包，无延迟)"
        elif [[ $loss_rate -eq 0 ]]; then
            log_success "延迟设置完成: ${delay_ms}ms"
        elif [[ $delay_ms -eq 0 ]]; then
            log_success "突发丢包设置完成: ${loss_rate}%"
        else
            log_success "网络条件设置完成: ${loss_rate}%丢包, ${delay_ms}ms延迟"
        fi
    else
        log_error "设置失败"
        exit 1
    fi
}

# 显示当前网络条件
show_network_conditions() {
    local interface=$1
    
    log_info "网络接口 $interface 的当前条件:"
    
    # 检查是否有qdisc设置
    if tc qdisc show dev "$interface" | grep -q "netem"; then
        echo ""
        echo "当前网络条件设置:"
        tc qdisc show dev "$interface"
        echo ""
        
        # 解析并显示详细信息
        local netem_info=$(tc qdisc show dev "$interface" | grep netem)
        
        # 显示延迟信息
        if echo "$netem_info" | grep -q "delay"; then
            local delay_info=$(echo "$netem_info" | grep -o "delay [0-9]*ms")
            echo "延迟设置: $delay_info"
        fi
        
        # 显示丢包信息
        if echo "$netem_info" | grep -q "loss"; then
            local loss_info=$(echo "$netem_info" | grep -o "loss [0-9.]*% [0-9]*")
            echo "丢包设置: $loss_info"
        fi
    else
        log_success "无网络条件限制 (理想网络)"
    fi
}

# 主函数
main() {
    local interface="$DEFAULT_INTERFACE"
    local loss_rate=""
    local burst_size="$DEFAULT_BURST_SIZE"
    local delay_ms="$DEFAULT_DELAY"
    local clear_flag=false
    local show_flag=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -l|--loss)
                loss_rate="$2"
                shift 2
                ;;
            -b|--burst)
                burst_size="$2"
                shift 2
                ;;
            -d|--delay)
                delay_ms="$2"
                shift 2
                ;;
            -c|--clear)
                clear_flag=true
                shift
                ;;
            -s|--show)
                show_flag=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查root权限
    check_root
    
    # 检查依赖
    check_tc
    
    # 检查网络接口
    check_interface "$interface"
    
    # 执行操作
    if [[ "$clear_flag" == true ]]; then
        clear_network_conditions "$interface"
    elif [[ "$show_flag" == true ]]; then
        show_network_conditions "$interface"
    elif [[ -n "$loss_rate" || $delay_ms -gt 0 ]]; then
        # 验证参数
        if [[ -n "$loss_rate" ]]; then
            if ! [[ "$loss_rate" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$loss_rate < 0" | bc -l) )) || (( $(echo "$loss_rate > 100" | bc -l) )); then
                log_error "丢包率必须在0-100之间"
        exit 1
    fi
    
            if ! [[ "$burst_size" =~ ^[0-9]+$ ]] || [[ $burst_size -lt 1 ]]; then
                log_error "突发大小必须是正整数"
                exit 1
            fi
        fi
        
        if ! [[ "$delay_ms" =~ ^[0-9]+$ ]] || (( $(echo "$delay_ms < 0" | bc -l) )); then
            log_error "延迟必须是正整数"
        exit 1
    fi
    
        set_network_conditions "$interface" "$loss_rate" "$burst_size" "$delay_ms"
    else
        log_error "请指定操作参数"
        show_help
        exit 1
    fi
}
    
# 清理函数
cleanup() {
    log_info "脚本执行完成"
}

# 设置信号处理
trap cleanup EXIT

# 运行主函数
main "$@" 