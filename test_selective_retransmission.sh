#!/bin/bash

# 测试选择性重传功能的脚本
echo "=== 选择性重传功能测试 ==="

# 1. 确保调试功能开启
echo "1. 检查配置文件..."
grep -A 5 "debug" /etc/strongswan.conf

echo -e "\n2. 启动抓包（监听Moon端的重传）..."
echo "在另一个终端运行以下命令来监听重传："
echo "sudo tcpdump -i any -n host 192.168.31.117 and host 192.168.31.116 -v"

echo -e "\n3. 清理日志..."
sudo journalctl --vacuum-time=1s

echo -e "\n4. 启动连接测试..."
echo "准备启动IKE连接，注意观察："
echo "- 第1个分片是否被模拟丢失"
echo "- 第2个分片是否正常发送"
echo "- 是否收到ACK"
echo "- 是否立即重传第1个分片"

echo -e "\n开始测试... 按回车键继续"
read

# 启动连接
sudo swanctl --initiate --child moon-sun

echo -e "\n5. 检查日志结果..."
sudo journalctl -u strongswan-starter --since "1 minute ago" | grep -E "(SIMULATE|IMMEDIATE|RETRANSMIT|FRAGMENT_ACK)" | tail -20