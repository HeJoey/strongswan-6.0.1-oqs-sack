#!/bin/bash

# 双向网络条件设置脚本
# 用于在两端同时设置相同的网络条件，确保测试的严谨性

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

# 生成对端设置脚本
generate_remote_script() {
    local remote_ip=$1
    local condition_type=$2
    local value=$3
    local script_name="remote_setup_${remote_ip}_$(date +%Y%m%d_%H%M%S).sh"
    
    cat > $script_name << EOF
#!/bin/bash

# 对端网络条件设置脚本
# 请在 $remote_ip 上运行此脚本

set -e

# 颜色定义
RED='\\033[0;31m'
GREEN='\\033[0;32m'
BLUE='\\033[0;34m'
NC='\\033[0m'

log_info() {
    echo -e "\\\${BLUE}[INFO]\\\${NC} \$1"
}

log_success() {
    echo -e "\\\${GREEN}[SUCCESS]\\\${NC} \$1"
}

log_error() {
    echo -e "\\\${RED}[ERROR]\\\${NC} \$1"
}

# 检查root权限
if [[ \$EUID -ne 0 ]]; then
    log_error "此脚本需要root权限运行"
    exit 1
fi

# 获取默认网络接口
interface=\$(ip route | grep default | awk '{print \$5}' | head -1)
log_info "使用网络接口: \$interface"

# 清理现有网络条件
log_info "清理现有网络条件..."
tc qdisc del dev \$interface root 2>/dev/null || true

# 设置网络条件
log_info "设置网络条件: $condition_type = $value"

case "$condition_type" in
    "loss")
        tc qdisc add dev \$interface root netem loss $value%
        ;;
    "delay")
        tc qdisc add dev \$interface root netem delay ${value}ms
        ;;
    "bandwidth")
        tc qdisc add dev \$interface root tbf rate $value burst 32kbit latency 400ms
        ;;
    "corruption")
        tc qdisc add dev \$interface root netem corrupt $value%
        ;;
    "duplication")
        tc qdisc add dev \$interface root netem duplicate $value%
        ;;
    "reordering")
        tc qdisc add dev \$interface root netem delay 10ms reorder 25% 50%
        ;;
esac

log_success "网络条件设置完成"
log_info "当前网络条件:"
tc qdisc show dev \$interface

echo ""
log_info "测试完成后，请运行以下命令清理网络条件："
echo "tc qdisc del dev \$interface root"
EOF

    chmod +x $script_name
    echo $script_name
}

# 显示帮助信息
show_help() {
    cat << EOF
双向网络条件设置脚本

用法: $0 [选项] <网络条件>

选项:
    -i, --interface <接口>    指定网络接口 (默认: 自动检测)
    -r, --remote <IP>         对端IP地址 (生成对端设置脚本)
    -c, --cleanup             清理网络条件
    -h, --help               显示此帮助信息

网络条件格式:
    <类型>:<值>
    
支持的类型:
    loss        - 丢包率 (百分比)
    delay       - 延迟 (毫秒)
    bandwidth   - 带宽限制 (如: 1mbit)
    corruption  - 数据包损坏率 (百分比)
    duplication - 数据包重复率 (百分比)
    reordering  - 数据包重排序

示例:
    $0 delay:100
    $0 -i eth0 loss:10
    $0 -r 192.168.31.135 delay:200
    $0 -c

重要说明:
    - 使用 -r 选项会生成对端设置脚本
    - 为获得准确的测试结果，建议两端都设置相同的网络条件
    - 测试完成后记得清理网络条件

EOF
}

# 主函数
main() {
    check_root
    
    local interface=""
    local remote_ip=""
    local cleanup_mode=false
    local condition=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -r|--remote)
                remote_ip="$2"
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
                if [[ -z "$condition" ]]; then
                    condition="$1"
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
    
    if [[ "$cleanup_mode" == true ]]; then
        cleanup_network $interface
        exit 0
    fi
    
    if [[ -z "$condition" ]]; then
        log_error "请指定网络条件"
        show_help
        exit 1
    fi
    
    # 解析网络条件
    IFS=':' read -r condition_type value <<< "$condition"
    
    if [[ -z "$condition_type" ]] || [[ -z "$value" ]]; then
        log_error "无效的网络条件格式: $condition"
        log_error "正确格式: <类型>:<值> (例如: delay:100)"
        exit 1
    fi
    
    log_info "=== 双向网络条件设置 ==="
    log_info "网络接口: $interface"
    log_info "网络条件: $condition_type = $value"
    
    if [[ -n "$remote_ip" ]]; then
        log_info "对端IP: $remote_ip"
    fi
    echo ""
    
    # 清理现有网络条件
    cleanup_network $interface
    
    # 设置网络条件
    setup_network_condition $interface $condition_type $value
    
    # 显示当前网络条件
    log_info "当前网络条件:"
    sudo tc qdisc show dev $interface
    
    # 生成对端设置脚本
    if [[ -n "$remote_ip" ]]; then
        echo ""
        log_info "生成对端设置脚本..."
        local remote_script=$(generate_remote_script $remote_ip $condition_type $value)
        log_success "对端设置脚本已生成: $remote_script"
        echo ""
        log_info "请将对端设置脚本复制到 $remote_ip 并执行："
        echo "scp $remote_script $remote_ip:/tmp/"
        echo "ssh $remote_ip 'sudo bash /tmp/$remote_script'"
        echo ""
        log_warning "确保两端都设置完成后，再进行IPsec连接测试"
    fi
    
    echo ""
    log_success "网络条件设置完成！"
    log_info "测试完成后，请运行以下命令清理网络条件："
    echo "sudo $0 -c"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 