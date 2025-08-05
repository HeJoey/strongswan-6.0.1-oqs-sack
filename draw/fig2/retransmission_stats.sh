#!/bin/bash

# IKE消息重传统计脚本
# 专门用于统计和分析strongSwan的重传行为

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 默认配置
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly DEFAULT_CONNECTION_NAME="host-host"
readonly DEFAULT_LOG_DURATION=300  # 5分钟
readonly DEFAULT_TESTS=10

show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -c CONN     IPsec连接名称 (默认: $DEFAULT_CONNECTION_NAME)"
    echo "  -n NUM      测试次数 (默认: $DEFAULT_TESTS)"
    echo "  -d SEC      每次测试的日志监控时长 (默认: $DEFAULT_LOG_DURATION)"
    echo "  -o FILE     输出文件路径"
    echo "  -r          仅分析现有日志 (不执行新测试)"
    echo "  -l          实时监控重传 (持续模式)"
    echo "  -h          显示此帮助信息"
    echo ""
    echo "功能:"
    echo "  1. 自动测试连接并统计重传次数"
    echo "  2. 分析重传模式和频率"
    echo "  3. 生成重传统计报告"
    echo "  4. 支持实时监控模式"
    echo ""
    echo "示例:"
    echo "  $0                    # 执行默认测试"
    echo "  $0 -n 20             # 执行20次测试"
    echo "  $0 -l                # 实时监控重传"
    echo "  $0 -r                # 只分析现有日志"
}

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查strongSwan状态
check_strongswan() {
    if ! systemctl is-active --quiet strongswan; then
        log "${RED}错误: strongSwan未运行${NC}"
        exit 1
    fi
}

# 清理现有连接
cleanup_connections() {
    log "${YELLOW}清理现有连接...${NC}"
    swanctl --terminate --ike "$DEFAULT_CONNECTION_NAME" &>/dev/null || true
    sleep 2
}

# 统计重传次数
count_retransmissions() {
    local log_start_time=$1
    local log_duration=${2:-60}
    local end_time=$(date -d "$log_start_time + $log_duration seconds" '+%Y-%m-%d %H:%M:%S')
    
    # 使用journalctl统计重传
    local retrans_total=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "retransmit [0-9]+ of request" | wc -l)
    
    # 统计不同类型的重传
    local ike_init_retrans=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "retransmit.*IKE_SA_INIT" | wc -l)
    
    local ike_auth_retrans=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "retransmit.*IKE_AUTH" | wc -l)
    
    local intermediate_retrans=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "retransmit.*INTERMEDIATE" | wc -l)
    
    # 统计分片重传
    local fragment_retrans=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "retransmit.*fragment|selective.*retransmission" | wc -l)
    
    echo "$retrans_total,$ike_init_retrans,$ike_auth_retrans,$intermediate_retrans,$fragment_retrans"
}

# 获取连接详细信息
get_connection_info() {
    local log_start_time=$1
    local log_duration=${2:-60}
    local end_time=$(date -d "$log_start_time + $log_duration seconds" '+%Y-%m-%d %H:%M:%S')
    
    # 检查连接是否成功
    local connection_success=0
    if journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -q "CHILD_SA.*established"; then
        connection_success=1
    fi
    
    # 统计使用的算法
    local ike_algo=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -o "IKE proposal: [^,]*" | head -1 | cut -d: -f2 | xargs || echo "unknown")
    
    local esp_algo=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -o "ESP proposal: [^,]*" | head -1 | cut -d: -f2 | xargs || echo "unknown")
    
    # 统计消息交换数
    local ike_messages=$(journalctl --since "$log_start_time" --until "$end_time" -u strongswan 2>/dev/null | \
        grep -E "sending|received" | grep -E "IKE_SA_INIT|IKE_AUTH|IKE_INTERMEDIATE" | wc -l)
    
    echo "$connection_success,$ike_algo,$esp_algo,$ike_messages"
}

# 执行单次测试
perform_single_test() {
    local test_num=$1
    local monitor_duration=${2:-$DEFAULT_LOG_DURATION}
    
    log "${CYAN}测试 ${test_num}: 开始连接测试${NC}"
    
    # 清理现有连接
    cleanup_connections
    
    # 记录开始时间
    local test_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 发起连接
    local connection_start=$(date +%s.%3N)
    local connection_result="FAILED"
    local hct="0"
    
    if swanctl --initiate --child "$DEFAULT_CONNECTION_NAME" &>/dev/null; then
        # 等待连接建立
        sleep 5
        if swanctl --list-sas | grep -q "ESTABLISHED"; then
            local connection_end=$(date +%s.%3N)
            hct=$(echo "scale=3; $connection_end - $connection_start" | bc)
            connection_result="SUCCESS"
            log "${GREEN}连接建立成功: HCT=${hct}s${NC}"
        else
            log "${YELLOW}连接建立失败或超时${NC}"
        fi
    else
        log "${RED}连接发起失败${NC}"
    fi
    
    # 等待指定时间以收集重传数据
    sleep $monitor_duration
    
    # 统计重传数据
    local retrans_stats=$(count_retransmissions "$test_start_time" $((monitor_duration + 10)))
    local conn_info=$(get_connection_info "$test_start_time" $((monitor_duration + 10)))
    
    # 断开连接
    swanctl --terminate --ike "$DEFAULT_CONNECTION_NAME" &>/dev/null || true
    
    # 返回测试结果：测试号,连接结果,HCT,总重传,IKE_INIT重传,IKE_AUTH重传,INTERMEDIATE重传,分片重传,连接成功,IKE算法,ESP算法,消息数
    echo "${test_num},${connection_result},${hct},${retrans_stats},${conn_info},${test_start_time}"
}

# 运行重传测试
run_retransmission_tests() {
    local num_tests=${1:-$DEFAULT_TESTS}
    local monitor_duration=${2:-$DEFAULT_LOG_DURATION}
    local output_file=${3:-"${SCRIPT_DIR}/retransmission_stats_${TIMESTAMP}.csv"}
    
    log "${CYAN}开始重传统计测试 (${num_tests} 次测试)${NC}"
    
    # 创建输出文件头
    {
        echo "# strongSwan IKE消息重传统计"
        echo "# 测试时间: $(date)"
        echo "# 测试次数: $num_tests"
        echo "# 监控时长: $monitor_duration 秒"
        echo "# 测试号,连接结果,HCT(s),总重传次数,IKE_INIT重传,IKE_AUTH重传,INTERMEDIATE重传,分片重传,连接成功(1/0),IKE算法,ESP算法,消息数,测试时间"
    } > "$output_file"
    
    for ((i=1; i<=num_tests; i++)); do
        local progress=$((i * 100 / num_tests))
        log "${BLUE}进度: ${progress}% (${i}/${num_tests})${NC}"
        
        local result=$(perform_single_test "$i" "$monitor_duration")
        echo "$result" >> "$output_file"
        
        # 测试间休息
        sleep 2
    done
    
    log "${GREEN}测试完成！结果保存到: $output_file${NC}"
    
    # 生成统计报告
    generate_stats_report "$output_file"
}

# 生成统计报告
generate_stats_report() {
    local results_file=$1
    local report_file="${results_file%.csv}_report.txt"
    
    log "${YELLOW}生成统计报告...${NC}"
    
    # 基本统计
    local total_tests=$(grep -v '^#' "$results_file" | wc -l)
    local successful_tests=$(awk -F',' '$9==1' "$results_file" | wc -l)
    local success_rate=$(echo "scale=2; $successful_tests * 100 / $total_tests" | bc 2>/dev/null || echo "0")
    
    # 重传统计
    local avg_total_retrans=$(awk -F',' '$9==1 {sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$results_file")
    local max_total_retrans=$(awk -F',' '$9==1 {if($4>max) max=$4} END {print max+0}' "$results_file")
    
    local avg_init_retrans=$(awk -F',' '$9==1 {sum+=$5; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$results_file")
    local avg_auth_retrans=$(awk -F',' '$9==1 {sum+=$6; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$results_file")
    local avg_intermediate_retrans=$(awk -F',' '$9==1 {sum+=$7; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$results_file")
    local avg_fragment_retrans=$(awk -F',' '$9==1 {sum+=$8; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$results_file")
    
    # HCT统计
    local avg_hct=$(awk -F',' '$9==1 {sum+=$3; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}' "$results_file")
    local min_hct=$(awk -F',' '$9==1 {if(NR==1 || $3<min) min=$3} END {printf "%.3f", min+0}' "$results_file")
    local max_hct=$(awk -F',' '$9==1 {if($3>max) max=$3} END {printf "%.3f", max+0}' "$results_file")
    
    {
        echo "strongSwan IKE消息重传统计报告"
        echo "=================================="
        echo "生成时间: $(date)"
        echo "数据文件: $results_file"
        echo ""
        echo "基本统计:"
        echo "  总测试次数: $total_tests"
        echo "  成功连接: $successful_tests"
        echo "  成功率: ${success_rate}%"
        echo ""
        echo "握手完成时间 (HCT) 统计:"
        echo "  平均HCT: ${avg_hct}s"
        echo "  最小HCT: ${min_hct}s"
        echo "  最大HCT: ${max_hct}s"
        echo ""
        echo "重传统计 (仅成功连接):"
        echo "  平均总重传次数: $avg_total_retrans"
        echo "  最大总重传次数: $max_total_retrans"
        echo "  平均IKE_INIT重传: $avg_init_retrans"
        echo "  平均IKE_AUTH重传: $avg_auth_retrans"
        echo "  平均INTERMEDIATE重传: $avg_intermediate_retrans"
        echo "  平均分片重传: $avg_fragment_retrans"
        echo ""
        echo "算法使用统计:"
    } > "$report_file"
    
    # 算法统计
    awk -F',' '$9==1 {print $10}' "$results_file" | sort | uniq -c | sort -nr | \
        awk '{printf "  %s: %d次\n", $2, $1}' >> "$report_file"
    
    echo "" >> "$report_file"
    echo "详细重传分布:" >> "$report_file"
    awk -F',' '$9==1 {print $4}' "$results_file" | sort -n | uniq -c | \
        awk '{printf "  %d次重传: %d个测试\n", $2, $1}' >> "$report_file"
    
    log "${GREEN}统计报告已保存: $report_file${NC}"
}

# 实时监控重传
monitor_retransmissions() {
    log "${CYAN}开始实时监控重传活动...${NC}"
    log "${YELLOW}按 Ctrl+C 停止监控${NC}"
    
    # 监控日志变化
    journalctl -u strongswan -f --since "1 minute ago" | \
        grep --line-buffered -E "retransmit|fragment|selective" | \
        while read -r line; do
            local timestamp=$(echo "$line" | awk '{print $1, $2, $3}')
            local message=$(echo "$line" | cut -d' ' -f4-)
            
            if echo "$message" | grep -q "retransmit"; then
                log "${RED}[重传] $timestamp: $message${NC}"
            elif echo "$message" | grep -q "fragment"; then
                log "${YELLOW}[分片] $timestamp: $message${NC}"
            elif echo "$message" | grep -q "selective"; then
                log "${BLUE}[选择性] $timestamp: $message${NC}"
            fi
        done
}

# 分析现有日志
analyze_existing_logs() {
    local duration=${1:-3600}  # 默认分析最近1小时
    local output_file=${2:-"${SCRIPT_DIR}/log_analysis_${TIMESTAMP}.txt"}
    
    log "${CYAN}分析最近 ${duration} 秒的日志...${NC}"
    
    local since_time=$(date -d "$duration seconds ago" '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "strongSwan 日志分析报告"
        echo "======================"
        echo "分析时间: $(date)"
        echo "时间范围: $since_time 至 $(date '+%Y-%m-%d %H:%M:%S')"
        echo "分析时长: $duration 秒"
        echo ""
        
        echo "重传活动统计:"
        echo "=============="
        local total_retrans=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "retransmit.*of request" || echo "0")
        echo "总重传次数: $total_retrans"
        
        local init_retrans=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "retransmit.*IKE_SA_INIT" || echo "0")
        echo "IKE_SA_INIT重传: $init_retrans"
        
        local auth_retrans=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "retransmit.*IKE_AUTH" || echo "0")
        echo "IKE_AUTH重传: $auth_retrans"
        
        echo ""
        echo "分片活动统计:"
        echo "=============="
        local fragment_count=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "fragment" || echo "0")
        echo "分片相关日志: $fragment_count"
        
        local selective_retrans=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "selective.*retransmission" || echo "0")
        echo "选择性重传: $selective_retrans"
        
        echo ""
        echo "连接活动统计:"
        echo "=============="
        local connections=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "CHILD_SA.*established" || echo "0")
        echo "成功连接: $connections"
        
        local failures=$(journalctl --since "$since_time" -u strongswan 2>/dev/null | \
            grep -c "giving up after.*retransmits" || echo "0")
        echo "连接失败: $failures"
        
    } > "$output_file"
    
    log "${GREEN}日志分析完成: $output_file${NC}"
}

# 主程序
main() {
    local connection_name=$DEFAULT_CONNECTION_NAME
    local num_tests=$DEFAULT_TESTS
    local log_duration=$DEFAULT_LOG_DURATION
    local output_file=""
    local analyze_only=false
    local monitor_mode=false
    
    # 解析命令行参数
    while getopts "c:n:d:o:rlh" opt; do
        case $opt in
            c)
                connection_name=$OPTARG
                ;;
            n)
                num_tests=$OPTARG
                ;;
            d)
                log_duration=$OPTARG
                ;;
            o)
                output_file=$OPTARG
                ;;
            r)
                analyze_only=true
                ;;
            l)
                monitor_mode=true
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
    
    # 设置默认输出文件
    if [[ -z "$output_file" ]]; then
        if [[ "$analyze_only" == "true" ]]; then
            output_file="${SCRIPT_DIR}/log_analysis_${TIMESTAMP}.txt"
        else
            output_file="${SCRIPT_DIR}/retransmission_stats_${TIMESTAMP}.csv"
        fi
    fi
    
    log "${GREEN}strongSwan IKE消息重传统计脚本${NC}"
    
    # 处理不同模式
    if [[ "$monitor_mode" == "true" ]]; then
        check_strongswan
        monitor_retransmissions
    elif [[ "$analyze_only" == "true" ]]; then
        analyze_existing_logs "$log_duration" "$output_file"
    else
        check_strongswan
        DEFAULT_CONNECTION_NAME="$connection_name"
        run_retransmission_tests "$num_tests" "$log_duration" "$output_file"
    fi
}

# 设置信号处理
trap 'log "${YELLOW}用户中断，正在清理...${NC}"; cleanup_connections; exit 130' INT TERM

# 执行主程序
main "$@" 