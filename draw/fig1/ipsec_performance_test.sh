#!/bin/bash

# IPsec Performance Test Script
# 测试strongSwan IPsec连接的握手完成时间(HCT)
# 执行至少50次测试以保证数据可靠性

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
LOG_FILE="ipsec_performance_test_$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE="figure1.csv"
PLOT_SCRIPT="generate_hct_plot.py"

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

# 函数：检测proposal算法并重命名结果文件
detect_proposals_and_rename_file() {
    log "${YELLOW}检测连接proposal算法...${NC}"
    
    # 获取连接配置信息
    local conn_info=$(sudo swanctl --list-conns 2>/dev/null | grep -A 20 "^${CONNECTION_NAME}:")
    
    if [ -z "$conn_info" ]; then
        log "${RED}错误: 无法找到连接 '$CONNECTION_NAME'${NC}"
        exit 1
    fi
    
    # 提取各种算法
    local esp_proposals=$(echo "$conn_info" | grep -i "esp_proposals" | sed 's/.*esp_proposals: //' | tr '[:upper:]' '[:lower:]')
    local ike_proposals=$(echo "$conn_info" | grep -i "proposals" | head -1 | sed 's/.*proposals: //' | tr '[:upper:]' '[:lower:]')
    
    log "${GREEN}连接配置信息:${NC}"
    log "  连接名称: $CONNECTION_NAME"
    log "  IKE proposals: $ike_proposals"
    log "  ESP proposals: $esp_proposals"
    
    # 解析算法组合，提取关键算法标识
    local key_algorithm=""
    
    # 检查常见的密钥交换算法
    if echo "$ike_proposals $esp_proposals" | grep -q "curve25519"; then
        key_algorithm="curve25519"
    elif echo "$ike_proposals $esp_proposals" | grep -q "ecp_256"; then
        key_algorithm="ecp256"
    elif echo "$ike_proposals $esp_proposals" | grep -q "ecp_384"; then
        key_algorithm="ecp384"
    elif echo "$ike_proposals $esp_proposals" | grep -q "ecp_521"; then
        key_algorithm="ecp521"
    elif echo "$ike_proposals $esp_proposals" | grep -q "modp2048"; then
        key_algorithm="modp2048"
    elif echo "$ike_proposals $esp_proposals" | grep -q "modp3072"; then
        key_algorithm="modp3072"
    elif echo "$ike_proposals $esp_proposals" | grep -q "modp4096"; then
        key_algorithm="modp4096"
    elif echo "$ike_proposals $esp_proposals" | grep -q "sntrup761"; then
        key_algorithm="sntrup761"
    elif echo "$ike_proposals $esp_proposals" | grep -q "kyber"; then
        key_algorithm="kyber"
    else
        # 如果没有找到特定算法，使用加密算法
        if echo "$ike_proposals $esp_proposals" | grep -q "aes256"; then
            key_algorithm="aes256"
        elif echo "$ike_proposals $esp_proposals" | grep -q "aes128"; then
            key_algorithm="aes128"
        elif echo "$ike_proposals $esp_proposals" | grep -q "chacha20"; then
            key_algorithm="chacha20"
        else
            key_algorithm="default"
        fi
    fi
    
    # 根据检测到的算法重命名结果文件
    RESULTS_FILE="${key_algorithm}_fig1.csv"
    
    log "${GREEN}算法检测完成，使用文件名: ${RESULTS_FILE}${NC}"
    
    # 将proposal信息写入CSV文件开头
    cat > "$RESULTS_FILE" << EOF
# strongSwan IPsec 握手完成时间测试结果
# 测试时间: $(date)
# 连接名称: $CONNECTION_NAME
# IKE Proposals: $ike_proposals
# ESP Proposals: $esp_proposals
# 关键算法: $key_algorithm
# 列格式: test_num,hct_ms,connection_status,error_message,timestamp,network_conditions,interface,local_ip,remote_ip
EOF
    echo "test_num,hct_ms,connection_status,error_message,timestamp,network_conditions,interface,local_ip,remote_ip" >> "$RESULTS_FILE"
    
    log "${GREEN}proposal信息已写入 ${RESULTS_FILE}${NC}"
}

# 函数：检查依赖
check_dependencies() {
    log "${YELLOW}检查系统依赖...${NC}"
    
    # 检查必要的命令
    local deps=("swanctl" "ipsec" "python3" "bc" "awk" "grep" "tee")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "${RED}错误: 缺少依赖 '$dep'${NC}"
            exit 1
        fi
    done
    
    # 检查Python包
    if ! python3 -c "import matplotlib, numpy, pandas" 2>/dev/null; then
        log "${YELLOW}安装Python依赖包...${NC}"
        pip3 install matplotlib numpy pandas
    fi
    
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
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    
    # 设置理想网络条件（无丢包，低延迟）
    sudo tc qdisc add dev $INTERFACE root netem delay 5ms loss 0%
    
    log "${GREEN}理想网络条件设置完成: 5ms延迟，0%丢包${NC}"
}

# 函数：清除网络条件
clear_network_conditions() {
    log "${YELLOW}清除网络条件...${NC}"
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    log "${GREEN}网络条件已清除${NC}"
}

# 函数：等待连接建立
wait_for_connection() {
    local timeout=30
    local elapsed=0    
    
    while [ $elapsed -lt $timeout ]; do
        # 使用 --list-sas 检查活动的安全关联
        if sudo swanctl --list-sas | grep -q "$CONNECTION_NAME.*ESTABLISHED"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    return 1
}

# 函数：测量握手完成时间
measure_hct() {
    local test_num=$1
    local start_time
    local end_time
    local connection_status="SUCCESS"
    local error_message=""
    
    log "${PURPLE}执行测试 #$test_num/${TEST_COUNT}${NC}"
    
    # 确保连接已断开
    sudo swanctl --terminate --ike "$CONNECTION_NAME" 2>/dev/null || true
    sleep 2   
    
    # 清除日志
    sudo truncate -s 0 /var/log/strongswan.log
    
    # 记录开始时间
    start_time=$(date +%s.%N)
    
    # 启动连接
    sudo swanctl --initiate --ike "$CONNECTION_NAME" > /dev/null 2>&1 &
    local conn_pid=$!
    
    # 等待连接建立
    if wait_for_connection; then
        end_time=$(date +%s.%N)
        
        # 计算握手完成时间（毫秒）
        hct_ms=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc -l)
        
        log "${GREEN}测试 #$test_num 成功: HCT = ${hct_ms}ms${NC}"
        
        # 保存成功的数据
        save_test_data "$test_num" "$hct_ms" "SUCCESS" ""
        
        # 终止连接
        sudo swanctl --terminate --ike "$CONNECTION_NAME" > /dev/null 2>&1
        sleep 2   
        
        return 0
    else
        log "${RED}测试 #$test_num 失败: 连接超时${NC}"
        connection_status="FAILED"
        error_message="Connection timeout"
        
        # 保存失败的数据
        save_test_data "$test_num" "0" "FAILED" "Connection timeout"
        
        # 强制终止连接
        kill $conn_pid 2>/dev/null || true
        sudo swanctl --terminate --ike "$CONNECTION_NAME" > /dev/null 2>&1
        sleep 2   
        
        return 1
    fi
}

# 函数：保存测试数据
save_test_data() {
    local test_num=$1
    local hct_ms=$2
    local connection_status=$3
    local error_message=$4
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local network_conditions="ideal"
    local interface=$INTERFACE
    local local_ip=$LOCAL_IP
    local remote_ip=$REMOTE_IP
    
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
    
    # 提取成功的HCT数据
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
    local median=$(echo "$hct_data" | sort -n | awk '
    {
        count[NR] = $1;
    } END {
        if (NR % 2 == 1) {
            print count[(NR + 1)/2]
        } else {
            print (count[NR / 2] + count[NR / 2 + 1]) / 2
        }
    }')
    
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

测试环境:
- 本地IP: $LOCAL_IP
- 远程IP: $REMOTE_IP
- 网络接口: $INTERFACE
- strongSwan版本: $(swanctl --version 2>/dev/null | head -1 || echo "Unknown")
EOF
    
    log "${GREEN}统计数据已保存到 ${stats_file}${NC}"
    cat "$stats_file"
}

# 函数：生成Python绘图脚本
generate_plot_script() {
    cat >"$PLOT_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['SimHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

def create_hct_plot(results_file):
    """
    创建握手完成时间图表
    """
    # 读取数据
    df = pd.read_csv(results_file, names=['test_num', 'hct_ms', 'connection_status', 'error_message', 'timestamp', 'network_conditions', 'interface', 'local_ip', 'remote_ip'])
    
    # 只使用成功的测试数据
    df_success = df[df['connection_status'] == 'SUCCESS'].copy()
    
    if df_success.empty:
        print("没有成功的测试数据")
        return
    
    # 计算统计数据
    mean_hct = df_success['hct_ms'].mean()
    std_hct = df_success['hct_ms'].std()
    min_hct = df_success['hct_ms'].min()
    max_hct = df_success['hct_ms'].max()
    
    # 创建图表
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))
    
    # 图1: 带误差棒的条形图
    ax1.bar([平均握手完成时间'], [mean_hct], yerr=std_hct, 
            capsize=10, color='skyblue', edgecolor='navy', linewidth=2)
    ax1.set_ylabel('时间 (毫秒)', fontsize=12)
    ax1.set_title(strongSwan IPsec 握手完成时间 (HCT) - 理想网络条件', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=0.3)
    
    # 在条形图上添加数值标签
    ax1.text(0, mean_hct + std_hct + 1, f'{mean_hct:0.2f}±{std_hct:.2f}ms', 
             ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    # 添加统计信息
    stats_text = f'测试次数: {len(df_success)}\n最小值: {min_hct:.2}ms\n最大值: {max_hct:.2f}ms'
    ax1.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    # 图2: 时间序列图
    ax2.plot(df_success['test_num'], df_success['hct_ms'], 'o-', color='red', alpha=0.7, linewidth=1)
    ax2.axhline(y=mean_hct, color='blue', linestyle='--', label=f'平均值: {mean_hct:.2f}ms')
    ax2.fill_between(df_success['test_num'], mean_hct - std_hct, mean_hct + std_hct, 
                     alpha=0.2, color='blue', label=f'±1σ: {std_hct:.2f}ms')
    ax2.set_xlabel('测试序号', fontsize=12)
    ax2.set_ylabel('握手完成时间 (毫秒)', fontsize=12)
    ax2.set_title(握手完成时间变化趋势', fontsize=14, fontweight='bold')
    ax2.grid(True, alpha=0.3)
    ax2.legend()
    
    plt.tight_layout()
    
    # 保存图表
    plot_filename = f'ipsec_hct_plot_{pd.Timestamp.now().strftime("%Y%m%d_%H%M%S")}.png'
    plt.savefig(plot_filename, dpi=300, bbox_inches='tight')
    print(f"图表已保存为: {plot_filename}")
    
    # 显示图表
    plt.show()

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("用法: python3 generate_hct_plot.py <results_file>")
        sys.exit(1)
    
    results_file = sys.argv[1]
    if not os.path.exists(results_file):
        print(f"错误: 文件 {results_file} 不存在")
        sys.exit(1)
    
    create_hct_plot(results_file)
EOF
    
    chmod +x "$PLOT_SCRIPT"
    log "${GREEN}Python绘图脚本已生成${NC}"
}

# 函数：生成图表
generate_plots() {
    log "${YELLOW}生成性能图表...${NC}"
    
    if [ -f "$RESULTS_FILE" ]; then
        python3 "$PLOT_SCRIPT" "$RESULTS_FILE"
        log "${GREEN}图表生成完成${NC}"
    else
        log "${RED}结果文件不存在，无法生成图表${NC}"
    fi
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
    
    # 检测proposal算法并重命名文件
    detect_proposals_and_rename_file
    
    # 设置理想网络条件
    setup_ideal_network
    
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
    done
    
    log "${CYAN}测试完成!${NC}"
    log "${GREEN}成功: $success_count 次${NC}"
    log "${RED}失败: $fail_count 次${NC}"
    
    # 计算统计数据
    if [ $success_count -gt 0 ]; then
        calculate_statistics
        generate_plot_script
        generate_plots
    else
        log "${RED}没有成功的测试，无法生成统计数据和图表${NC}"
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