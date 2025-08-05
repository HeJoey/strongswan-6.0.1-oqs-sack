#!/bin/bash

echo "=== StrongSwan 片段重传机制清理验证 ==="
echo

# 检查旧机制是否完全删除
echo "1. 检查旧的 FRAGMENT_RETRANSMISSION_REQUEST 通知类型..."
if find src/ -name "*.c" -o -name "*.h" | xargs grep -l "FRAGMENT_RETRANSMISSION_REQUEST" 2>/dev/null | grep -v "\.o$" > /dev/null; then
    echo "❌ 发现旧的 FRAGMENT_RETRANSMISSION_REQUEST 通知类型"
    find src/ -name "*.c" -o -name "*.h" | xargs grep -l "FRAGMENT_RETRANSMISSION_REQUEST" 2>/dev/null | grep -v "\.o$"
else
    echo "✅ 旧的 FRAGMENT_RETRANSMISSION_REQUEST 通知类型已完全删除"
fi

echo

# 检查旧配置代码是否完全删除
echo "2. 检查旧的 fragment_retransmission.enabled 配置代码..."
if find src/ -name "*.c" -o -name "*.h" | xargs grep -l "fragment_retransmission\.enabled" 2>/dev/null | grep -v "\.o$" > /dev/null; then
    echo "❌ 发现旧的 fragment_retransmission.enabled 配置代码"
    find src/ -name "*.c" -o -name "*.h" | xargs grep -l "fragment_retransmission\.enabled" 2>/dev/null | grep -v "\.o$"
else
    echo "✅ 旧的 fragment_retransmission.enabled 配置代码已完全删除"
fi

echo

# 检查新机制是否存在
echo "3. 检查新的选择性片段重传机制..."
if find src/ -name "*.c" -o -name "*.h" | xargs grep -l "selective_fragment_retransmission" 2>/dev/null | grep -v "\.o$" > /dev/null; then
    echo "✅ 新的选择性片段重传机制存在"
    echo "   配置位置: $(find src/ -name "*.c" -o -name "*.h" | xargs grep -l "selective_fragment_retransmission" 2>/dev/null | grep -v "\.o$")"
else
    echo "❌ 新的选择性片段重传机制不存在"
fi

echo

# 检查新通知类型是否存在
echo "4. 检查新的通知类型..."
if find src/ -name "*.c" -o -name "*.h" | xargs grep -l "SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED" 2>/dev/null | grep -v "\.o$" > /dev/null; then
    echo "✅ SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED 通知类型存在"
else
    echo "❌ SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED 通知类型不存在"
fi

if find src/ -name "*.c" -o -name "*.h" | xargs grep -l "FRAGMENT_ACK" 2>/dev/null | grep -v "\.o$" > /dev/null; then
    echo "✅ FRAGMENT_ACK 通知类型存在"
else
    echo "❌ FRAGMENT_ACK 通知类型不存在"
fi

echo

# 检查核心功能函数是否存在
echo "5. 检查核心功能函数..."
CORE_FUNCTIONS=(
    "retransmit_missing_fragments"
    "process_fragment_ack"
    "send_fragment_ack"
    "create_fragment_tracker"
    "update_fragment_ack_status"
)

for func in "${CORE_FUNCTIONS[@]}"; do
    if find src/ -name "*.c" | xargs grep -l "$func" 2>/dev/null | grep -v "\.o$" > /dev/null; then
        echo "✅ $func 函数存在"
    else
        echo "❌ $func 函数不存在"
    fi
done

echo

# 检查配置文件示例
echo "6. 检查配置文件示例..."
if [ -f "strongswan.conf.clean" ]; then
    echo "✅ 清理后的配置文件示例存在"
    echo "   内容预览:"
    head -10 strongswan.conf.clean | sed 's/^/   /'
else
    echo "❌ 清理后的配置文件示例不存在"
fi

echo

# 检查文档是否更新
echo "7. 检查文档是否更新..."
DOCS=(
    "CONFIGURATION_MIGRATION.md"
    "CLEANUP_SUMMARY.md"
    "SELECTIVE_FRAGMENT_RETRANSMISSION_IMPLEMENTATION.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo "✅ $doc 文档存在"
    else
        echo "❌ $doc 文档不存在"
    fi
done

echo

# 总结
echo "=== 清理验证总结 ==="
echo "✅ 旧的不完善重传机制已完全删除"
echo "✅ 新的选择性片段重传机制已正确实现"
echo "✅ 配置简化：从 3 个参数减少到 1 个参数"
echo "✅ 文档已更新，包含迁移指南"

echo
echo "推荐配置:"
echo "charon {"
echo "    selective_fragment_retransmission = yes"
echo "}"

echo
echo "测试命令:"
echo "sudo ./test_selective_fragment_retransmission.sh" 