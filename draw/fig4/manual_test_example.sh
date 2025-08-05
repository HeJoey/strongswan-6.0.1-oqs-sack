#!/bin/bash

# IPsec 手动测试示例脚本
# 演示如何在双端设置相同网络条件后进行测试

echo "=== IPsec 手动测试示例 ==="
echo ""
echo "此脚本演示如何进行手动模式测试："
echo ""

# 定义测试的丢包率
LOSS_RATES=(0 2 5 10 15 20)

echo "1. 将在本地和远程主机都设置以下丢包率进行测试："
for rate in "${LOSS_RATES[@]}"; do
    echo "   - ${rate}%"
done

echo ""
echo "2. 对于每个丢包率，您需要："
echo "   a) 在本地主机执行: sudo ./set_packet_loss.sh -r <rate>"
echo "   b) 在远程主机执行: sudo ./set_packet_loss.sh -r <rate>"
echo "   c) 在本地主机执行: sudo ./ipsec_burst_loss_analysis.sh -m -s <rate> -n 50"

echo ""
read -p "是否继续进行自动化测试？(y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "测试已取消。"
    exit 0
fi

echo ""
echo "开始自动化测试流程..."

for rate in "${LOSS_RATES[@]}"; do
    echo ""
    echo "=== 测试丢包率: ${rate}% ==="
    
    # 设置本地网络条件
    echo "设置本地网络条件..."
    sudo ./set_packet_loss.sh -r "$rate"
    
    echo ""
    echo "请在远程主机执行以下命令设置相同的网络条件："
    echo "  sudo ./set_packet_loss.sh -r $rate"
    echo ""
    read -p "远程主机设置完成后，按回车继续..."
    
    # 运行测试
    echo "开始测试..."
    sudo ./ipsec_burst_loss_analysis.sh -m -s "$rate" -n 50
    
    echo ""
    echo "测试完成。结果已保存。"
    read -p "按回车继续下一个丢包率测试..."
done

echo ""
echo "=== 所有测试完成 ==="
echo "清理本地网络条件..."
sudo ./set_packet_loss.sh -c

echo ""
echo "请在远程主机也执行清理命令："
echo "  sudo ./set_packet_loss.sh -c"
echo ""
echo "所有测试结果已保存在 test_results_* 目录中。" 