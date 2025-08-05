#!/bin/bash

# 网络丢包设置脚本
# 用于设置不同的突发丢包率以测试IPsec性能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取默认网络接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# 函数：显示帮助信息
show_help() {
    echo -e "${CYAN}网络丢包设置脚本${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -r, --rate <rate>     设置丢包率 (0-100%)"
    echo "  -b, --burst <size>    设置突发丢包大小 (默认: 3)"
    echo "  -d, --delay <ms>      设置网络延迟 (默认: 50ms)"
    echo "  -i, --interface <if>  指定网络接口 (默认: $INTERFACE)"
    echo "  -m, --mode <mode>     丢包模式: simple(简单) 或 burst(突发,默认)"
    echo "  -c, --clear          清除所有网络条件"
    echo "  -s, --status         显示当前网络条件"
    echo "  -h, --help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -r 5              # 设置5%简单丢包率"
    echo "  $0 -r 5 -m simple    # 设置5%简单丢包率"
    echo "  $0 -r 10 -b 5        # 设置10%突发丢包率，突发大小5"
    echo "  $0 -r 0              # 设置理想网络条件"
    echo "  $0 -c                # 清除所有网络条件"
    echo "  $0 -s                # 显示当前状态"
}

# 函数：带时间戳的日志
log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"
}

# 函数：清除网络条件
clear_network_conditions() {
    log "${YELLOW}清除网络接口 $INTERFACE 上的网络条件...${NC}"
    
    # 删除根qdisc
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    
    # 删除入口qdisc
    sudo tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
    
    log "${GREEN}网络条件已清除${NC}"
}

# 函数：显示当前网络条件
show_status() {
    log "${YELLOW}当前网络接口 $INTERFACE 的配置:${NC}"
    
    echo -e "${CYAN}根队列规则:${NC}"
    sudo tc qdisc show dev $INTERFACE 2>/dev/null || echo "  无特殊配置"
    
    echo -e "${CYAN}过滤器规则:${NC}"
    sudo tc filter show dev $INTERFACE 2>/dev/null || echo "  无过滤器"
    
    echo -e "${CYAN}网络接口状态:${NC}"
    ip link show $INTERFACE | grep -E "(UP|DOWN|mtu)"
}

# 函数：设置突发丢包
set_burst_packet_loss() {
    local loss_rate=$1
    local burst_size=$2
    local delay=$3
    local interface=$4
    
    log "${YELLOW}在接口 $interface 上设置网络条件...${NC}"
    log "  丢包率: ${loss_rate}%"
    log "  丢包模式: $loss_mode"
    if [ "$loss_mode" = "burst" ]; then
        log "  突发大小: $burst_size"
    fi
    log "  网络延迟: ${delay}ms"
    
    # 清除现有规则
    clear_network_conditions
    
    # 设置网络条件
    if [ "$loss_rate" = "0" ]; then
        # 理想网络条件
        sudo tc qdisc add dev $interface root netem delay ${delay}ms
        log "${GREEN}理想网络条件设置完成${NC}"
    else
        if [ "$loss_mode" = "simple" ]; then
            # 简单丢包模式
            sudo tc qdisc add dev $interface root netem delay ${delay}ms loss ${loss_rate}%
            log "${GREEN}简单丢包网络条件设置完成${NC}"
        else
            # 突发丢包模式 (默认)
            # 使用Gilbert-Elliott模型模拟突发丢包
            # loss gemodel p r 1-h 1-k
            # p: 进入坏状态的概率
            # r: 在坏状态中的丢包概率  
            # 1-h: 坏状态恢复到好状态的概率
            # 1-k: 好状态保持的概率
            
            # 计算Gilbert-Elliott模型参数
            # 目标: 平均丢包率为loss_rate%，突发长度为burst_size
            # 使用awk替代bc进行浮点计算
            
            # Gilbert-Elliott模型参数说明:
            # p: 从好状态进入坏状态的概率
            # r: 在坏状态时的丢包概率 (设为1.0表示坏状态时100%丢包)
            # h: 从坏状态恢复到好状态的概率
            # k: 在好状态时保持好状态的概率
            
            # 计算参数:
            # 1. 坏状态平均持续时间 = 1/h = burst_size
            # 2. 好状态平均持续时间 = 1/(1-k) ≈ 100 (因为k=0.99)
            # 3. 平均丢包率 = (p/(p+h)) * r = loss_rate/100
            
            local r="1.0"  # 在坏状态时100%丢包
            local h=$(awk "BEGIN {printf \"%.6f\", 1/$burst_size}")  # 坏状态恢复概率
            local k="0.99"  # 好状态保持概率 (1-k=0.01, 好状态平均持续100个包)
            
            # 根据平均丢包率计算p: (p/(p+h)) * r = loss_rate/100
            # 因为r=1.0，所以 p/(p+h) = loss_rate/100
            # 解出 p = (loss_rate/100) * h / (1 - loss_rate/100)
            local p=$(awk "BEGIN {printf \"%.6f\", ($loss_rate/100) * $h / (1 - $loss_rate/100)}")
            
            # 应用网络条件
            sudo tc qdisc add dev $interface root netem delay ${delay}ms loss gemodel $p $r $h $k
            
            log "${GREEN}突发丢包网络条件设置完成${NC}"
            log "${CYAN}Gilbert-Elliott参数: p=$p, r=$r, h=$h, k=$k${NC}"
        fi
    fi
    
    # 验证设置
    log "${CYAN}当前网络条件:${NC}"
    sudo tc qdisc show dev $interface
}

# 函数：批量设置预定义丢包率
setup_predefined_rates() {
    local rates=(0 1 2 5 10 15 20 25 30)
    
    log "${CYAN}可用的预定义丢包率:${NC}"
    for i in "${!rates[@]}"; do
        echo "  $((i+1)). ${rates[i]}%"
    done
    
    echo -n "请选择丢包率 (1-${#rates[@]}): "
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#rates[@]}" ]; then
        local selected_rate=${rates[$((choice-1))]}
        set_burst_packet_loss "$selected_rate" 3 50 "$INTERFACE"
    else
        log "${RED}无效选择${NC}"
        exit 1
    fi
}

# 主函数
main() {
    local loss_rate=""
    local burst_size=3
    local delay=50
    local interface="$INTERFACE"
    local loss_mode="burst"  # 默认使用突发模式
    local clear_flag=false
    local status_flag=false
    local interactive_flag=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--rate)
                loss_rate="$2"
                shift 2
                ;;
            -b|--burst)
                burst_size="$2"
                shift 2
                ;;
            -d|--delay)
                delay="$2"
                shift 2
                ;;
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -m|--mode)
                loss_mode="$2"
                shift 2
                ;;
            -c|--clear)
                clear_flag=true
                shift
                ;;
            -s|--status)
                status_flag=true
                shift
                ;;
            -p|--predefined)
                interactive_flag=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知参数: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查接口是否存在
    if ! ip link show "$interface" &>/dev/null; then
        log "${RED}错误: 网络接口 '$interface' 不存在${NC}"
        exit 1
    fi
    
    # 执行相应操作
    if [ "$clear_flag" = true ]; then
        clear_network_conditions
    elif [ "$status_flag" = true ]; then
        show_status
    elif [ "$interactive_flag" = true ]; then
        setup_predefined_rates
    elif [ -n "$loss_rate" ]; then
        # 验证丢包率范围 - 使用awk替代bc
        if ! [[ "$loss_rate" =~ ^[0-9]+\.?[0-9]*$ ]] || [ "$(awk "BEGIN {print ($loss_rate >= 0 && $loss_rate <= 100)}")" != "1" ]; then
            log "${RED}错误: 丢包率必须在0-100之间${NC}"
            exit 1
        fi
        
        # 验证突发大小
        if ! [[ "$burst_size" =~ ^[0-9]+$ ]] || [ "$burst_size" -le 0 ]; then
            log "${RED}错误: 突发大小必须是正整数${NC}"
            exit 1
        fi
        
        # 验证延迟
        if ! [[ "$delay" =~ ^[0-9]+$ ]] || [ "$delay" -lt 0 ]; then
            log "${RED}错误: 延迟必须是非负整数${NC}"
            exit 1
        fi
        
        set_burst_packet_loss "$loss_rate" "$burst_size" "$delay" "$interface"
    else
        show_help
        exit 1
    fi
}

# 权限检查
if [ "$EUID" -ne 0 ] && [[ "$*" != *"--help"* ]] && [[ "$*" != *"-h"* ]]; then
    log "${RED}此脚本需要root权限运行${NC}"
    log "${YELLOW}请使用: sudo $0 $*${NC}"
    exit 1
fi

# 运行主函数
main "$@" 