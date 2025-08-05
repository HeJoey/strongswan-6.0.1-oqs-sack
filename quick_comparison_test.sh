#!/bin/bash

# strongSwan 分片重传快速对比测试脚本
# 用于快速比较不同网络条件下的连接效果

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
    sudo tc qdisc del dev $interface root 2>/dev/null || true
}

# 设置网络条件
setup_network_condition() {
    local interface=$1
    local delay=$2
    local loss=$3
    
    cleanup_network $interface
    
    if [[ $delay -gt 0 ]] && [[ $loss -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem delay ${delay}ms loss ${loss}%
    elif [[ $delay -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem delay ${delay}ms
    elif [[ $loss -gt 0 ]]; then
        sudo tc qdisc add dev $interface root netem loss ${loss}%
    fi
}

# 重启strongSwan服务
restart_strongswan() {
    sudo systemctl restart strongswan
    sleep 3
}

# 带超时的连接测试
test_connection() {
    local conn_name=$1
    local test_num=$2
    local timeout_seconds=$3
    
    local start_time=$(date +%s.%N)
    
    local result
    local retransmission_count=0
    
    # 使用timeout命令限制连接时间
    if timeout $timeout_seconds sudo swanctl --initiate --ike $conn_name >/dev/null 2>&1; then
        result="SUCCESS"
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            result="TIMEOUT"
        else
            result="FAILED"
        fi
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc)
    
    local status="DOWN"
    if sudo swanctl --list-sas | grep -q "$conn_name"; then
        status="UP"
    fi
    
    # 统计重传次数
    local log_file="/var/log/strongswan.log"
    if [[ -f $log_file ]]; then
        retransmission_count=$(tail -100 $log_file | grep -c "retransmit" || echo "0")
    fi
    
    # 区分一次成功和重传成功
    if [[ $result == "SUCCESS" ]] && [[ $status == "UP" ]]; then
        # 使用bc进行浮点数比较
        if (( $(echo "$duration < 1000" | bc -l) )); then
            echo "$test_num,SUCCESS_ONE_SHOT,${duration},$status,0"
        else
            echo "$test_num,SUCCESS_RETRANSMIT,${duration},$status,$retransmission_count"
        fi
    elif [[ $result == "TIMEOUT" ]]; then
        echo "$test_num,TIMEOUT,${duration},$status,$retransmission_count"
    else
        echo "$test_num,FAILED,${duration},$status,$retransmission_count"
    fi
    
    sudo swanctl --terminate --ike $conn_name >/dev/null 2>&1 || true
    sleep 1
}

# 运行测试场景
run_test_scenario() {
    local interface=$1
    local conn_name=$2
    local delay=$3
    local loss=$4
    local test_count=$5
    local scenario_name=$6
    local timeout_seconds=$7
    
    log_info "=== 测试场景: $scenario_name ==="
    log_info "网络条件: 延迟=${delay}ms, 丢包率=${loss}%, 超时=${timeout_seconds}s"
    
    # 设置网络条件
    setup_network_condition $interface $delay $loss
    
    # 重启服务
    restart_strongswan
    
    # 创建结果文件
    local results_file="/tmp/comparison_${scenario_name}_$(date +%Y%m%d_%H%M%S).txt"
    echo "测试编号,结果,连接时间(ms),状态,重传次数" > $results_file
    
    local success_one_shot=0
    local success_retransmit=0
    local failed_count=0
    local timeout_count=0
    local total_retransmissions=0
    
    # 执行测试
    for ((i=1; i<=$test_count; i++)); do
        local result=$(test_connection $conn_name $i $timeout_seconds)
        echo "$result" >> $results_file
        
        # 统计结果
        if echo "$result" | grep -q "SUCCESS_ONE_SHOT"; then
            success_one_shot=$((success_one_shot + 1))
        elif echo "$result" | grep -q "SUCCESS_RETRANSMIT"; then
            success_retransmit=$((success_retransmit + 1))
            local retransmissions=$(echo "$result" | cut -d',' -f5)
            total_retransmissions=$((total_retransmissions + retransmissions))
        elif echo "$result" | grep -q "TIMEOUT"; then
            timeout_count=$((timeout_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
        
        if [[ $((i % 5)) -eq 0 ]]; then
            local total_success=$((success_one_shot + success_retransmit))
            log_info "进度: $i/$test_count (一次成功: $success_one_shot, 重传成功: $success_retransmit, 失败: $failed_count, 超时: $timeout_count)"
        fi
    done
    
    # 计算统计结果
    local total_success=$((success_one_shot + success_retransmit))
    local success_rate=$(echo "scale=2; $total_success * 100 / $test_count" | bc)
    local one_shot_rate=$(echo "scale=2; $success_one_shot * 100 / $test_count" | bc)
    
    # 计算平均时间
    local avg_one_shot=0
    local avg_retransmit=0
    local avg_failed=0
    local avg_timeout=0
    
    # 分析结果文件计算平均时间
    while IFS=',' read -r test_num result duration status retransmissions; do
        case $result in
            "SUCCESS_ONE_SHOT")
                if (( $(echo "$avg_one_shot == 0" | bc -l) )); then
                    avg_one_shot=$duration
                else
                    avg_one_shot=$(echo "scale=3; ($avg_one_shot + $duration) / 2" | bc)
                fi
                ;;
            "SUCCESS_RETRANSMIT")
                if (( $(echo "$avg_retransmit == 0" | bc -l) )); then
                    avg_retransmit=$duration
                else
                    avg_retransmit=$(echo "scale=3; ($avg_retransmit + $duration) / 2" | bc)
                fi
                ;;
            "FAILED")
                if (( $(echo "$avg_failed == 0" | bc -l) )); then
                    avg_failed=$duration
                else
                    avg_failed=$(echo "scale=3; ($avg_failed + $duration) / 2" | bc)
                fi
                ;;
            "TIMEOUT")
                if (( $(echo "$avg_timeout == 0" | bc -l) )); then
                    avg_timeout=$duration
                else
                    avg_timeout=$(echo "scale=3; ($avg_timeout + $duration) / 2" | bc)
                fi
                ;;
        esac
    done < $results_file
    
    # 输出结果
    echo "结果: 成功率=${success_rate}% (一次成功: ${one_shot_rate}%), 平均重传次数: $(echo "scale=2; $total_retransmissions / $success_retransmit" | bc 2>/dev/null || echo "0")"
    echo "      一次成功平均时间: ${avg_one_shot}ms, 重传成功平均时间: ${avg_retransmit}ms"
    echo ""
    
    # 保存结果
    echo "$scenario_name,$delay,$loss,$test_count,$success_one_shot,$success_retransmit,$failed_count,$timeout_count,$success_rate,$one_shot_rate,$avg_one_shot,$avg_retransmit,$total_retransmissions" >> "/tmp/comparison_summary.txt"
}

# 显示帮助信息
show_help() {
    cat << EOF
strongSwan 分片重传快速对比测试脚本

用法: $0 [选项] <连接名称>

选项:
    -i, --interface <接口>    指定网络接口 (默认: 自动检测)
    -n, --num <次数>          每个场景的测试次数 (默认: 20)
    -t, --timeout <秒>        连接超时时间 (默认: 30)
    -h, --help               显示此帮助信息

示例:
    $0 site-to-site
    $0 -i eth0 -n 30 -t 60 site-to-site

说明:
    - 脚本会自动测试多个网络场景
    - 生成对比报告
    - 区分一次成功和重传成功
    - 设置连接超时机制
    - 适合快速评估分片重传效果

EOF
}

# 主函数
main() {
    check_root
    
    local interface=""
    local conn_name=""
    local test_count=20
    local timeout_seconds=30
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
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
    
    if [[ -z "$conn_name" ]]; then
        log_error "请指定连接名称"
        show_help
        exit 1
    fi
    
    if [[ -z "$interface" ]]; then
        interface=$(get_default_interface)
        log_info "使用默认网络接口: $interface"
    fi
    
    # 检查连接是否存在
    if ! sudo swanctl --list-conns | grep -q "$conn_name"; then
        log_error "连接 '$conn_name' 不存在，请检查配置"
        log_info "可用的连接:"
        sudo swanctl --list-conns | grep -E "^[[:space:]]*[^[:space:]]+" | head -10
        exit 1
    fi
    
    log_info "=== 开始快速对比测试 ==="
    log_info "网络接口: $interface"
    log_info "连接名称: $conn_name"
    log_info "每个场景测试次数: $test_count"
    log_info "连接超时: ${timeout_seconds}s"
    echo ""
    
    # 创建汇总文件
    echo "场景名称,延迟(ms),丢包率(%),测试次数,一次成功,重传成功,失败次数,超时次数,成功率(%),一次成功率(%),一次成功平均时间(ms),重传成功平均时间(ms),总重传次数" > "/tmp/comparison_summary.txt"
    
    # 定义测试场景
    local scenarios=(
        "正常网络:0:0"
        "轻微延迟:50:0"
        "中等延迟:200:0"
        "严重延迟:500:0"
        "轻微丢包:0:5"
        "中等丢包:0:15"
        "严重丢包:0:30"
        "轻微延迟+丢包:50:5"
        "中等延迟+丢包:200:15"
        "严重延迟+丢包:500:30"
    )
    
    # 执行测试场景
    for scenario in "${scenarios[@]}"; do
        IFS=':' read -r name delay loss <<< "$scenario"
        run_test_scenario $interface $conn_name $delay $loss $test_count "$name" $timeout_seconds
    done
    
    # 生成对比报告
    local report_file="comparison_report_$(date +%Y%m%d_%H%M%S).txt"
    cat > $report_file << EOF
strongSwan 分片重传对比测试报告
生成时间: $(date)
测试环境: $(uname -a)

测试配置:
- 网络接口: $interface
- 连接名称: $conn_name
- 每个场景测试次数: $test_count
- 连接超时: ${timeout_seconds}s

测试结果对比:
$(cat /tmp/comparison_summary.txt)

测试场景说明:
1. 正常网络: 无延迟，无丢包
2. 轻微延迟: 50ms延迟
3. 中等延迟: 200ms延迟
4. 严重延迟: 500ms延迟
5. 轻微丢包: 5%丢包率
6. 中等丢包: 15%丢包率
7. 严重丢包: 30%丢包率
8. 轻微延迟+丢包: 50ms延迟 + 5%丢包
9. 中等延迟+丢包: 200ms延迟 + 15%丢包
10. 严重延迟+丢包: 500ms延迟 + 30%丢包

分析建议:
- 比较不同网络条件下的成功率
- 观察一次成功率和重传成功率的变化
- 分析连接时间的变化趋势
- 评估分片重传机制的效果
- 注意超时和失败情况的比例
EOF
    
    # 清理网络条件
    cleanup_network $interface
    
    log_success "对比测试完成！"
    log_success "报告已保存到: $report_file"
    
    # 显示简要结果
    echo ""
    echo "=== 简要结果 ==="
    tail -n +2 /tmp/comparison_summary.txt | while IFS=',' read -r name delay loss count one_shot retransmit failed timeout rate one_shot_rate avg_one avg_retransmit total_retrans; do
        printf "%-20s: 成功率=%-6s, 一次成功率=%-6s, 一次成功=%-8s, 重传成功=%-8s\n" "$name" "${rate}%" "${one_shot_rate}%" "${avg_one}ms" "${avg_retransmit}ms"
    done
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 