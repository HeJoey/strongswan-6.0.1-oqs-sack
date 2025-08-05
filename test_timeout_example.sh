#!/bin/bash

# 超时机制测试示例

echo "=== strongSwan 分片重传超时机制测试示例 ==="
echo ""

echo "修改后的脚本新增功能："
echo "1. 连接超时机制 (-t 参数)"
echo "2. 区分一次成功和重传成功"
echo "3. 统计重传次数"
echo "4. 更详细的失败分类"
echo ""

echo "=== 使用示例 ==="
echo ""

echo "1. 设置30秒超时（默认）:"
echo "   sudo ./fragment_retransmission_test.sh -d 100 -l 15 site-to-site"
echo ""

echo "2. 设置60秒超时:"
echo "   sudo ./fragment_retransmission_test.sh -d 200 -l 20 -t 60 site-to-site"
echo ""

echo "3. 快速测试（10次，15秒超时）:"
echo "   sudo ./fragment_retransmission_test.sh -d 500 -l 30 -n 10 -t 15 site-to-site"
echo ""

echo "4. 快速对比测试（带超时）:"
echo "   sudo ./quick_comparison_test.sh -n 10 -t 45 site-to-site"
echo ""

echo "=== 新增结果类型 ==="
echo ""

echo "SUCCESS_ONE_SHOT  - 一次连接成功（<1秒）"
echo "SUCCESS_RETRANSMIT - 重传连接成功（≥1秒）"
echo "TIMEOUT           - 连接超时"
echo "FAILED            - 连接失败"
echo ""

echo "=== 统计信息 ==="
echo ""

echo "脚本现在会统计："
echo "- 一次成功率 vs 重传成功率"
echo "- 平均重传次数"
echo "- 超时和失败的比例"
echo "- 不同类型连接的平均时间"
echo ""

echo "=== 解决您提到的问题 ==="
echo ""

echo "1. 5%丢包率100%成功率问题："
echo "   - 现在会区分一次成功和重传成功"
echo "   - 可以看到实际的重传次数"
echo ""

echo "2. 15%丢包率卡住问题："
echo "   - 添加了超时机制，避免无限等待"
echo "   - 可以设置合适的超时时间"
echo ""

echo "3. 失败状态特殊标记："
echo "   - TIMEOUT: 超时失败"
echo "   - FAILED: 其他失败"
echo "   - 统计重传次数"
echo ""

echo "=== 建议测试参数 ==="
echo ""

echo "轻微网络问题："
echo "   sudo ./fragment_retransmission_test.sh -d 50 -l 5 -t 30 site-to-site"
echo ""

echo "中等网络问题："
echo "   sudo ./fragment_retransmission_test.sh -d 200 -l 15 -t 45 site-to-site"
echo ""

echo "严重网络问题："
echo "   sudo ./fragment_retransmission_test.sh -d 500 -l 30 -t 60 site-to-site"
echo ""

echo "快速验证："
echo "   sudo ./quick_comparison_test.sh -n 5 -t 30 site-to-site"
echo "" 