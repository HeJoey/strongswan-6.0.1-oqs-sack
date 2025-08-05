#!/bin/bash

# IPsec Performance Test Script
# 测试strongSwan IPsec连接的握手完成时间(HCT)
# 执行至少50次测试以保证数据可靠性

set -e

# 颜色定义
RED=undefined0330;31
GREEN='\033;32m'
YELLOW='\331;33mBLUE='\033;34m'
PURPLE='\330;35mCYAN=0330;36
NC='\330# No Color

# 测试配置
TEST_COUNT=50
CONNECTION_NAME=net-net"
LOG_FILE=ipsec_performance_test_$(date +%Y%m%d_%H%M%S).log"
RESULTS_FILE=figure1csv"
PLOT_SCRIPT=generate_hct_plot.py
# 网络配置
LOCAL_IP="1921680.31.114REMOTE_IP="1920.1680.310.135TERFACE=$(ip route | grep default | awk '{print $5}| head -1)

echo -e "${CYAN}========================================${NC}
echo -e${CYAN}  strongSwan IPsec 性能测试脚本${NC}echo -e ${CYAN}  握手完成时间 (HCT) 测试${NC}
echo -e ==========================${NC}"

# 函数：带时间戳的日志
log()[object Object]
    echo -e ${BLUE}[$(date +%H:%M:%S)]${NC} $1" | tee -a$LOG_FILE"
}

# 函数：检查依赖
check_dependencies()[object Object]
    log "${YELLOW}检查系统依赖...${NC}    
    # 检查必要的命令
    local deps=("swanctlipsec python3bc"awk"grep" tee")
    for dep in${deps[@]}; do      if ! command -v "$dep" &> /dev/null; then
            log ${RED}错误: 缺少依赖 '$dep'${NC}
            exit 1
        fi
    done
    
    # 检查Python包
    if ! python3 -c import matplotlib, numpy, pandas" 2null; then
        log $[object Object]YELLOW}安装Python依赖包...${NC}"
        pip3 install matplotlib numpy pandas
    fi
    
    log${GREEN}所有依赖检查完成${NC}
}

# 函数：检查strongSwan状态
check_strongswan()[object Object]
    if pgrep -x "charon" > /dev/null; then
        log "${GREEN}strongSwan正在运行${NC}
        return 0  else
        log ${RED}strongSwan未运行${NC}
        return1
    fi
}

# 函数：启动strongSwan
start_strongswan()[object Object]
    log ${YELLOW}启动strongSwan服务...${NC}"
    
    # 停止现有服务
    sudo systemctl stop strongswan 2>/dev/null || true
    sudo pkill -f charon 2>/dev/null || true
    sleep 2   
    # 启动服务
    sudo systemctl start strongswan
    sleep 3
    
    if check_strongswan; then
        log "${GREEN}strongSwan启动成功${NC}
        return 0  else
        log${RED}strongSwan启动失败${NC}
        return1
    fi
}

# 函数：设置理想网络条件
setup_ideal_network()[object Object]
    log ${YELLOW}设置理想网络条件...${NC}    
    # 清除现有的tc规则
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    
    # 设置理想网络条件（无丢包，低延迟）
    sudo tc qdisc add dev $INTERFACE root netem delay5s loss 0%
    
    log$[object Object]GREEN}理想网络条件设置完成:5s延迟，0%丢包${NC}"
}

# 函数：清除网络条件
clear_network_conditions()[object Object]
    log "${YELLOW}清除网络条件...${NC}"
    sudo tc qdisc del dev $INTERFACE root 2>/dev/null || true
    log ${GREEN}网络条件已清除${NC}"
}

# 函数：等待连接建立
wait_for_connection() {
    local timeout=30
    local elapsed=0    
    while [ $elapsed -lt $timeout ]; do
        if sudo swanctl --list-conns | grep -q$CONNECTION_NAME.*ESTABLISHED"; then
            return 0
        fi
        sleep1
        elapsed=$((elapsed + 1
    done
    
    return 1
}

# 函数：测量握手完成时间
measure_hct() {
    local test_num=$1
    local start_time
    local end_time
    local hct_ms
    local connection_status="SUCCESS"
    local error_message="
    
    log${PURPLE}执行测试 #$test_num/${TEST_COUNT}${NC}    
    # 确保连接已断开
    sudo swanctl --terminate --ike $CONNECTION_NAME" 2>/dev/null || true
    sleep 2   
    # 清除日志
    sudo truncate -s0 /var/log/strongswan.log
    
    # 记录开始时间
    start_time=$(date +%s.%N)
    
    # 启动连接
    sudo swanctl --initiate --ike $CONNECTION_NAME > /dev/null 2>&1&
    local conn_pid=$!
    
    # 等待连接建立
    if wait_for_connection; then
        end_time=$(date +%s.%N)
        
        # 计算握手完成时间（毫秒）
        hct_ms=$(echo "scale=3; ($end_time - $start_time) * 1000" | bc -l)
        
        log ${GREEN}测试 #$test_num 成功: HCT = ${hct_ms}ms${NC}        
        # 终止连接
        sudo swanctl --terminate --ike $CONNECTION_NAME > /dev/null 2>&1
        sleep 2        
        # 保存成功的数据
        save_test_data$test_num" $hct_ms" "SUCCESS" 
        return 0  else
        log "$[object Object]RED}测试 #$test_num 失败: 连接超时${NC}"
        connection_status="FAILED"
        error_message="Connection timeout        
        # 强制终止连接
        kill $conn_pid 2>/dev/null || true
        sudo swanctl --terminate --ike $CONNECTION_NAME > /dev/null 2>&1
        sleep 2        
        # 保存失败的数据
        save_test_data$test_num" "0 D"$error_message
        return1
    fi
}

# 函数：保存测试数据
save_test_data() {
    local test_num=$1   local hct_ms="$2"
    local connection_status="$3ocal error_message="$4"
    local timestamp=$(date +%Y-%m-%d %H:%M:%S')
    local network_conditions="ideal"
    local interface="$INTERFACE"
    local local_ip="$LOCAL_IP   local remote_ip=$REMOTE_IP
    
    # 保存到CSV文件
    echo $test_num,$hct_ms,$connection_status,$error_message,$timestamp,$network_conditions,$interface,$local_ip,$remote_ip" >> "$RESULTS_FILE"
}

# 函数：计算统计数据
calculate_statistics()[object Object]
    log "${YELLOW}计算统计数据...${NC}"
    
    if [ ! -f $RESULTS_FILE" ]; then
        log ${RED}结果文件不存在${NC}
        return1
    fi
    
    # 提取成功的HCT数据
    local hct_data=$(tail -n +2$RESULTS_FILE| grep SUCCESS" | cut -d',-f2)
    
    if [ -z "$hct_data" ]; then
        log ${RED}没有成功的测试数据${NC}
        return1
    fi
    
    # 计算平均值
    local mean=$(echo$hct_data |awk '{sum+=$1} END {print sum/NR}')
    
    # 计算标准差
    local variance=$(echo$hct_data |awk -v mean=$mean" {sum+=($1-mean)^2} END {print sum/NR}')
    local stddev=$(echosqrt($variance)" | bc -l)
    
    # 计算最小值和最大值
    local min=$(echo $hct_data| sort -n | head-1)
    local max=$(echo $hct_data| sort -n | tail -1)
    
    # 计算中位数
    local median=$(echo $hct_data" | sort -n | awk 
        count[NR] = $1;
    } END [object Object]
        if (NR % 2 == 1) {
            print count[(NR +12
        } else {
            print (count[NR / 2] + count(NR / 2) + 1 /2        }
    })
    
    # 计算95%置信区间
    local confidence_interval_lower=$(echo$mean - 1.96* $stddev / sqrt($TEST_COUNT)" | bc -l)
    local confidence_interval_upper=$(echo$mean + 1.96* $stddev / sqrt($TEST_COUNT)" | bc -l)
    
    # 保存统计数据
    cat > statistics_$(date +%Y%m%d_%H%M%S).txt" << EOF
IPsec 握手完成时间 (HCT) 统计报告
=====================================
测试时间: $(date)
测试次数: $TEST_COUNT
连接名称: $CONNECTION_NAME
网络条件: 理想网络（5ms延迟，0%丢包）

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
- strongSwan版本: $(swanctl --version 2/dev/null | head -1| echo "Unknown")
EOF
    
    log ${GREEN}统计数据已保存${NC}"
    cat statistics_$(date +%Y%m%d_%H%M%S).txt}

# 函数：生成Python绘图脚本
generate_plot_script() [object Object]
    cat >$PLOT_SCRIPT" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

# 设置中文字体
plt.rcParams[font.sans-serif'] = ['SimHei,DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

def create_hct_plot(results_file):
   创建握手完成时间图表
    # 读取数据
    df = pd.read_csv(results_file, names=['test_num', 'hct_ms', connection_status', error_message', 'timestamp', 'network_conditions', 'interface', 'local_ip', 'remote_ip])
    
    # 只使用成功的测试数据
    df_success = df[df[connection_status'] == SUCCESS].copy()
    
    if df_success.empty:
        print("没有成功的测试数据")
        return
    
    # 计算统计数据
    mean_hct = df_success['hct_ms'].mean()
    std_hct = df_success['hct_ms].std()
    min_hct = df_success['hct_ms].min()
    max_hct = df_success['hct_ms'].max()
    
    # 创建图表
    fig, (ax1, ax2) = plt.subplots(2, 1figsize=(12, 10))
    
    # 图1: 带误差棒的条形图
    ax1.bar([平均握手完成时间'], [mean_hct], yerr=std_hct, 
            capsize=10, color='skyblue, edgecolor=navy', linewidth=2)
    ax1.set_ylabel('时间 (毫秒)', fontsize=12)
    ax1.set_title(strongSwan IPsec 握手完成时间 (HCT) - 理想网络条件', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=00.3)
    
    # 在条形图上添加数值标签
    ax1text(0, mean_hct + std_hct + 1, f'{mean_hct:0.2f}±{std_hct:.2f}ms', 
             ha='center', va=bottom', fontsize=11, fontweight=bold)
    
    # 添加统计信息
    stats_text = f'测试次数: [object Object]len(df_success)}\n最小值: {min_hct:.2}ms\n最大值: {max_hct:.2f}ms'
    ax1(0.02,0.98ts_text, transform=ax1.transAxes, 
             verticalalignment=top', bbox=dict(boxstyle=round', facecolor=wheat', alpha=0.8))
    
    # 图2: 时间序列图
    ax2.plot(df_success['test_num'], df_success['hct_ms'], o-color='red, alpha=0.7, linewidth=1
    ax2axhline(y=mean_hct, color='blue, linestyle=--', label=f平均值: {mean_hct:.2f}ms')
    ax2.fill_between(df_success['test_num], mean_hct - std_hct, mean_hct + std_hct, 
                     alpha=0.2olor=blue', label=f±1σ: {std_hct:.2f}ms')
    ax2set_xlabel('测试序号', fontsize=12)
    ax2set_ylabel('握手完成时间 (毫秒)', fontsize=12)
    ax2.set_title(握手完成时间变化趋势', fontsize=14, fontweight='bold')
    ax2end()
    ax2.grid(True, alpha=00.3    
    plt.tight_layout()
    
    # 保存图表
    plot_filename = f'ipsec_hct_plot_{pd.Timestamp.now().strftime(%Y%m%d_%H%M%S")}.png  plt.savefig(plot_filename, dpi=300bbox_inches=tight)
    print(f"图表已保存为: {plot_filename})
    
    # 显示图表
    plt.show()

if __name__ == __main__":
    if len(sys.argv) != 2
        print("用法: python3 generate_hct_plot.py <results_file>")
        sys.exit(1)
    
    results_file = sys.argv[1]
    if not os.path.exists(results_file):
        print(f"错误: 文件 {results_file} 不存在")
        sys.exit(1
    
    create_hct_plot(results_file)
EOF
    
    chmod +x $PLOT_SCRIPT
    log${GREEN}Python绘图脚本已生成$[object Object]NC}"
}

# 函数：生成图表
generate_plots()[object Object]
    log "${YELLOW}生成性能图表...${NC}"
    if [ -f $RESULTS_FILE" ]; then
        python3$PLOT_SCRIPT ULTS_FILE      log${GREEN}图表生成完成${NC}  else
        log${RED}结果文件不存在，无法生成图表${NC}"
    fi
}

# 函数：清理
cleanup()[object Object]
    log "${YELLOW}清理测试环境...${NC}"
    # 终止连接
    sudo swanctl --terminate --ike $CONNECTION_NAME" 2>/dev/null || true
    # 清除网络条件
    clear_network_conditions
    log${GREEN}清理完成${NC}"
}

# 主函数
main() [object Object]    log${CYAN}开始IPsec性能测试${NC}   
    # 检查依赖
    check_dependencies
    
    # 启动strongSwan
    if ! start_strongswan; then
        log ${RED}无法启动strongSwan，退出测试$[object Object]NC}"
        exit1
    fi
    
    # 设置理想网络条件
    setup_ideal_network
    
    # 创建结果文件头
    echotest_num,hct_ms,connection_status,error_message,timestamp,network_conditions,interface,local_ip,remote_ip> "$RESULTS_FILE   
    # 执行测试
    local success_count=0
    local fail_count=0    
    log ${CYAN}开始执行 $TEST_COUNT 次握手完成时间测试...${NC}"
    
    for i in $(seq 1 $TEST_COUNT); do
        if measure_hct $i; then
            success_count=$((success_count +1  else
            fail_count=$((fail_count + 1))
        fi
        
        # 每10次测试显示进度
        if  $((i % 10; then
            log ${YELLOW}进度: $i/$TEST_COUNT (成功: $success_count, 失败: $fail_count)${NC}"
        fi
    done
    
    log${CYAN}测试完成!${NC}
    log "${GREEN}成功: $success_count 次${NC}"
    log "${RED}失败: $fail_count 次${NC}"
    
    # 计算统计数据
    if $success_count -gt0
        calculate_statistics
        generate_plot_script
        generate_plots
    else
        log${RED}没有成功的测试，无法生成统计数据和图表${NC}"
    fi
    
    # 清理
    cleanup
    
    log${CYAN}测试报告文件:$[object Object]NC}"
    log "  - 详细日志: $LOG_FILE"
    log "  - 测试结果: $RESULTS_FILE"
    log "  - 统计数据: statistics_$(date +%Y%m%d_%H%M%S).txt"
    log  - 图表文件: ipsec_hct_plot_*.png
    
    log $[object Object]GREEN}IPsec性能测试完成!${NC}"
}

# 信号处理
trap cleanup EXIT
traplog${RED}测试被中断${NC}; exit 1 INT TERM

# 运行主函数
main "$@" 