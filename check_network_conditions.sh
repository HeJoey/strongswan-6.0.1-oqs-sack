#!/bin/bash

# 检查网络条件设置脚本
# Check Network Conditions Script

echo "======================================"
echo "检查当前网络条件设置 (Checking Network Conditions)"
echo "======================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查tc命令是否存在
if ! command -v tc &> /dev/null; then
    echo -e "${RED}错误: tc命令未找到，请安装iproute2包${NC}"
    exit 1
fi

# 获取网络接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    echo -e "${RED}错误: 无法检测到默认网络接口${NC}"
    exit 1
fi

echo -e "${BLUE}检查接口: $INTERFACE${NC}"
echo ""

# 1. 检查qdisc (队列规则)
echo -e "${YELLOW}1. 队列规则 (Queue Disciplines):${NC}"
tc qdisc show dev $INTERFACE
echo ""

# 2. 检查class (类别)
echo -e "${YELLOW}2. 流量类别 (Traffic Classes):${NC}"
tc class show dev $INTERFACE
echo ""

# 3. 检查filter (过滤器)
echo -e "${YELLOW}3. 流量过滤器 (Traffic Filters):${NC}"
tc filter show dev $INTERFACE
echo ""

# 4. 详细的netem信息
echo -e "${YELLOW}4. 详细的netem设置:${NC}"
tc -s qdisc show dev $INTERFACE | grep -A 5 netem
echo ""

# 5. 使用ping测试实际延迟
echo -e "${YELLOW}5. 实际网络测试:${NC}"
TARGET_IP="192.168.31.135"  # sun机器IP
echo "测试到 $TARGET_IP 的延迟:"

# 发送5个ping包测试
ping -c 5 $TARGET_IP | grep -E "(time=|packet loss)" | while read line; do
    if [[ $line == *"time="* ]]; then
        echo -e "${GREEN}  $line${NC}"
    elif [[ $line == *"packet loss"* ]]; then
        echo -e "${BLUE}  $line${NC}"
    fi
done

echo ""

# 6. 检查是否有netem规则
echo -e "${YELLOW}6. netem规则检查:${NC}"
NETEM_RULES=$(tc qdisc show dev $INTERFACE | grep netem)
if [ -n "$NETEM_RULES" ]; then
    echo -e "${GREEN}✓ 发现netem规则:${NC}"
    echo "$NETEM_RULES"
    
    # 解析规则
    if echo "$NETEM_RULES" | grep -q "delay"; then
        DELAY=$(echo "$NETEM_RULES" | grep -o "delay [0-9]*ms" | head -1)
        echo -e "${GREEN}  - 延迟设置: $DELAY${NC}"
    fi
    
    if echo "$NETEM_RULES" | grep -q "loss"; then
        LOSS=$(echo "$NETEM_RULES" | grep -o "loss [0-9]*%" | head -1)
        echo -e "${GREEN}  - 丢包率设置: $LOSS${NC}"
    fi
    
    if echo "$NETEM_RULES" | grep -q "duplicate"; then
        DUP=$(echo "$NETEM_RULES" | grep -o "duplicate [0-9]*%" | head -1)
        echo -e "${GREEN}  - 重复包率: $DUP${NC}"
    fi
    
    if echo "$NETEM_RULES" | grep -q "corrupt"; then
        CORRUPT=$(echo "$NETEM_RULES" | grep -o "corrupt [0-9]*%" | head -1)
        echo -e "${GREEN}  - 损坏包率: $CORRUPT${NC}"
    fi
else
    echo -e "${RED}✗ 未发现netem规则 (网络条件未设置)${NC}"
fi

echo ""

# 7. 提供清除建议
echo -e "${YELLOW}7. 管理建议:${NC}"
echo "清除所有网络条件设置:"
echo -e "${BLUE}  sudo tc qdisc del dev $INTERFACE root${NC}"
echo ""
echo "设置延迟示例:"
echo -e "${BLUE}  sudo tc qdisc add dev $INTERFACE root netem delay 100ms${NC}"
echo ""
echo "设置丢包示例:"
echo -e "${BLUE}  sudo tc qdisc add dev $INTERFACE root netem loss 5%${NC}"
echo ""
echo "组合设置示例:"
echo -e "${BLUE}  sudo tc qdisc add dev $INTERFACE root netem delay 50ms loss 2%${NC}"

echo ""
echo "======================================"
echo "检查完成"
echo "======================================" 