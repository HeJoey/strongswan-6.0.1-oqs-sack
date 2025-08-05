#!/bin/bash

# Gilbert-Elliot模型IPsec性能测试脚本
# 基于NTIA技术备忘录TM-23-565的科学参数设置

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${PURPLE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo "Gilbert-Elliot模型IPsec性能测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --mode MODE              测试模式: basic, knee, full (默认: basic)"
    echo "  --loss-range RATES       错误率范围 (默认: 0 2 5 8 10 12 15 18 20)"
    echo "  --burst-length LENGTH    突发长度 (默认: 5)"
    echo "  --bad-state-time TIME    坏状态时间比例 (默认: 0.4)"
    echo "  --test-count N           每个配置测试次数 (默认: 50)"
    echo "  --output FILE            输出文件前缀 (默认: ge_test)"
    echo "  --model MODEL            GE模型类型: 2param, 3param, 4param (默认: 3param)"
    echo "  --interface IFACE        网络接口 (默认: ens33)"
    echo "  --target-ip IP           目标IP地址 (默认: 192.168.31.136)"
    echo "  --help                   显示此帮助信息"
    echo ""
    echo "测试模式说明:"
    echo "  basic: 基础性能测试，快速扫描"
    echo "  knee:  拐点精确定位，密集测试"
    echo "  full:  完整性能分析，多参数组合"
    echo ""
    echo "示例:"
    echo "  $0 --mode basic --loss-range '0 5 10 15 20'"
    echo "  $0 --mode knee --loss-range '8 9 10 11 12' --test-count 100"
    echo "  $0 --mode full --output my_ge_test"
    echo ""
    echo "输出文件:"
    echo "  - 原始数据: {output}_raw.csv"
    echo "  - 统计结果: {output}_stats.csv"
    echo "  - 拐点分析: {output}_knee.csv"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0 [选项]"
        exit 1
    fi
}

# 检查依赖脚本
check_dependencies() {
    local missing_deps=()
    
    if [[ ! -f "./set_realistic_network.sh" ]]; then
        missing_deps+=("set_realistic_network.sh")
    fi
    
    if [[ ! -f "./connection_test.sh" ]]; then
        missing_deps+=("connection_test.sh")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少依赖脚本: ${missing_deps[*]}"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 设置网络条件
set_network_conditions() {
    local loss_rate=$1
    local burst_length=$2
    local bad_state_time=$3
    local model_type=$4
    
    log_info "设置网络条件: 错误率=${loss_rate}%, 突发长度=${burst_length}, 坏状态时间=${bad_state_time}, 模型=${model_type}"
    
    case $model_type in
        "2param")
            # 双参数模型: 错误率 + 突发长度
            sudo ./set_realistic_network.sh -l $loss_rate -m burst -b $burst_length
            ;;
        "3param")
            # 三参数模型: 错误率 + 突发长度 + 坏状态时间
            sudo ./set_realistic_network.sh -l $loss_rate -m gilbert -b $burst_length -t $bad_state_time
            ;;
        "4param")
            # 四参数模型: 错误率 + 突发长度 + 坏状态时间 + 坏状态无错误概率
            local h_value=$(echo "scale=2; 1 - $loss_rate * 0.8" | bc)
            sudo ./set_realistic_network.sh -l $loss_rate -m 4state -b $burst_length -t $bad_state_time -h $h_value
            ;;
        *)
            log_error "不支持的模型类型: $model_type"
            exit 1
            ;;
    esac
    
    sleep 2  # 等待设置生效
}

# 运行IPsec测试
run_ipsec_test() {
    local loss_rate=$1
    local burst_length=$2
    local bad_state_time=$3
    local test_count=$4
    local output_file=$5
    local model_type=$6
    
    log_step "运行IPsec测试: 错误率=${loss_rate}%, 测试次数=${test_count}"
    
    # 运行连接测试
    sudo ./connection_test.sh -l "$loss_rate" -n $test_count -o "${output_file}_temp.csv"
    
    # 添加GE模型参数到结果中
    if [[ -f "${output_file}_temp.csv" ]]; then
        # 读取原始数据并添加GE参数
        while IFS=',' read -r loss test_num result hct retrans; do
            if [[ $loss != "#"* && $loss != "错误率"* ]]; then
                echo "$loss,$burst_length,$bad_state_time,$test_num,$result,$hct,$retrans,$model_type" >> "${output_file}_raw.csv"
            fi
        done < "${output_file}_temp.csv"
        
        rm -f "${output_file}_temp.csv"
        log_success "测试完成: ${loss_rate}% 错误率"
    else
        log_warning "测试失败: ${loss_rate}% 错误率"
    fi
}

# 计算统计信息
calculate_statistics() {
    local output_file=$1
    
    log_info "计算统计信息..."
    
    # 创建统计文件头
    cat > "${output_file}_stats.csv" << EOF
# GE模型IPsec性能统计结果
# 生成时间: $(date)
# 格式: 错误率(%),突发长度,坏状态时间,模型类型,测试次数,成功率(%),平均HCT(ms),最大HCT(ms),最小HCT(ms),平均重传次数,最大重传次数
EOF
    
    # 按配置分组计算统计
    awk -F',' '
    NR>1 && $1!~/^#/ {
        key = $1 "," $2 "," $3 "," $8
        count[key]++
        if ($5 == "SUCCESS") success[key]++
        hct_sum[key] += $6
        retrans_sum[key] += $7
        if ($6 > hct_max[key] || hct_max[key] == "") hct_max[key] = $6
        if ($6 < hct_min[key] || hct_min[key] == "") hct_min[key] = $6
        if ($7 > retrans_max[key] || retrans_max[key] == "") retrans_max[key] = $7
    }
    END {
        for (key in count) {
            split(key, parts, ",")
            success_rate = (success[key] / count[key]) * 100
            avg_hct = hct_sum[key] / count[key]
            avg_retrans = retrans_sum[key] / count[key]
            printf "%s,%s,%s,%s,%d,%.2f,%.3f,%.3f,%.3f,%.2f,%d\n", 
                   parts[1], parts[2], parts[3], parts[4], count[key], 
                   success_rate, avg_hct, hct_max[key], hct_min[key], 
                   avg_retrans, retrans_max[key]
        }
    }' "${output_file}_raw.csv" | sort -t',' -k1,1n >> "${output_file}_stats.csv"
    
    log_success "统计信息已保存到: ${output_file}_stats.csv"
}

# 拐点分析
analyze_knee_points() {
    local output_file=$1
    
    log_info "分析性能拐点..."
    
    # 创建拐点分析文件头
    cat > "${output_file}_knee.csv" << EOF
# GE模型IPsec性能拐点分析
# 生成时间: $(date)
# 格式: 指标类型,拐点错误率(%),拐点值,拐点置信度,线性区域,非线性区域
EOF
    
    # 分析成功率拐点
    awk -F',' '
    NR>1 && $1!~/^#/ {
        loss_rate = $1
        success_rate = $6
        if (success_rate > 0) {
            print loss_rate, success_rate
        }
    }' "${output_file}_stats.csv" | sort -n > "${output_file}_success_temp.txt"
    
    # 简单的拐点检测算法
    if [[ -f "${output_file}_success_temp.txt" ]]; then
        local prev_rate=0
        local prev_success=100
        local knee_found=false
        
        while read -r loss_rate success_rate; do
            if [[ $prev_rate -gt 0 ]]; then
                local rate_diff=$((loss_rate - prev_rate))
                local success_diff=$(echo "$prev_success - $success_rate" | bc)
                
                # 检测成功率急剧下降的点
                if [[ $(echo "$success_diff > 10" | bc) -eq 1 && $rate_diff -le 2 ]]; then
                    echo "成功率拐点,$loss_rate,$success_rate,高,$prev_rate%,${loss_rate}%" >> "${output_file}_knee.csv"
                    knee_found=true
                    break
                fi
            fi
            prev_rate=$loss_rate
            prev_success=$success_rate
        done < "${output_file}_success_temp.txt"
        
        if [[ $knee_found == false ]]; then
            echo "成功率拐点,未发现,0,低,0%,100%" >> "${output_file}_knee.csv"
        fi
        
        rm -f "${output_file}_success_temp.txt"
    fi
    
    log_success "拐点分析已保存到: ${output_file}_knee.csv"
}

# 生成测试报告
generate_report() {
    local output_file=$1
    local test_mode=$2
    
    log_info "生成测试报告..."
    
    cat > "${output_file}_report.txt" << EOF
Gilbert-Elliot模型IPsec性能测试报告
=====================================

测试时间: $(date)
测试模式: $test_mode
输出文件: $output_file

测试配置:
- 错误率范围: $LOSS_RATES
- 突发长度: $BURST_LENGTH
- 坏状态时间: $BAD_STATE_TIME
- 模型类型: $MODEL_TYPE
- 每个配置测试次数: $TEST_COUNT

文件说明:
- ${output_file}_raw.csv: 原始测试数据
- ${output_file}_stats.csv: 统计结果
- ${output_file}_knee.csv: 拐点分析
- ${output_file}_report.txt: 本报告

主要发现:
EOF
    
    # 添加主要统计信息
    if [[ -f "${output_file}_stats.csv" ]]; then
        echo "" >> "${output_file}_report.txt"
        echo "性能统计摘要:" >> "${output_file}_report.txt"
        echo "错误率 | 成功率 | 平均HCT | 平均重传" >> "${output_file}_report.txt"
        echo "-------|--------|---------|----------" >> "${output_file}_report.txt"
        
        awk -F',' 'NR>1 && $1!~/^#/ {printf "  %2s%%  |  %5.1f%% |  %6.1fms |  %6.1f次\n", $1, $6, $7, $10}' "${output_file}_stats.csv" >> "${output_file}_report.txt"
    fi
    
    # 添加拐点信息
    if [[ -f "${output_file}_knee.csv" ]]; then
        echo "" >> "${output_file}_report.txt"
        echo "性能拐点:" >> "${output_file}_report.txt"
        awk -F',' 'NR>1 && $1!~/^#/ {print "  " $1 ": " $2 "% 错误率, 置信度: " $4}' "${output_file}_knee.csv" >> "${output_file}_report.txt"
    fi
    
    log_success "测试报告已保存到: ${output_file}_report.txt"
}

# 基础性能测试
run_basic_test() {
    local output_file=$1
    
    log_step "开始基础性能测试..."
    
    # 创建原始数据文件头
    cat > "${output_file}_raw.csv" << EOF
# GE模型IPsec性能测试原始数据
# 生成时间: $(date)
# 格式: 错误率(%),突发长度,坏状态时间,测试序号,结果,HCT(ms),重传次数,模型类型
EOF
    
    # 测试每个错误率
    for loss_rate in $LOSS_RATES; do
        log_info "测试错误率: ${loss_rate}%"
        
        # 设置网络条件
        set_network_conditions $loss_rate $BURST_LENGTH $BAD_STATE_TIME $MODEL_TYPE
        
        # 运行IPsec测试
        run_ipsec_test $loss_rate $BURST_LENGTH $BAD_STATE_TIME $TEST_COUNT $output_file $MODEL_TYPE
        
        echo ""
    done
    
    # 清除网络条件
    sudo ./set_realistic_network.sh -c
    
    # 计算统计信息
    calculate_statistics $output_file
    
    # 拐点分析
    analyze_knee_points $output_file
    
    # 生成报告
    generate_report $output_file "basic"
}

# 拐点精确定位测试
run_knee_test() {
    local output_file=$1
    
    log_step "开始拐点精确定位测试..."
    
    # 创建原始数据文件头
    cat > "${output_file}_raw.csv" << EOF
# GE模型IPsec性能拐点精确定位测试
# 生成时间: $(date)
# 格式: 错误率(%),突发长度,坏状态时间,测试序号,结果,HCT(ms),重传次数,模型类型
EOF
    
    # 在拐点区域进行密集测试
    for loss_rate in $LOSS_RATES; do
        log_info "密集测试错误率: ${loss_rate}% (${TEST_COUNT}次)"
        
        # 设置网络条件
        set_network_conditions $loss_rate $BURST_LENGTH $BAD_STATE_TIME $MODEL_TYPE
        
        # 运行IPsec测试
        run_ipsec_test $loss_rate $BURST_LENGTH $BAD_STATE_TIME $TEST_COUNT $output_file $MODEL_TYPE
        
        echo ""
    done
    
    # 清除网络条件
    sudo ./set_realistic_network.sh -c
    
    # 计算统计信息
    calculate_statistics $output_file
    
    # 详细拐点分析
    analyze_knee_points $output_file
    
    # 生成报告
    generate_report $output_file "knee"
}

# 完整性能分析测试
run_full_test() {
    local output_file=$1
    
    log_step "开始完整性能分析测试..."
    
    # 创建原始数据文件头
    cat > "${output_file}_raw.csv" << EOF
# GE模型IPsec完整性能分析测试
# 生成时间: $(date)
# 格式: 错误率(%),突发长度,坏状态时间,测试序号,结果,HCT(ms),重传次数,模型类型
EOF
    
    # 多参数组合测试
    local burst_lengths="3 5 8"
    local bad_state_times="0.2 0.4 0.6"
    
    for burst_length in $burst_lengths; do
        for bad_state_time in $bad_state_times; do
            log_info "测试配置: 突发长度=${burst_length}, 坏状态时间=${bad_state_time}"
            
            for loss_rate in $LOSS_RATES; do
                log_info "  错误率: ${loss_rate}%"
                
                # 设置网络条件
                set_network_conditions $loss_rate $burst_length $bad_state_time $MODEL_TYPE
                
                # 运行IPsec测试
                run_ipsec_test $loss_rate $burst_length $bad_state_time $TEST_COUNT $output_file $MODEL_TYPE
            done
            
            echo ""
        done
    done
    
    # 清除网络条件
    sudo ./set_realistic_network.sh -c
    
    # 计算统计信息
    calculate_statistics $output_file
    
    # 拐点分析
    analyze_knee_points $output_file
    
    # 生成报告
    generate_report $output_file "full"
}

# 主函数
main() {
    # 默认参数
    local test_mode="basic"
    local loss_rates="0 2 5 8 10 12 15 18 20"
    local burst_length=5
    local bad_state_time=0.4
    local test_count=50
    local output_file="ge_test"
    local model_type="3param"
    local interface="ens33"
    local target_ip="192.168.31.136"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                test_mode="$2"
                shift 2
                ;;
            --loss-range)
                loss_rates="$2"
                shift 2
                ;;
            --burst-length)
                burst_length="$2"
                shift 2
                ;;
            --bad-state-time)
                bad_state_time="$2"
                shift 2
                ;;
            --test-count)
                test_count="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --model)
                model_type="$2"
                shift 2
                ;;
            --interface)
                interface="$2"
                shift 2
                ;;
            --target-ip)
                target_ip="$2"
                shift 2
                ;;
            --help)
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
    
    # 检查权限和依赖
    check_root
    check_dependencies
    
    # 设置全局变量
    LOSS_RATES=$loss_rates
    BURST_LENGTH=$burst_length
    BAD_STATE_TIME=$bad_state_time
    TEST_COUNT=$test_count
    MODEL_TYPE=$model_type
    
    log_info "开始GE模型IPsec性能测试"
    log_info "测试模式: $test_mode"
    log_info "错误率范围: $loss_rates"
    log_info "突发长度: $burst_length"
    log_info "坏状态时间: $bad_state_time"
    log_info "模型类型: $model_type"
    log_info "输出文件: $output_file"
    echo ""
    
    # 根据测试模式运行相应测试
    case $test_mode in
        "basic")
            run_basic_test $output_file
            ;;
        "knee")
            run_knee_test $output_file
            ;;
        "full")
            run_full_test $output_file
            ;;
        *)
            log_error "不支持的测试模式: $test_mode"
            show_help
            exit 1
            ;;
    esac
    
    log_success "所有测试完成！"
    log_success "结果文件:"
    log_success "  - 原始数据: ${output_file}_raw.csv"
    log_success "  - 统计结果: ${output_file}_stats.csv"
    log_success "  - 拐点分析: ${output_file}_knee.csv"
    log_success "  - 测试报告: ${output_file}_report.txt"
}

# 清理函数
cleanup() {
    log_info "脚本执行完成"
}

# 设置信号处理
trap cleanup EXIT

# 运行主函数
main "$@" 