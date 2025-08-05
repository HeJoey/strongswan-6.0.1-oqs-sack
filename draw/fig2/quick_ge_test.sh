#!/bin/bash

# 快速GE模型测试脚本
# 用于验证GE模型参数设置和IPsec性能测试

set -e

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
    echo "快速GE模型测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -l, --loss-rate RATE     错误率 (0-1, 默认: 0.05)"
    echo "  -b, --burst-length LEN   突发长度 (默认: 5)"
    echo "  -t, --bad-state-time T   坏状态时间比例 (默认: 0.4)"
    echo "  -m, --model MODEL        模型类型: 2param, 3param (默认: 3param)"
    echo "  -n, --test-count N       测试次数 (默认: 20)"
    echo "  -o, --output FILE        输出文件 (默认: quick_ge_test.csv)"
    echo "  -h, --help               显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l 0.05 -b 5 -t 0.4    # 5%错误率，突发长度5，坏状态时间40%"
    echo "  $0 -l 0.1 -b 3 -m 2param  # 10%错误率，突发长度3，双参数模型"
    echo ""
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0 [选项]"
        exit 1
    fi
}

# 计算GE参数并设置网络条件
setup_ge_network() {
    local loss_rate=$1
    local burst_length=$2
    local bad_state_time=$3
    local model_type=$4
    
    log_info "设置GE模型网络条件..."
    log_info "错误率: ${loss_rate}, 突发长度: ${burst_length}, 坏状态时间: ${bad_state_time}, 模型: ${model_type}"
    
    # 计算GE参数
    local ge_params
    if [[ $model_type == "2param" ]]; then
        ge_params=$(python3 ./ge_parameter_calculator.py --model 2param --error-rate $loss_rate --burst-length $burst_length --tc-command 2>/dev/null | grep "tc qdisc" | sed 's/^  //')
    else
        ge_params=$(python3 ./ge_parameter_calculator.py --model 3param --error-rate $loss_rate --burst-length $burst_length --bad-state-time $bad_state_time --tc-command 2>/dev/null | grep "tc qdisc" | sed 's/^  //')
    fi
    
    if [[ -z $ge_params ]]; then
        log_error "无法计算GE参数，请检查输入参数"
        return 1
    fi
    
    log_info "GE参数: $ge_params"
    
    # 清除现有网络条件
    sudo ./set_realistic_network.sh -c
    
    # 设置新的网络条件
    if [[ $model_type == "2param" ]]; then
        # 双参数模型使用burst模式
        sudo ./set_realistic_network.sh -l $(echo "$loss_rate * 100" | bc) -m burst -b $burst_length
    else
        # 三参数模型使用gilbert模式
        sudo ./set_realistic_network.sh -l $(echo "$loss_rate * 100" | bc) -m gilbert -b $burst_length -t $bad_state_time
    fi
    
    sleep 2
    log_success "网络条件设置完成"
}

# 运行IPsec测试
run_ipsec_test() {
    local loss_rate=$1
    local test_count=$2
    local output_file=$3
    
    log_info "运行IPsec连接测试..."
    
    # 运行连接测试
    sudo ./connection_test.sh -l "$(echo "$loss_rate * 100" | bc)" -n $test_count -o "${output_file}_temp.csv"
    
    # 处理结果
    if [[ -f "${output_file}_temp.csv" ]]; then
        # 添加GE模型信息到结果中
        while IFS=',' read -r loss test_num result hct retrans; do
            if [[ $loss != "#"* && $loss != "错误率"* ]]; then
                echo "$loss,$test_num,$result,$hct,$retrans" >> "$output_file"
            fi
        done < "${output_file}_temp.csv"
        
        rm -f "${output_file}_temp.csv"
        log_success "IPsec测试完成"
    else
        log_warning "IPsec测试失败"
    fi
}

# 显示测试结果
show_results() {
    local output_file=$1
    
    if [[ ! -f "$output_file" ]]; then
        log_warning "没有找到测试结果文件"
        return
    fi
    
    log_info "测试结果统计:"
    echo "========================================"
    
    # 计算统计信息
    local total_tests=$(awk -F',' 'NR>1 && $1!~/^#/ {count++} END {print count+0}' "$output_file")
    local success_count=$(awk -F',' 'NR>1 && $1!~/^#/ && $3=="SUCCESS" {count++} END {print count+0}' "$output_file")
    local success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc 2>/dev/null || echo "0")
    local avg_hct=$(awk -F',' 'NR>1 && $1!~/^#/ && $3=="SUCCESS" {sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$output_file")
    local avg_retrans=$(awk -F',' 'NR>1 && $1!~/^#/ {sum+=$5; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$output_file")
    
    echo "总测试次数: $total_tests"
    echo "成功次数: $success_count"
    echo "成功率: ${success_rate}%"
    echo "平均HCT: ${avg_hct}ms"
    echo "平均重传次数: ${avg_retrans}"
    echo "========================================"
}

# 主函数
main() {
    # 默认参数
    local loss_rate=0.05
    local burst_length=5
    local bad_state_time=0.4
    local model_type="3param"
    local test_count=20
    local output_file="quick_ge_test.csv"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--loss-rate)
                loss_rate="$2"
                shift 2
                ;;
            -b|--burst-length)
                burst_length="$2"
                shift 2
                ;;
            -t|--bad-state-time)
                bad_state_time="$2"
                shift 2
                ;;
            -m|--model)
                model_type="$2"
                shift 2
                ;;
            -n|--test-count)
                test_count="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
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
    
    # 检查权限
    check_root
    
    log_info "开始快速GE模型测试"
    log_info "参数: 错误率=${loss_rate}, 突发长度=${burst_length}, 坏状态时间=${bad_state_time}, 模型=${model_type}"
    log_info "测试次数: ${test_count}, 输出文件: ${output_file}"
    echo ""
    
    # 创建输出文件头
    cat > "$output_file" << EOF
# 快速GE模型IPsec性能测试结果
# 生成时间: $(date)
# 参数: 错误率=${loss_rate}, 突发长度=${burst_length}, 坏状态时间=${bad_state_time}, 模型=${model_type}
# 格式: 错误率(%),测试序号,结果,HCT(ms),重传次数
EOF
    
    # 设置网络条件
    if ! setup_ge_network $loss_rate $burst_length $bad_state_time $model_type; then
        log_error "网络条件设置失败"
        exit 1
    fi
    
    # 运行IPsec测试
    run_ipsec_test $loss_rate $test_count $output_file
    
    # 清除网络条件
    sudo ./set_realistic_network.sh -c
    
    # 显示结果
    show_results $output_file
    
    log_success "快速GE模型测试完成！"
    log_success "结果已保存到: $output_file"
}

# 清理函数
cleanup() {
    log_info "脚本执行完成"
}

# 设置信号处理
trap cleanup EXIT

# 运行主函数
main "$@" 