#!/bin/bash
# 传统分片性能测试 - 快速启动脚本

echo "========================================"
echo "   传统分片机制性能测试工具"
echo "========================================"
echo

# 检查是否在正确目录
if [ ! -f "traditional_fragment_performance_test.py" ]; then
    echo "❌ 错误：请在tradition目录下运行此脚本"
    echo "使用方法："
    echo "  cd tradition/"
    echo "  ./quick_start.sh"
    exit 1
fi

# 检查权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ 需要root权限运行此脚本"
    echo "请使用: sudo ./quick_start.sh"
    exit 1
fi

echo "✅ 环境检查通过"
echo

# 显示菜单
echo "请选择测试模式："
echo "1) 快速测试 (推荐) - 4个丢包率，每个50次，约30分钟"
echo "2) 完整测试 - 12个丢包率，每个500次，约3-4小时"
echo "3) 查看帮助文档"
echo "4) 退出"
echo

read -p "请选择 (1-4): " choice

case $choice in
    1)
        echo "=== 启动快速测试 ==="
        python3 run_test.py << EOF
1
EOF
        ;;
    2)
        echo "=== 启动完整测试 ==="
        echo "警告：完整测试将运行3-4小时"
        read -p "确认继续？ (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            python3 run_test.py << EOF
2
y
EOF
        else
            echo "测试取消"
        fi
        ;;
    3)
        echo "=== 帮助文档 ==="
        if [ -f "README.md" ]; then
            less README.md
        else
            echo "README.md 文件未找到"
        fi
        ;;
    4)
        echo "退出"
        exit 0
        ;;
    *)
        echo "无效选择"
        exit 1
        ;;
esac

echo
echo "测试完成！查看结果文件："
echo "- traditional_fragment_detailed_*.json (详细数据)"
echo "- traditional_fragment_summary_*.json (汇总结果)" 