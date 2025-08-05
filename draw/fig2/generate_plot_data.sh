#!/bin/bash

# 生成绘图数据的脚本
# 用于生成图4、图5、图6所需的数据

# set -e  # 暂时注释掉，避免提前退出

# 默认配置
DEFAULT_LOSS_RATES="0 5 10 15 20"
DEFAULT_TESTS_PER_LOSS=50
DEFAULT_CONNECTION="net-net"
DEFAULT_OUTPUT_FILE="plot_data.csv"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

show_help() {
    echo "生成绘图数据脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -l, --loss-rates RATES    丢包率列表 (默认: 0 5 10 15 20)"
    echo "  -n, --tests-per-loss N    每个丢包率的测试次数 (默认: 50)"
    echo "  -c, --connection NAME     连接名称 (默认: net-net)"
    echo "  -o, --output FILE         输出文件 (默认: plot_data.csv)"
    echo "  -h, --help                显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -l '0 5 10' -n 30       # 测试0%, 5%, 10%丢包率，每个30次"
    echo "  $0 -o my_data.csv          # 指定输出文件"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要root权限"
        exit 1
    fi
}

# 检查strongSwan
check_strongswan() {
    if ! systemctl is-active --quiet strongswan; then
        log_error "strongSwan服务未运行"
        exit 1
    fi
}

# 设置网络条件
set_network_conditions() {
    local loss_rate=$1
    local interface="ens33"
    
    if [[ $loss_rate -eq 0 ]]; then
        # 清除网络条件
        tc qdisc del dev "$interface" root 2>/dev/null || true
        log_info "设置理想网络条件 (0% 丢包)"
    else
        # 设置突发丢包
        tc qdisc del dev "$interface" root 2>/dev/null || true
        tc qdisc add dev "$interface" root netem loss ${loss_rate}% 3
        log_info "设置 ${loss_rate}% 突发丢包率"
    fi
}

# 运行单次测试
run_single_test() {
    local conn_name=$1
    local timeout=30
    
    # 断开现有连接
    sudo swanctl --terminate --child "$conn_name" >/dev/null 2>&1 || true
    sleep 2
    
    # 记录开始时间
    local start_time=$(date +%s.%N)
    
    # 启动IKE SA建立
    if ! sudo swanctl --initiate --ike "$conn_name" >/dev/null 2>&1; then
        return 1
    fi
    
    # 等待IKE SA建立
    local start_wait=$(date +%s)
    while true; do
        if sudo swanctl --list-sas | grep -q "$conn_name.*ESTABLISHED"; then
            local end_time=$(date +%s.%N)
            local hct=$(echo "scale=1; ($end_time - $start_time) * 1000" | bc)
            local retrans=$(journalctl -u strongswan --since "1 minute ago" | grep -i "retransmit\|retry" | wc -l)
            echo "SUCCESS,$hct,$retrans"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_wait))
        
        if [[ $elapsed -ge $timeout ]]; then
            echo "TIMEOUT,0,0"
            return 1
        fi
        
        sleep 0.1
    done
}

# 生成绘图数据
generate_plot_data() {
    local loss_rates="$1"
    local tests_per_loss=$2
    local conn_name="$3"
    local output_file="$4"
    
    log_info "开始生成绘图数据"
    log_info "丢包率: $loss_rates"
    log_info "每个丢包率测试次数: $tests_per_loss"
    log_info "连接名称: $conn_name"
    log_info "输出文件: $output_file"
    echo ""
    
    # 创建输出文件头
    cat > "$output_file" << EOF
# 绘图数据文件
# 生成时间: $(date)
# 用于生成图4(握手成功率)、图5(HCT箱形图)、图6(重传次数)
# 格式: 丢包率(%),测试序号,结果,HCT(ms),重传次数
EOF
    
    # 测试每个丢包率
    for loss_rate in $loss_rates; do
        log_info "测试丢包率: ${loss_rate}%"
        
        # 设置网络条件
        set_network_conditions "$loss_rate"
        
        # 运行测试
        local success_count=0
        local total_tests=$tests_per_loss
        
        for ((i=1; i<=tests_per_loss; i++)); do
            # 显示进度
            if [[ $((i % 10)) -eq 0 ]]; then
                echo -ne "\r  进度: $i/$tests_per_loss"
            fi
            
            # 运行单次测试
            if result=$(run_single_test "$conn_name"); then
                ((success_count++))
            fi
            
            # 写入结果
            echo "$loss_rate,$i,$result" >> "$output_file"
            
            # 测试间隔
            sleep 0.5
        done
        
        echo ""
        local success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
        log_success "丢包率 ${loss_rate}%: 成功率 ${success_rate}% ($success_count/$total_tests)"
        echo ""
    done
    
    # 清理网络条件
    set_network_conditions 0
    
    log_success "数据生成完成！"
    log_success "输出文件: $output_file"
    
    # 生成统计摘要
    generate_summary "$output_file"
}

# 生成统计摘要
generate_summary() {
    local data_file="$1"
    local summary_file="${data_file%.csv}_summary.csv"
    
    log_info "生成统计摘要..."
    
    # 创建摘要文件头
    cat > "$summary_file" << EOF
# 统计摘要
# 用于生成图4、图5、图6
# 格式: 丢包率(%),成功率(%),HCT均值(ms),HCT中位数(ms),HCT标准差(ms),平均重传次数,重传标准差
EOF
    
    # 分析每个丢包率
    for loss_rate in $(grep "^[0-9]" "$data_file" | cut -d',' -f1 | sort -u); do
        # 提取该丢包率的数据
        local success_data=$(grep "^${loss_rate}," "$data_file" | grep "SUCCESS" | cut -d',' -f4)
        local retrans_data=$(grep "^${loss_rate}," "$data_file" | grep "SUCCESS" | cut -d',' -f5)
        
        # 计算基本统计
        local total_tests=$(grep "^${loss_rate}," "$data_file" | wc -l)
        local success_count=$(echo "$success_data" | wc -l)
        local success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
        
        # 计算HCT统计
        local hct_mean=0
        local hct_median=0
        local hct_std=0
        
        if [[ $success_count -gt 0 ]]; then
            hct_mean=$(echo "$success_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
            hct_median=$(echo "$success_data" | sort -n | awk '{values[NR]=$1} END {n=NR; if(n%2==1) print values[(n+1)/2]; else printf "%.1f", (values[n/2]+values[n/2+1])/2}')
            hct_std=$(echo "$success_data" | awk -v mean="$hct_mean" '{sum+=($1-mean)^2; count++} END {if(count>1) printf "%.1f", sqrt(sum/(count-1)); else print "0"}')
        fi
        
        # 计算重传统计
        local retrans_mean=0
        local retrans_std=0
        
        if [[ $success_count -gt 0 ]]; then
            retrans_mean=$(echo "$retrans_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
            retrans_std=$(echo "$retrans_data" | awk -v mean="$retrans_mean" '{sum+=($1-mean)^2; count++} END {if(count>1) printf "%.2f", sqrt(sum/(count-1)); else print "0"}')
        fi
        
        # 输出摘要
        echo "${loss_rate},${success_rate},${hct_mean},${hct_median},${hct_std},${retrans_mean},${retrans_std}" >> "$summary_file"
        
        log_info "  丢包率 ${loss_rate}%: 成功率 ${success_rate}%, 平均HCT ${hct_mean}ms, 平均重传 ${retrans_mean}"
    done
    
    log_success "统计摘要已保存到: $summary_file"
}

# 主函数
main() {
    local loss_rates="$DEFAULT_LOSS_RATES"
    local tests_per_loss="$DEFAULT_TESTS_PER_LOSS"
    local conn_name="$DEFAULT_CONNECTION"
    local output_file="$DEFAULT_OUTPUT_FILE"
    
    # 解析参数
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
    
    # 检查环境
    check_root
    check_strongswan
    
    # 生成数据
    generate_plot_data "$loss_rates" "$tests_per_loss" "$conn_name" "$output_file"
}

# 清理函数
cleanup() {
    log_info "脚本执行完成"
}

# 设置信号处理
trap cleanup EXIT

# 运行主函数
main "$@" 