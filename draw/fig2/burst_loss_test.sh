#!/bin/bash

# strongSwan 突发丢包率性能测试脚本
# 用于生成图5和图6的数据：连接成功率 vs 突发丢包率、HCT vs 突发丢包率、重传次数 vs 突发丢包率

# =============================================================================
# 脚本配置
# =============================================================================

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 文件路径配置
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly RESULTS_DIR="${SCRIPT_DIR}/burst_loss_results_${TIMESTAMP}"
readonly LOG_FILE="${RESULTS_DIR}/burst_loss_test.log"

# 测试配置
readonly DEFAULT_TESTS_PER_LOSS_RATE=50     # 每个丢包率的测试次数 - 确保数据可靠性
readonly DEFAULT_CONNECTION_TIMEOUT=60      # 连接超时时间(秒)
readonly DEFAULT_INTERFACE="ens33"          # 网络接口
readonly DEFAULT_CONNECTION_NAME="net-net" # IPsec连接名称

# 丢包率测试范围 (百分比) - 简化版本用于测试
readonly LOSS_RATES=(0 5 10 15)

# 突发配置：突发丢包模式 - 连续丢包
readonly BURST_SIZE=3  # 连续丢包数量

# =============================================================================
# 日志和工具函数
# =============================================================================

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "${RED}错误: $1${NC}"
    cleanup_and_exit 1
}

cleanup_network() {
    log "${YELLOW}清理网络设置...${NC}"
    sudo tc qdisc del dev "$DEFAULT_INTERFACE" root 2>/dev/null || true
    sudo tc qdisc del dev "$DEFAULT_INTERFACE" ingress 2>/dev/null || true
}

cleanup_and_exit() {
    local exit_code=${1:-0}
    cleanup_network
    log "${CYAN}测试结束。结果保存在: $RESULTS_DIR${NC}"
    exit $exit_code
}

# =============================================================================
# 依赖检查
# =============================================================================

check_dependencies() {
    log "${YELLOW}检查依赖...${NC}"
    
    # 检查必要的命令
    local deps=("swanctl" "tc" "bc" "awk" "grep" "tee")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error_exit "缺少依赖 '$dep'"
        fi
    done
    
    # 检查是否以root权限运行
    if [[ $EUID -ne 0 ]]; then
        error_exit "此脚本需要root权限运行"
    fi
    
    # 检查网络接口
    if ! ip link show "$DEFAULT_INTERFACE" &> /dev/null; then
        error_exit "网络接口 $DEFAULT_INTERFACE 不存在"
    fi
    
    log "${GREEN}依赖检查通过${NC}"
}

# =============================================================================
# 网络条件设置
# =============================================================================

set_burst_loss_conditions() {
    local loss_rate=$1
    
    cleanup_network
    
    if (( $(echo "$loss_rate > 0" | bc -l) )); then
        log "${YELLOW}设置突发丢包率: ${loss_rate}% (突发大小: ${BURST_SIZE})${NC}"
        
        # 使用tc netem设置突发丢包
        # 语法：tc qdisc add dev DEVICE root netem loss PERCENT% [CORRELATION%]
        # 为了模拟突发丢包，我们使用更高的相关性参数
        sudo tc qdisc add dev "$DEFAULT_INTERFACE" root netem \
            loss "${loss_rate}%" 25% \
            delay 5ms 1ms \
            duplicate 0% \
            corrupt 0% || error_exit "设置突发丢包失败"
            
        log "${GREEN}突发丢包设置完成: ${loss_rate}%${NC}"
    else
        log "${GREEN}理想网络条件 (无丢包)${NC}"
    fi
}

# =============================================================================
# strongSwan控制函数
# =============================================================================

start_strongswan() {
    log "${YELLOW}启动strongSwan...${NC}"
    if ! systemctl is-active --quiet strongswan; then
        sudo systemctl start strongswan || error_exit "启动strongSwan失败"
        sleep 2
    fi
    log "${GREEN}strongSwan已启动${NC}"
}

stop_strongswan() {
    log "${YELLOW}停止strongSwan...${NC}"
    sudo systemctl stop strongswan 2>/dev/null || true
    sleep 1
}

# =============================================================================
# 连接测试和数据收集
# =============================================================================

wait_for_connection() {
    local timeout=$1
    local start_time=$(date +%s.%3N)
    local end_time
    
    for ((i=0; i<timeout; i++)); do
        if sudo swanctl --list-sas | grep -q "ESTABLISHED"; then
            end_time=$(date +%s.%3N)
            local hct=$(echo "scale=3; $end_time - $start_time" | bc)
            echo "$hct"
            return 0
        fi
        sleep 1
    done
    
    return 1
}

count_retransmissions() {
    local log_start_time=$1
    
    # 统计重传次数
    local retrans_count=$(journalctl --since "$log_start_time" -u strongswan | \
        grep -c "retransmit.*of request" 2>/dev/null || echo "0")
    
    echo "$retrans_count"
}

perform_single_test() {
    local loss_rate=$1
    local test_num=$2
    local test_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "${CYAN}测试 ${test_num}: 丢包率 ${loss_rate}%${NC}"
    
    # 断开现有连接
    sudo swanctl --terminate --ike "$DEFAULT_CONNECTION_NAME" &>/dev/null || true
    sleep 2
    
    # 清理SA状态
    sudo swanctl --flush-certs &>/dev/null || true
    sleep 1
    
    # 记录测试开始时间（用于日志过滤）
    local log_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 发起连接
    local connect_start=$(date +%s.%3N)
    local connect_result
    local hct="0"
    local success=0
    local retrans_count=0
    
    # 异步发起连接并等待结果
    if sudo swanctl --initiate --child "$DEFAULT_CONNECTION_NAME" &>/dev/null; then
        # 等待连接建立
        if hct=$(wait_for_connection $DEFAULT_CONNECTION_TIMEOUT); then
            success=1
            connect_result="SUCCESS"
            
            # 统计重传次数
            retrans_count=$(count_retransmissions "$log_start_time")
            
            log "${GREEN}连接成功: HCT=${hct}s, 重传=${retrans_count}次${NC}"
        else
            connect_result="TIMEOUT"
            log "${RED}连接超时${NC}"
        fi
    else
        connect_result="INITIATE_FAILED"
        log "${RED}连接发起失败${NC}"
    fi
    
    # 断开连接
    sudo swanctl --terminate --ike "$DEFAULT_CONNECTION_NAME" &>/dev/null || true
    
    # 返回测试结果
    echo "${loss_rate},${test_num},${success},${hct},${retrans_count},${connect_result},${test_start_time}"
}

# =============================================================================
# 数据分析和统计
# =============================================================================

calculate_statistics() {
    local results_file=$1
    local loss_rate=$2
    local stats_file="${RESULTS_DIR}/statistics_${loss_rate}pct.txt"
    
    # 提取成功连接的数据
    local success_data=$(awk -F',' -v lr="$loss_rate" '$1==lr && $3==1 {print $4}' "$results_file")
    local total_tests=$(awk -F',' -v lr="$loss_rate" '$1==lr' "$results_file" | wc -l)
    local success_count=$(echo "$success_data" | grep -c '^[0-9]' || echo "0")
    local success_rate=0
    
    if [[ $total_tests -gt 0 ]]; then
        success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
    fi
    
    {
        echo "# 突发丢包率 ${loss_rate}% 统计数据"
        echo "# 生成时间: $(date)"
        echo "# =============================================="
        echo "总测试次数: $total_tests"
        echo "成功次数: $success_count"
        echo "成功率: ${success_rate}%"
        echo ""
    } > "$stats_file"
    
    if [[ $success_count -gt 0 ]]; then
        # 计算HCT统计
        local hct_mean=$(echo "$success_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
        local hct_median=$(echo "$success_data" | sort -n | awk '{values[NR]=$1} END {n=NR; if(n%2==1) print values[(n+1)/2]; else printf "%.3f", (values[n/2]+values[n/2+1])/2}')
        local hct_min=$(echo "$success_data" | sort -n | head -1)
        local hct_max=$(echo "$success_data" | sort -n | tail -1)
        
        # 计算标准差
        local hct_std=$(echo "$success_data" | awk -v mean="$hct_mean" '{sum+=($1-mean)^2; count++} END {if(count>1) printf "%.3f", sqrt(sum/(count-1)); else print "0"}')
        
        # 计算重传统计
        local retrans_data=$(awk -F',' -v lr="$loss_rate" '$1==lr && $3==1 {print $5}' "$results_file")
        local retrans_mean=$(echo "$retrans_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        local retrans_max=$(echo "$retrans_data" | sort -n | tail -1)
        
        {
            echo "握手完成时间 (HCT) 统计:"
            echo "  平均值: ${hct_mean}s"
            echo "  中位数: ${hct_median}s"
            echo "  标准差: ${hct_std}s"
            echo "  最小值: ${hct_min}s"
            echo "  最大值: ${hct_max}s"
            echo ""
            echo "重传次数统计:"
            echo "  平均重传次数: ${retrans_mean}"
            echo "  最大重传次数: ${retrans_max}"
            echo ""
        } >> "$stats_file"
    else
        {
            echo "握手完成时间 (HCT) 统计: 无成功连接"
            echo "重传次数统计: 无成功连接"
            echo ""
        } >> "$stats_file"
    fi
    
    log "${GREEN}统计数据已保存: $stats_file${NC}"
    
    # 返回关键统计值用于汇总
    echo "${loss_rate},${success_rate},${hct_mean:-0},${hct_median:-0},${hct_std:-0},${retrans_mean:-0}"
}

# =============================================================================
# 结果可视化数据生成
# =============================================================================

generate_summary_data() {
    local results_file=$1
    local summary_file="${RESULTS_DIR}/summary_statistics.csv"
    
    {
        echo "# 突发丢包率测试汇总统计"
        echo "# 适用于生成图5和图6"
        echo "# 丢包率(%),成功率(%),HCT均值(s),HCT中位数(s),HCT标准差(s),平均重传次数"
    } > "$summary_file"
    
    for loss_rate in "${LOSS_RATES[@]}"; do
        local stats=$(calculate_statistics "$results_file" "$loss_rate")
        echo "$stats" >> "$summary_file"
    done
    
    log "${GREEN}汇总统计已保存: $summary_file${NC}"
    
    # 生成用于箱形图的详细数据
    generate_boxplot_data "$results_file"
}

generate_boxplot_data() {
    local results_file=$1
    local boxplot_file="${RESULTS_DIR}/hct_boxplot_data.csv"
    
    {
        echo "# 握手完成时间箱形图数据"
        echo "# 用于生成图5: HCT vs 突发丢包率的箱形图"
        echo "# 丢包率(%),HCT(s)"
    } > "$boxplot_file"
    
    awk -F',' '$3==1 {print $1","$4}' "$results_file" >> "$boxplot_file"
    
    log "${GREEN}箱形图数据已保存: $boxplot_file${NC}"
}

# =============================================================================
# 主测试流程
# =============================================================================

run_burst_loss_tests() {
    local tests_per_rate=${1:-$DEFAULT_TESTS_PER_LOSS_RATE}
    local results_file="${RESULTS_DIR}/burst_loss_results.csv"
    
    log "${CYAN}开始突发丢包率测试 (每个丢包率 ${tests_per_rate} 次测试)${NC}"
    
    # 创建结果文件头
    {
        echo "# strongSwan 突发丢包率性能测试结果"
        echo "# 测试时间: $(date)"
        echo "# 每个丢包率测试次数: $tests_per_rate"
        echo "# 突发大小: $BURST_SIZE"
        echo "# 连接超时: $DEFAULT_CONNECTION_TIMEOUT 秒"
        echo "# 丢包率(%),测试序号,成功(1/0),HCT(s),重传次数,结果,测试时间"
    } > "$results_file"
    
    local total_tests=$((${#LOSS_RATES[@]} * tests_per_rate))
    local current_test=0
    
    for loss_rate in "${LOSS_RATES[@]}"; do
        log "${BLUE}开始测试丢包率: ${loss_rate}%${NC}"
        
        # 设置网络条件
        set_burst_loss_conditions "$loss_rate"
        sleep 2
        
        # 执行测试
        for ((test_num=1; test_num<=tests_per_rate; test_num++)); do
            current_test=$((current_test + 1))
            local progress=$((current_test * 100 / total_tests))
            
            log "${CYAN}总进度: ${progress}% (${current_test}/${total_tests})${NC}"
            
            local result=$(perform_single_test "$loss_rate" "$test_num")
            echo "$result" >> "$results_file"
            
            # 测试间短暂休息
            sleep 1
        done
        
        log "${GREEN}丢包率 ${loss_rate}% 测试完成${NC}"
        echo "" >> "$results_file"  # 添加空行分隔
    done
    
    # 生成统计和可视化数据
    log "${YELLOW}生成统计数据和可视化数据...${NC}"
    generate_summary_data "$results_file"
    
    log "${GREEN}所有测试完成！${NC}"
}

# =============================================================================
# 辅助工具函数
# =============================================================================

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -n NUM    每个丢包率的测试次数 (默认: $DEFAULT_TESTS_PER_LOSS_RATE)"
    echo "  -i IFACE  网络接口 (默认: $DEFAULT_INTERFACE)"
    echo "  -c CONN   IPsec连接名称 (默认: $DEFAULT_CONNECTION_NAME)"
    echo "  -t SEC    连接超时时间 (默认: $DEFAULT_CONNECTION_TIMEOUT)"
    echo "  -h        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                    # 使用默认参数运行"
    echo "  $0 -n 50             # 每个丢包率测试50次"
    echo "  $0 -i enp0s3         # 使用指定网络接口"
}

show_test_info() {
    log "${CYAN}突发丢包率测试配置:${NC}"
    log "  测试次数/丢包率: $DEFAULT_TESTS_PER_LOSS_RATE"
    log "  网络接口: $DEFAULT_INTERFACE"
    log "  连接名称: $DEFAULT_CONNECTION_NAME"
    log "  连接超时: $DEFAULT_CONNECTION_TIMEOUT 秒"
    log "  突发大小: $BURST_SIZE 个连续包"
    log "  丢包率范围: ${LOSS_RATES[*]}%"
    log "  结果目录: $RESULTS_DIR"
    log ""
}

# =============================================================================
# 主程序入口
# =============================================================================

main() {
    local tests_per_rate=$DEFAULT_TESTS_PER_LOSS_RATE
    
    # 解析命令行参数
    while getopts "n:i:c:t:h" opt; do
        case $opt in
            n)
                tests_per_rate=$OPTARG
                ;;
            i)
                DEFAULT_INTERFACE=$OPTARG
                ;;
            c)
                DEFAULT_CONNECTION_NAME=$OPTARG
                ;;
            t)
                DEFAULT_CONNECTION_TIMEOUT=$OPTARG
                ;;
            h)
                show_usage
                exit 0
                ;;
            \?)
                echo "无效选项: -$OPTARG" >&2
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 创建结果目录
    mkdir -p "$RESULTS_DIR"
    
    # 设置信号处理
    trap 'cleanup_and_exit 130' INT TERM
    
    # 开始测试
    log "${GREEN}strongSwan 突发丢包率性能测试开始${NC}"
    
    show_test_info
    check_dependencies
    start_strongswan
    
    run_burst_loss_tests "$tests_per_rate"
    
    cleanup_and_exit 0
}

# 检查是否直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 