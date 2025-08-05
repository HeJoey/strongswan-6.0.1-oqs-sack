#!/bin/bash

# IPsec Performance Test Script
# 测试strongSwan IPsec连接的握手完成时间(HCT)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 测试配置
TEST_COUNT=50
CONNECTION_NAME="net-net"
LOG_FILE="ipsec_test_$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="figure1.csv"
# PLOT_SCRIPT="generate_plot.py" # 已禁用绘图功能

# 网络配置
LOCAL_IP="192.168.31.114"
REMOTE_IP="192.168.31.135"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  strongSwan IPsec 性能测试脚本${NC}"
echo -e "${CYAN}  握手完成时间 (HCT) 测试${NC}"
echo -e "${CYAN}========================================${NC}"

# 函数：带时间戳的日志
log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1" | tee -a "$LOG_FILE"
}

# 函数：初始化结果文件
initialize_results_file() {
    log "${YELLOW}初始化结果文件...${NC}"
    
    # 直接使用默认的figure1.csv文件名
    cat > "$RESULTS_FILE" << EOF
# strongSwan IPsec 握手完成时间测试结果
# 测试时间: $(date)
# 连接名称: $CONNECTION_NAME
# 列格式: test_num,hct_ms,connection_status,error_message,timestamp,network_conditions,interface,local_ip,remote_ip
EOF
    echo "test_num,hct_ms,connection_status,error_message,timestamp,network_conditions,interface,local_ip,remote_ip" >> "$RESULTS_FILE"
    
    log "${GREEN}结果文件 ${RESULTS_FILE} 已初始化${NC}"
}

# 函数：检查依赖
check_dependencies() {
    log "${YELLOW}检查系统依赖...${NC}"
    
    # 检查必要的命令
    local deps=("swanctl" "ipsec" "bc" "awk" "grep" "tee")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "${RED}错误: 缺少依赖 '$dep'${NC}"
            exit 1
        fi
    done
    
    # Python包检查已禁用（不再需要绘图）
    # if ! python3 -c "import matplotlib, numpy, pandas" 2>/dev/null; then
    #     log "${YELLOW}检测到缺少Python依赖包...${NC}"
    # fi
    
    log "${GREEN}所有依赖检查完成${NC}"
}

# 函数：检查strongSwan状态
check_strongswan() {
    if pgrep -f "charon" > /dev/null; then
        log "${GREEN}strongSwan正在运行${NC}"
        return 0
    else
        log "${RED}strongSwan未运行${NC}"
        return 1
    fi
}

# 函数：启动strongSwan
start_strongswan() {
    log "${YELLOW}启动strongSwan服务...${NC}"
    
    # 停止现有服务
    sudo systemctl stop strongswan 2>/dev/null || true
    sudo pkill -f charon 2>/dev/null || true
    sleep 2
    
    # 启动服务
    sudo systemctl start strongswan
    sleep 3
    
    if check_strongswan; then
        log "${GREEN}strongSwan启动成功${NC}"
        return 0
    else
        log "${RED}strongSwan启动失败${NC}"
        return 1
    fi
}

# 函数：设置理想网络条件
setup_ideal_network() {
    log "${YELLOW}设置理想网络条件...${NC}"
    
    # 清除现有的tc规则
    sudo tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    
    # 设置理想网络条件（无丢包，低延迟）
    sudo tc qdisc add dev "$INTERFACE" root netem delay 5ms loss 0%
    
    log "${GREEN}理想网络条件设置完成: 5ms延迟，0%丢包${NC}"
}

# 函数：清除网络条件
clear_network_conditions() {
    log "${YELLOW}清除网络条件...${NC}"
    sudo tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    log "${GREEN}网络条件已清除${NC}"
}

# 函数：等待连接建立（改进版）
wait_for_connection() {
    local timeout=30
    local elapsed=0
    local check_interval=0.5
    
    log "${YELLOW}等待IPsec连接建立...${NC}"
    
    while [ $(echo "$elapsed < $timeout" | bc -l) -eq 1 ]; do
        # 使用 --list-sas 检查活动的安全关联，而不是 --list-conns
        local sa_status=$(sudo swanctl --list-sas 2>/dev/null)
        
        # 检查是否有 ESTABLISHED 状态的SA
        if echo "$sa_status" | grep -q "$CONNECTION_NAME.*ESTABLISHED"; then
            log "${GREEN}IPsec连接已建立 (ESTABLISHED)${NC}"
            return 0
        fi
        
        # 检查是否有正在建立的连接（CONNECTING状态）
        if echo "$sa_status" | grep -q "$CONNECTION_NAME.*CONNECTING"; then
            log "${YELLOW}连接正在建立中...${NC}"
        fi
        
        sleep $check_interval
        elapsed=$(echo "$elapsed + $check_interval" | bc -l)
    done
    
    log "${RED}连接超时，检查当前SA状态：${NC}"
    sudo swanctl --list-sas || log "${RED}无法获取SA状态${NC}"
    
    log "${RED}连接超时，检查连接配置：${NC}"
    sudo swanctl --list-conns | grep -A 5 "$CONNECTION_NAME" || log "${RED}无法获取连接配置${NC}"
    
    return 1
}

# 函数：测量握手完成时间（改进版）
measure_hct() {
    local test_num=$1
    local start_time
    local end_time
    local hct_ms
    local connection_status="SUCCESS"
    local error_message=""
    
    log "${PURPLE}执行测试 #$test_num/${TEST_COUNT}${NC}"
    
    # 确保连接已断开
    log "${YELLOW}断开现有连接...${NC}"
    sudo swanctl --terminate --ike "$CONNECTION_NAME" 2>/dev/null || true
    sleep 3
    
    # 验证连接已完全断开
    local attempts=0
    while [ $attempts -lt 5 ]; do
        if ! sudo swanctl --list-sas | grep -q "$CONNECTION_NAME"; then
            break
        fi
        log "${YELLOW}等待连接完全断开...${NC}"
        sleep 1
        attempts=$((attempts + 1))
    done
    
    # 清除日志
    sudo truncate -s 0 /var/log/strongswan.log 2>/dev/null || true
    
    # 记录开始时间
    start_time=$(date +%s.%N)
    
    # 启动连接（改进的方式）
    log "${YELLOW}启动IPsec连接: $CONNECTION_NAME${NC}"
    
    # 启动连接并等待结果
    local initiate_output=$(timeout 30 sudo swanctl --initiate --ike "$CONNECTION_NAME" 2>&1)
    local initiate_result=$?
    
    # 记录结束时间
    end_time=$(date +%s.%N)
    
    # 输出连接日志
    echo "$initiate_output" | tee -a "$LOG_FILE"
    
    # 检查连接是否成功
    if [ $initiate_result -eq 0 ] && echo "$initiate_output" | grep -q "initiate completed successfully"; then
        # 计算握手完成时间（毫秒）
        hct_ms=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc -l)
        
        log "${GREEN}测试 #$test_num 成功: HCT = ${hct_ms}ms${NC}"
        
        # 保存成功的数据
        save_test_data "$test_num" "$hct_ms" "SUCCESS" ""
        
        # 断开连接
        log "${YELLOW}断开测试连接...${NC}"
        sudo swanctl --terminate --ike "$CONNECTION_NAME" > /dev/null 2>&1
        sleep 2
        
        return 0
    else
        log "${RED}测试 #$test_num 失败: 连接建立失败${NC}"
        if [ $initiate_result -eq 124 ]; then
            error_message="Connection timeout"
        else
            error_message="Connection failed"
        fi
    fi
    
    # 如果到达这里说明失败了
    connection_status="FAILED"
    
    # 保存失败的数据
    save_test_data "$test_num" "0" "FAILED" "$error_message"
    
    # 强制清理连接
    sudo swanctl --terminate --ike "$CONNECTION_NAME" > /dev/null 2>&1
    sleep 2
    
    return 1
}

# 函数：保存测试数据
save_test_data() {
    local test_num=$1
    local hct_ms="$2"
    local connection_status="$3"
    local error_message="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local network_conditions="ideal"
    local interface="$INTERFACE"
    local local_ip="$LOCAL_IP"
    local remote_ip="$REMOTE_IP"
    
    # 保存到CSV文件
    echo "$test_num,$hct_ms,$connection_status,$error_message,$timestamp,$network_conditions,$interface,$local_ip,$remote_ip" >> "$RESULTS_FILE"
}

# 函数：计算统计数据
calculate_statistics() {
    log "${YELLOW}计算统计数据...${NC}"
    
    if [ ! -f "$RESULTS_FILE" ]; then
        log "${RED}结果文件不存在${NC}"
        return 1
    fi
    
    # 提取成功的HCT数据（跳过注释行）
    local hct_data=$(grep -v "^#" "$RESULTS_FILE" | tail -n +2 | grep "SUCCESS" | cut -d',' -f2)
    
    if [ -z "$hct_data" ]; then
        log "${RED}没有成功的测试数据${NC}"
        return 1
    fi
    
    # 计算平均值
    local mean=$(echo "$hct_data" | awk '{sum+=$1} END {print sum/NR}')
    
    # 计算标准差
    local variance=$(echo "$hct_data" | awk -v mean="$mean" '{sum+=($1-mean)^2} END {print sum/NR}')
    local stddev=$(echo "sqrt($variance)" | bc -l)
    
    # 计算最小值和最大值
    local min=$(echo "$hct_data" | sort -n | head -1)
    local max=$(echo "$hct_data" | sort -n | tail -1)
    
    # 计算中位数
    local median=$(echo "$hct_data" | sort -n | awk '{
        count[NR] = $1;
    } END {
        if (NR % 2 == 1) {
            print count[(NR + 1) / 2];
        } else {
            print (count[NR / 2] + count[(NR / 2) + 1]) / 2;
        }
    }')
    
    # 计算95%置信区间
    local confidence_interval_lower=$(echo "$mean - 1.96 * $stddev / sqrt($TEST_COUNT)" | bc -l)
    local confidence_interval_upper=$(echo "$mean + 1.96 * $stddev / sqrt($TEST_COUNT)" | bc -l)
    
    # 保存统计数据
    local stats_file="statistics_$(date +%Y%m%d_%H%M%S).txt"
    cat > "$stats_file" << EOF
IPsec 握手完成时间 (HCT) 统计报告
=====================================
测试时间: $(date)
测试次数: $TEST_COUNT
连接名称: $CONNECTION_NAME
网络条件: 理想网络（5ms延迟，0%丢包）
结果文件: $RESULTS_FILE

统计数据:
- 平均值: ${mean} ms
- 标准差: ${stddev} ms
- 最小值: ${min} ms
- 最大值: ${max} ms
- 中位数: ${median} ms
- 95%置信区间: ${confidence_interval_lower} - ${confidence_interval_upper} ms

测试环境:
- 本地IP: $LOCAL_IP
- 远程IP: $REMOTE_IP
- 网络接口: $INTERFACE
- strongSwan版本: $(swanctl --version 2>/dev/null | head -1 || echo "Unknown")
EOF
    
    log "${GREEN}统计数据已保存到 ${stats_file}${NC}"
    cat "$stats_file"
}

# 函数：生成Python绘图脚本 (已禁用)
# generate_plot_script() {
#     log "${YELLOW}绘图功能已禁用，跳过脚本生成${NC}"
# }

# 函数：生成图表 (已禁用)
generate_plots() {
    log "${YELLOW}绘图功能已禁用，数据已保存到 $RESULTS_FILE${NC}"
    log "${GREEN}你可以使用这些数据自己绘制图表${NC}"
}

# 函数：清理
cleanup() {
    log "${YELLOW}清理测试环境...${NC}"
    # 终止连接
    sudo swanctl --terminate --ike "$CONNECTION_NAME" 2>/dev/null || true
    # 清除网络条件
    clear_network_conditions
    log "${GREEN}清理完成${NC}"
}

# 主函数
main() {
    log "${CYAN}开始IPsec性能测试${NC}"
    
    # 检查依赖
    check_dependencies
    
    # 启动strongSwan
    if ! start_strongswan; then
        log "${RED}无法启动strongSwan，退出测试${NC}"
        exit 1
    fi
    
    # 初始化结果文件
    initialize_results_file
    
    # 设置理想网络条件
    setup_ideal_network
    
    # 检查可用连接
    log "${YELLOW}检查可用的IPsec连接配置...${NC}"
    sudo swanctl --list-conns || log "${RED}无法列出连接配置${NC}"
    
    # 执行测试
    local success_count=0
    local fail_count=0
    
    log "${CYAN}开始执行 $TEST_COUNT 次握手完成时间测试...${NC}"
    
    for i in $(seq 1 $TEST_COUNT); do
        if measure_hct $i; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        
        # 每10次测试显示进度
        if [ $((i % 10)) -eq 0 ]; then
            log "${YELLOW}进度: $i/$TEST_COUNT (成功: $success_count, 失败: $fail_count)${NC}"
        fi
        
        # 如果连续失败太多次，提前退出
        if [ $fail_count -gt 10 ] && [ $success_count -eq 0 ]; then
            log "${RED}连续失败次数过多，可能存在配置问题，提前退出${NC}"
            break
        fi
    done
    
    log "${CYAN}测试完成!${NC}"
    log "${GREEN}成功: $success_count 次${NC}"
    log "${RED}失败: $fail_count 次${NC}"
    
    # 计算统计数据
    if [ $success_count -gt 0 ]; then
        calculate_statistics
        generate_plots
    else
        log "${RED}没有成功的测试，无法生成统计数据${NC}"
        log "${RED}请检查IPsec连接配置和网络连通性${NC}"
    fi
    
    # 清理
    cleanup
    
    log "${CYAN}测试报告文件:${NC}"
    log "  - 详细日志: $LOG_FILE"
    log "  - 测试结果: $RESULTS_FILE"
    log "  - 统计数据: statistics_*.txt"
    
    log "${GREEN}IPsec性能测试完成!${NC}"
}

# 信号处理
trap cleanup EXIT
trap 'log "${RED}测试被中断${NC}"; exit 1' INT TERM

# 运行主函数
main "$@" 