#!/bin/bash

# 基于突发持续时间的IPsec连接测试脚本
# 方案A: X轴 = 平均突发持续时间 (ms)

# 移除set -e，避免在循环中意外退出
# set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[$(date '+%H:%M:%S')]${NC} $1"
}

# 显示当前网络设置（仅用于信息显示）
show_network_status() {
    log_step "当前网络设置:"
    sudo tc qdisc show dev ens33 2>/dev/null || echo "无网络条件设置"
}

# 检查IPsec服务状态
check_ipsec_service() {
    log_step "检查IPsec服务状态..."
    
    if sudo systemctl is-active --quiet strongswan; then
        log_success "strongSwan服务正在运行"
        return 0
    else
        log_error "strongSwan服务未运行"
        return 1
    fi
}

# 测试IPsec连接
test_ipsec_connection() {
    local burst_duration=$1
    local test_num=$2
    local output_file=$3
    
    log_step "测试IPsec连接: 突发持续时间=${burst_duration}ms, 测试序号=$test_num"
    
    # 记录开始时间
    start_time=$(date +%s%N)
    
    # 尝试建立IPsec连接
    log_info "尝试建立IPsec连接..."
    
    # 使用timeout命令避免卡住，设置30秒超时
    local result=""
    local actual_retransmissions=0
    
    # 启动swanctl连接并捕获输出
    local temp_log=$(mktemp)
    
    # 启动连接进程
    timeout 30s sudo swanctl --initiate --ike net-net > "$temp_log" 2>&1
    local exit_code=$?
    
    # 计算HCT
    end_time=$(date +%s%N)
    hct_ms=$(( (end_time - start_time) / 1000000 ))
    
    # 统一检查重传次数 - 无论成功、失败还是超时都要统计
    # 只统计连接建立阶段的重传，排除断开连接阶段的重传
    actual_retransmissions=$(grep -c "retransmit.*IKE_SA_INIT\|retransmit.*IKE_AUTH\|retransmit.*request.*0\|retransmit.*request.*1" "$temp_log" 2>/dev/null || echo "0")
    actual_retransmissions=$(echo "$actual_retransmissions" | tr -d '\n\r')
    
    # 根据退出码和重传次数确定结果状态
    if [ $exit_code -eq 124 ]; then
        # 超时情况 - 我们的timeout设置为30s，小于strongSwan的165s总超时
        # 如果30s超时，说明重传次数可能已经很多
        result="timeout"
        log_error "连接超时 (30s), 重传次数: ${actual_retransmissions}"
    elif [ $exit_code -eq 0 ]; then
        # 连接成功
        if [ "$actual_retransmissions" -gt 0 ]; then
            result="retransmit_success"
            log_success "连接成功但有重传! HCT: ${hct_ms}ms, 重传次数: ${actual_retransmissions}"
        else
            result="success"
            log_success "连接成功! HCT: ${hct_ms}ms"
        fi
    else
        # 连接失败
        # 根据strongSwan默认配置，5次重传后放弃，所以这里调整为5次
        if [ "$actual_retransmissions" -ge 5 ]; then
            result="retransmit_failure"
            log_error "重传次数达到上限导致失败 (${actual_retransmissions}次), HCT: ${hct_ms}ms"
        else
            result="failure"
            log_error "连接失败! HCT: ${hct_ms}ms, 重传次数: ${actual_retransmissions}"
        fi
    fi
    
    # 写入CSV文件
    echo "${burst_duration},${test_num},${result},${hct_ms},${actual_retransmissions}" >> "$output_file"
    
    # 清理
    rm -f "$temp_log"
    
    # 断开连接，使用timeout避免卡住
    #timeout 10s sudo swanctl --terminate --ike net-net 2>/dev/null || true
    
    # 重启strongSwan服务以避免断开连接重传影响下次测试
    echo "[$(date '+%H:%M:%S')] 重启strongSwan服务..."
    sudo systemctl restart strongswan
    sleep 2
    
    # 返回结果
    if [ "$result" = "success" ]; then
        return 0
    else
        return 1
    fi
}

# 计算重传次数 (基于突发持续时间的简化估算)
calculate_retransmissions() {
    local burst_duration=$1
    
    # 简化的重传估算模型
    # 假设IKEv2重传间隔为1秒，超时时间为30秒
    # 重传次数 = min(突发持续时间/1000, 30)
    local retransmissions=$(echo "scale=0; $burst_duration / 1000" | bc -l)
    
    # 限制最大重传次数为30
    if (( $(echo "$retransmissions > 5" | bc -l) )); then
        retransmissions=5
    fi
    
    echo $retransmissions
}

# 基于strongSwan重传机制计算预期重传次数
calculate_expected_retransmissions() {
    local burst_duration=$1
    
    # strongSwan重传机制：
    # 重传1: 4s, 重传2: 7s, 重传3: 13s, 重传4: 23s, 重传5: 42s
    # 总时间: 4s, 11s, 24s, 47s, 89s, 165s
    
    local retransmit_times=(4 7 13 23 42)
    local cumulative_times=(4 11 24 47 89)
    
    # 将突发持续时间转换为秒
    local burst_seconds=$(echo "scale=3; $burst_duration / 1000" | bc -l)
    
    # 计算预期重传次数
    local expected_retransmissions=0
    for i in "${!cumulative_times[@]}"; do
        if (( $(echo "$burst_seconds <= ${cumulative_times[$i]}" | bc -l) )); then
            expected_retransmissions=$i
            break
        fi
    done
    
    # 如果突发持续时间超过89秒，预期5次重传
    if (( $(echo "$burst_seconds > 89" | bc -l) )); then
        expected_retransmissions=5
    fi
    
    echo $expected_retransmissions
}

# 运行连接测试序列
run_connection_tests() {
    local burst_duration=$1
    local num_tests=$2
    local output_file=$3
    
    log_step "运行连接测试序列: 突发持续时间=${burst_duration}ms, 测试次数=$num_tests"
    
    # 计算预期重传次数
    expected_retransmissions=$(calculate_expected_retransmissions $burst_duration)
    echo "[$(date '+%H:%M:%S')] 预期重传次数: ${expected_retransmissions} (基于strongSwan重传机制)"
    
    # 显示当前网络设置（仅用于信息显示）
    show_network_status
    
    # 创建输出文件并写入标题
    echo "突发持续时间(ms),测试序号,结果,HCT(ms),重传次数" > "$output_file"
    
    local success_count=0
    local retransmit_success_count=0
    local retransmit_failure_count=0
    local timeout_count=0
    local failure_count=0
    
    for ((i=1; i<=num_tests; i++)); do
        log_info "执行测试 $i/$num_tests..."
        
        test_ipsec_connection $burst_duration $i "$output_file"
        
        # 检查具体结果
        last_result=$(tail -1 "$output_file" | cut -d',' -f3)
        case "$last_result" in
            "success")
                ((success_count++))
                ;;
            "retransmit_success")
                ((retransmit_success_count++))
                ;;
            "retransmit_failure")
                ((retransmit_failure_count++))
                ;;
            "timeout")
                ((timeout_count++))
                ;;
            "failure")
                ((failure_count++))
                ;;
        esac
        
        # 短暂等待，避免过于频繁的连接
        sleep 1
    done
    
    # 计算统计信息
    total_success=$((success_count + retransmit_success_count))
    if [ $total_success -gt 0 ]; then
        # 计算所有成功连接的平均HCT
        avg_hct=$(grep -E "(success|retransmit_success)" "$output_file" | awk -F',' '{sum+=$4} END {print sum/NR}')
    else
        avg_hct=0
    fi
    
    # 输出统计结果
    log_success "测试完成!"
    echo "   总测试数: $num_tests"
    echo "   完全成功: $success_count (无重传)"
    echo "   重传成功: $retransmit_success_count (有重传但成功)"
    echo "   重传失败: $retransmit_failure_count (重传过多导致失败)"
    echo "   超时失败: $timeout_count (超时)"
    echo "   其他失败: $failure_count"
    echo "   总成功率: $(echo "scale=1; $total_success * 100 / $num_tests" | bc)%"
    
    if [ $total_success -gt 0 ]; then
        echo "   平均HCT: ${avg_hct}ms"
    fi
    
    echo "   数据文件: $output_file"
}

# 运行拐点精确定位测试
run_knee_point_test() {
    local base_duration=$1
    local num_tests=$2
    
    log_step "运行拐点精确定位测试: 基准持续时间=${base_duration}ms"
    
    # 在基准持续时间附近进行密集测试
    local durations=()
    
    # 生成测试持续时间列表
    for i in {0..10}; do
        duration=$(echo "scale=0; $base_duration + $i * 10" | bc -l)
        durations+=($duration)
    done
    
    for duration in "${durations[@]}"; do
        log_info "测试突发持续时间: ${duration}ms"
        output_file="knee_point_${duration}ms.csv"
        run_connection_tests $duration $num_tests "$output_file"
        echo ""
    done
}

# 主函数
main() {
    echo "=========================================="
    echo "      基于突发持续时间的IPsec连接测试"
    echo "=========================================="
    echo ""
    echo "🎯 方案A: X轴 = 平均突发持续时间 (ms)"
    echo "核心问题: '网络中断多长时间，IPsec连接会失败？'"
    echo ""
    
    # 检查IPsec服务
    if ! check_ipsec_service; then
        log_error "IPsec服务检查失败，退出测试"
        exit 1
    fi
    
    case "${1:-help}" in
        "test")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "请指定突发持续时间和测试次数"
                echo "用法: $0 test <持续时间ms> <测试次数> [输出文件]"
                exit 1
            fi
            burst_duration=$2
            num_tests=$3
            output_file=${4:-"test_${burst_duration}ms.csv"}
            run_connection_tests $burst_duration $num_tests "$output_file"
            ;;
        "knee")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "请指定基准持续时间和测试次数"
                echo "用法: $0 knee <基准持续时间ms> <测试次数>"
                exit 1
            fi
            base_duration=$2
            num_tests=$3
            run_knee_point_test $base_duration $num_tests
            ;;
        "sweep")
            echo "=========================================="
            echo "          全参数扫描测试"
            echo "=========================================="
            echo ""
            
            # 定义测试的突发持续时间范围
            burst_durations=(10 20 50 100 150 200 250 300 400 500 750 1000 1500 2000)
            num_tests=${2:-20}
            
            log_step "开始全参数扫描测试..."
            
            for duration in "${burst_durations[@]}"; do
                log_info "测试突发持续时间: ${duration}ms"
                output_file="sweep_${duration}ms.csv"
                run_connection_tests $duration $num_tests "$output_file"
                echo ""
            done
            
            log_success "全参数扫描测试完成!"
            ;;
        *)
            echo "基于突发持续时间的IPsec连接测试脚本"
            echo ""
            echo "用法: $0 [命令] [参数]"
            echo ""
            echo "命令:"
            echo "  test <持续时间ms> <测试次数> [输出文件]  运行单次连接测试"
            echo "  knee <基准持续时间ms> <测试次数>        运行拐点精确定位测试"
            echo "  sweep [测试次数]                        运行全参数扫描测试"
            echo ""
            echo "参数说明:"
            echo "  <持续时间ms>: 平均突发持续时间 (毫秒)"
            echo "  <测试次数>: 每个配置的测试次数"
            echo "  [输出文件]: CSV输出文件名 (可选)"
            echo ""
            echo "重要说明:"
            echo "  - 网络条件需要在两端手动设置"
            echo "  - 使用 set_burst_duration_network.sh 设置网络条件"
            echo "  - 本脚本仅负责IPsec连接测试和数据记录"
            echo ""
            echo "使用流程:"
            echo "  1. 在两端设置网络条件: ./set_burst_duration_network.sh burst <持续时间ms>"
            echo "  2. 运行连接测试: $0 test <持续时间ms> <测试次数>"
            echo "  3. 清除网络条件: ./set_burst_duration_network.sh clear"
            echo ""
            echo "示例:"
            echo "  # 设置网络条件"
            echo "  ./set_burst_duration_network.sh burst 100"
            echo "  # 运行测试"
            echo "  $0 test 100 50"
            echo "  # 清除网络条件"
            echo "  ./set_burst_duration_network.sh clear"
            echo ""
            echo "输出数据格式:"
            echo "  突发持续时间(ms),测试序号,结果,HCT(ms),重传次数"
            echo ""
            echo "科学意义:"
            echo "  - 直接考验IKEv2协议的超时和重传机制"
            echo "  - 揭示协议层面的深层脆弱性"
            echo "  - 回答核心问题: '网络中断多长时间，IPsec连接会失败？'"
            ;;
    esac
}

# 运行主函数
main "$@" 