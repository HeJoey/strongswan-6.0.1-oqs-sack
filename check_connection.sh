#!/bin/bash

# 连接检查脚本

echo "=== strongSwan 连接检查 ==="
echo ""

# 检查strongSwan服务状态
echo "1. 检查strongSwan服务状态:"
if systemctl is-active --quiet strongswan; then
    echo "   ✅ strongSwan服务正在运行"
else
    echo "   ❌ strongSwan服务未运行"
    echo "   启动服务: sudo systemctl start strongswan"
    exit 1
fi

echo ""

# 检查可用连接
echo "2. 检查可用连接:"
if sudo swanctl --list-conns >/dev/null 2>&1; then
    echo "   ✅ swanctl命令可用"
    echo "   可用的连接:"
    sudo swanctl --list-conns | grep -E "^[^[:space:]]+:" | while read line; do
        conn_name=$(echo "$line" | cut -d':' -f1)
        echo "   - $conn_name"
    done
else
    echo "   ❌ swanctl命令不可用"
    echo "   请检查strongSwan安装和配置"
    exit 1
fi

echo ""

# 检查网络接口
echo "3. 检查网络接口:"
default_interface=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -n "$default_interface" ]]; then
    echo "   ✅ 默认网络接口: $default_interface"
    if ip link show $default_interface >/dev/null 2>&1; then
        echo "   ✅ 接口 $default_interface 存在且可用"
    else
        echo "   ❌ 接口 $default_interface 不可用"
    fi
else
    echo "   ❌ 未找到默认网络接口"
fi

echo ""

# 检查tc命令
echo "4. 检查网络工具:"
if command -v tc >/dev/null 2>&1; then
    echo "   ✅ tc命令可用"
else
    echo "   ❌ tc命令不可用"
    echo "   安装: sudo apt-get install iproute2"
fi

if command -v bc >/dev/null 2>&1; then
    echo "   ✅ bc命令可用"
else
    echo "   ❌ bc命令不可用"
    echo "   安装: sudo apt-get install bc"
fi

echo ""

# 检查timeout命令
if command -v timeout >/dev/null 2>&1; then
    echo "   ✅ timeout命令可用"
else
    echo "   ❌ timeout命令不可用"
    echo "   这通常是coreutils的一部分，请检查安装"
fi

echo ""

echo "=== 使用建议 ==="
echo ""

# 获取第一个可用连接
first_conn=$(sudo swanctl --list-conns | grep -E "^[^[:space:]]+:" | head -1 | cut -d':' -f1)

if [[ -n "$first_conn" ]]; then
    echo "建议使用连接: $first_conn"
    echo ""
    echo "测试命令示例:"
    echo "sudo ./fragment_retransmission_test.sh $first_conn"
    echo "sudo ./quick_comparison_test.sh $first_conn"
    echo ""
    echo "或者手动指定连接名称:"
    echo "sudo ./fragment_retransmission_test.sh your-connection-name"
    echo "sudo ./quick_comparison_test.sh your-connection-name"
else
    echo "未找到可用连接，请先配置strongSwan连接"
fi

echo "" 