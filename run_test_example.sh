#!/bin/bash

# strongSwan 分片重传测试使用示例脚本

echo "=== strongSwan 分片重传网络测试示例 ==="
echo ""

# 检查脚本是否存在
if [[ ! -f "fragment_retransmission_test.sh" ]]; then
    echo "错误: fragment_retransmission_test.sh 脚本不存在"
    exit 1
fi

if [[ ! -f "quick_comparison_test.sh" ]]; then
    echo "错误: quick_comparison_test.sh 脚本不存在"
    exit 1
fi

echo "可用的测试脚本:"
echo "1. fragment_retransmission_test.sh - 详细单场景测试"
echo "2. quick_comparison_test.sh - 快速多场景对比测试"
echo ""

echo "=== 使用示例 ==="
echo ""

echo "1. 基本测试（正常网络，100次连接）:"
echo "   sudo ./fragment_retransmission_test.sh site-to-site"
echo ""

echo "2. 设置网络延迟和丢包率:"
echo "   sudo ./fragment_retransmission_test.sh -d 100 -l 10 site-to-site"
echo ""

echo "3. 快速测试（少量次数）:"
echo "   sudo ./fragment_retransmission_test.sh -d 200 -l 15 -n 20 site-to-site"
echo ""

echo "4. 快速对比测试（多个网络场景）:"
echo "   sudo ./quick_comparison_test.sh site-to-site"
echo ""

echo "5. 自定义对比测试:"
echo "   sudo ./quick_comparison_test.sh -n 30 site-to-site"
echo ""

echo "=== 测试场景建议 ==="
echo ""

echo "基线测试（正常网络）:"
echo "   sudo ./fragment_retransmission_test.sh site-to-site"
echo ""

echo "轻微网络问题测试:"
echo "   sudo ./fragment_retransmission_test.sh -d 50 -l 5 site-to-site"
echo ""

echo "中等网络问题测试:"
echo "   sudo ./fragment_retransmission_test.sh -d 200 -l 15 site-to-site"
echo ""

echo "严重网络问题测试:"
echo "   sudo ./fragment_retransmission_test.sh -d 500 -l 30 site-to-site"
echo ""

echo "=== 注意事项 ==="
echo ""

echo "1. 确保以root权限运行脚本"
echo "2. 确保strongSwan服务已正确配置"
echo "3. 确保指定的连接名称存在且配置正确"
echo "4. 确保对端设备可达"
echo "5. 测试前建议手动验证连接配置"
echo ""

echo "=== 查看帮助信息 ==="
echo ""

echo "查看详细帮助:"
echo "   sudo ./fragment_retransmission_test.sh -h"
echo "   sudo ./quick_comparison_test.sh -h"
echo ""

echo "=== 查看测试结果 ==="
echo ""

echo "测试完成后，查看生成的报告文件:"
echo "   ls -la test_stats_*.txt"
echo "   ls -la comparison_report_*.txt"
echo ""

echo "=== 快速开始 ==="
echo ""

echo "要开始测试，请选择一个连接名称，例如:"
echo "   sudo ./fragment_retransmission_test.sh your-connection-name"
echo ""

echo "或者运行快速对比测试:"
echo "   sudo ./quick_comparison_test.sh your-connection-name"
echo "" 