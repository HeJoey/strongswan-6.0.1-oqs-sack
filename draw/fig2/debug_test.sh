#!/bin/bash

echo "=== 调试测试脚本 ==="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "需要root权限"
    exit 1
fi

echo "1. 检查strongSwan服务..."
if systemctl is-active --quiet strongswan; then
    echo "   strongSwan服务运行正常"
else
    echo "   strongSwan服务未运行"
    exit 1
fi

echo "2. 检查连接配置..."
if sudo swanctl --list-conns | grep -q "net-net"; then
    echo "   连接配置 net-net 存在"
else
    echo "   连接配置 net-net 不存在"
    exit 1
fi

echo "3. 断开现有连接..."
sudo swanctl --terminate --child "net-net" >/dev/null 2>&1 || echo "   无现有连接或断开失败"
sleep 2

echo "4. 启动新连接..."
if sudo swanctl --initiate --child "net-net" >/dev/null 2>&1; then
    echo "   连接启动成功"
else
    echo "   连接启动失败"
    exit 1
fi

echo "5. 等待连接建立..."
for i in {1..10}; do
    if sudo swanctl --list-sas | grep -q "net-net.*ESTABLISHED"; then
        echo "   连接建立成功"
        break
    fi
    echo "   等待中... ($i/10)"
    sleep 1
done

echo "6. 测试完成" 