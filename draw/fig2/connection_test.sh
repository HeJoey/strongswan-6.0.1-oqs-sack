#!/bin/bash

# IPsec连接测试脚本
# 用于测试strongSwan连接性能

# set -e  # 暂时注释掉，避免提前退出

# 默认配置
DEFAULT_CONNECTION_NAME="net-net"
DEFAULT_TIMEOUT=60
DEFAULT_TESTS=50
DEFAULT_LOSS_RATES="0 5 10 15 20"
DEFAULT_TESTS_PER_LOSS=50

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
    echo "IPsec连接测试脚本 - 用于生成图4、图5、图6数据"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -l, --loss-rates RATES       丢包率列表 (默认: $DEFAULT_LOSS_RATES)"
    echo "  -n, --tests-per-loss N       每个丢包率的测试次数 (默认: $DEFAULT_TESTS_PER_LOSS)"
    echo "  -c, --connection NAME        连接名称 (默认: $DEFAULT_CONNECTION_NAME)"
    echo "  -t, --timeout SECONDS        连接超时时间 (默认: $DEFAULT_TIMEOUT)"
    echo "  -o, --output FILE            输出文件 (默认: plot_data.csv)"
    echo "  -v, --verbose                详细输出模式"
    echo "  -h, --help                   显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l '0 5 10' -n 30          # 测试0%, 5%, 10%丢包率，每个30次"
    echo "  $0 -o my_data.csv             # 指定输出文件"
    echo ""
    echo "输出数据格式:"
    echo "  原始数据: 丢包率(%),测试序号,结果,HCT(ms),重传次数"
    echo "  用于生成: 图4(握手成功率)、图5(HCT箱形图)、图6(重传次数)"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0 [选项]"
        exit 1
    fi
}

# 检查strongSwan是否运行
check_strongswan() {
    if ! systemctl is-active --quiet strongswan; then
        log_warning "strongSwan服务未运行，尝试启动..."
        systemctl start strongswan
        sleep 2
        
        if ! systemctl is-active --quiet strongswan; then
            log_error "无法启动strongSwan服务"
            exit 1
        fi
    fi
    log_success "strongSwan服务运行正常"
}

# 检查连接配置是否存在
check_connection() {
    local conn_name=$1
    
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接配置 '$conn_name' 不存在"
        echo "可用的连接配置:"
        sudo swanctl --list-conns
        exit 1
    fi
}



# 等待IKE SA建立
wait_for_ike_sa() {
    local conn_name=$1
    local timeout=$2
    local start_time=$(date +%s)
    
    while true; do
        # 检查IKE SA状态
        if sudo swanctl --list-sas | grep -q "$conn_name.*ESTABLISHED"; then
            return 0
        fi
        
        # 检查超时
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            return 1
        fi
        
        sleep 0.1  # 更频繁的检查
    done
}

# 计算握手完成时间（毫秒）
calculate_hct() {
    local start_time=$1
    local end_time=$2
    
    # 使用bc进行浮点计算，转换为毫秒
    echo "scale=1; ($end_time - $start_time) * 1000" | bc
}

# 统计重传次数
count_retransmissions() {
    # 统计最近的重传事件
    local retrans_count=$(journalctl -u strongswan --since "1 minute ago" | grep -i "retransmit\|retry" | wc -l)
    echo $retrans_count
}

# 执行单次测试
perform_single_test() {
    local conn_name=$1
    local timeout=$2
    local test_num=$3
    local verbose=$4
    
    if [[ "$verbose" == "true" ]]; then
        log_info "测试 $test_num: 启动连接 '$conn_name'"
    fi
    
    # 先断开现有连接
    sudo swanctl --terminate --child "$conn_name" >/dev/null 2>&1 || true
    sleep 2  # 增加等待时间，确保连接完全断开
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动IKE SA建立
    if ! sudo swanctl --initiate --ike "$conn_name" >/dev/null 2>&1; then
        log_error "测试 $test_num: IKE SA启动失败"
        return 1
    fi
    
    # 等待IKE SA建立
    if wait_for_ike_sa "$conn_name" "$timeout"; then
        local end_time=$(date +%s.%N)
        local hct=$(calculate_hct "$start_time" "$end_time")
        local retrans=$(count_retransmissions)
        
        if [[ "$verbose" == "true" ]]; then
            log_success "测试 $test_num: IKE SA建立成功 - HCT: ${hct}ms, 重传: $retrans"
        fi
        
        echo "SUCCESS,$hct,$retrans" >&2
        echo "SUCCESS,$hct,$retrans"
        return 0
    else
        if [[ "$verbose" == "true" ]]; then
            log_error "测试 $test_num: IKE SA建立超时"
        fi
        
        echo "TIMEOUT,0,0" >&2
        echo "TIMEOUT,0,0"
        return 1
    fi
}

# 生成绘图数据文件
generate_plot_data() {
    local results_file=$1
    local output_file=$2
    
    log_info "生成绘图数据文件..."
    
    # 创建输出文件头
    cat > "$output_file" << EOF
# 绘图数据文件
# 生成时间: $(date)
# 用于生成图4(握手成功率)、图5(HCT箱形图)、图6(重传次数)
# 格式: 丢包率(%),测试序号,结果,HCT(ms),重传次数
EOF
    
    # 添加所有测试结果
    cat "$results_file" >> "$output_file"
    
    log_success "绘图数据已保存到: $output_file"
}

# 主函数
main() {
    local loss_rates="$DEFAULT_LOSS_RATES"
    local tests_per_loss="$DEFAULT_TESTS_PER_LOSS"
    local conn_name="$DEFAULT_CONNECTION_NAME"
    local timeout="$DEFAULT_TIMEOUT"
    local output_file="plot_data.csv"
    local verbose=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--loss-rates)
                loss_rates="$2"
                shift 2
                ;;
            -n|--tests-per-loss)
                tests_per_loss="$2"
                shift 2
                ;;
            -c|--connection)
                conn_name="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
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
    
    # 检查strongSwan
    check_strongswan
    
    # 检查连接配置
    check_connection "$conn_name"
    
    # 创建临时结果文件
    local temp_results=$(mktemp)
    
    log_info "开始收集IPsec连接测试数据"
    log_info "丢包率: $loss_rates"
    log_info "每个丢包率测试次数: $tests_per_loss"
    log_info "连接名称: $conn_name"
    log_info "输出文件: $output_file"
    log_info "注意: 请确保两端已使用 set_network_conditions.sh 设置了相应的网络条件"
    echo ""
    
    # 测试每个丢包率
    for loss_rate in $loss_rates; do
        log_info "测试丢包率: ${loss_rate}%"
        log_info "请确保两端已使用 set_network_conditions.sh 设置了 ${loss_rate}% 丢包率"
        
        # 运行测试
        local success_count=0
        local total_tests=$tests_per_loss
        
        for ((i=1; i<=tests_per_loss; i++)); do
            # 显示进度
            if [[ $((i % 10)) -eq 0 ]]; then
                echo -ne "\r  进度: $i/$tests_per_loss"
            fi
            
            # 运行单次测试
            if result=$(perform_single_test "$conn_name" "$timeout" "$i" "$verbose"); then
                ((success_count++))
            fi
            
            # 写入结果（格式：丢包率,测试序号,结果,HCT,重传）
            echo "$loss_rate,$i,$result" >> "$temp_results"
            
            # 测试间隔
            sleep 0.5
        done
        
        echo ""
        local success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
        log_success "丢包率 ${loss_rate}%: 成功率 ${success_rate}% ($success_count/$total_tests)"
        echo ""
    done
    
    log_info "测试完成"
    
    # 生成绘图数据文件
    generate_plot_data "$temp_results" "$output_file"
    
    # 清理临时文件
    rm -f "$temp_results"
    
    log_success "所有测试完成！"
    log_success "测试数据已保存到: $output_file"
    log_success "数据格式: 丢包率(%),测试序号,结果,HCT(ms),重传次数"
    log_success "可用于生成图4(握手成功率)、图5(HCT箱形图)、图6(重传次数)"
}

# 清理函数
cleanup() {
    log_info "脚本执行完成"
}

# 设置信号处理
trap cleanup EXIT

# 运行主函数
main "$@" 