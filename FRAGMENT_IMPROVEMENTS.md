# strongSwan Fragment Reassembly and IKE_INTERMEDIATE Improvements

## 概述

本文档描述了strongSwan中分片重组机制和IKE_INTERMEDIATE响应处理的改进，包括分片缓存、超时机制、选择性重传功能和IKE_INTERMEDIATE响应缓存机制。

## 问题背景

原始的strongSwan分片重组机制存在以下问题：

1. **缺乏超时机制**：当某些分片丢失时，系统会无限期等待
2. **没有选择性重传**：无法针对性地请求丢失的分片
3. **效率低下**：使用线性搜索检查重复分片
4. **缺乏进度跟踪**：无法了解分片重组的进度
5. **IKE_INTERMEDIATE响应处理不完善**：缺乏针对IKE_INTERMEDIATE响应的缓存和选择性重传机制

## 改进功能

### 1. 分片缓存机制

- **位图跟踪**：使用位图高效跟踪已接收的分片
- **内存管理**：自动清理过期的分片缓存
- **重复检测**：快速检测重复分片

### 2. 超时机制

- **可配置超时**：通过配置文件设置分片重组超时时间
- **自动清理**：超时后自动清理相关资源
- **错误处理**：超时后返回适当的错误状态

### 3. 选择性重传

- **缺失分片检测**：准确识别缺失的分片编号
- **选择性请求**：只请求缺失的分片
- **重传限制**：限制重传次数避免无限循环

### 4. 进度跟踪

- **实时进度**：提供分片重组的实时进度信息
- **详细日志**：记录分片接收和缺失情况
- **调试支持**：便于问题诊断和性能分析

### 5. IKE_INTERMEDIATE响应缓存机制

- **响应缓存**：缓存IKE_INTERMEDIATE响应用于选择性重传
- **分片支持**：支持分片IKE_INTERMEDIATE响应的缓存和重组
- **超时清理**：自动清理过期的缓存条目
- **选择性重传**：针对IKE_INTERMEDIATE响应的选择性重传请求

## 配置选项

在 `strongswan.conf` 中可以配置以下选项：

```conf
# 分片重组超时时间（秒）
charon.fragment_timeout = 30

# 启用选择性重传
charon.selective_retransmission = yes

# 最大重传尝试次数
charon.max_retransmission_attempts = 3

# 重传请求间隔（秒）
charon.retransmission_interval = 5

# 启用分片进度日志
charon.fragment_progress_logging = no

# 分片缓存大小
charon.fragment_cache_size = 100

# 分片清理间隔（秒）
charon.fragment_cleanup_interval = 60

# IKE_INTERMEDIATE响应缓存超时（秒）
charon.intermediate_cache_timeout = 300

# 启用IKE_INTERMEDIATE选择性重传
charon.intermediate_selective_retransmission = yes
```

## API 接口

### 新增的Message接口

```c
// 获取缺失的分片编号
uint16_t* get_missing_fragments(message_t *this, uint16_t *count);

// 检查分片重组是否超时
bool is_fragment_timeout(message_t *this);

// 获取分片重组进度
bool get_fragment_progress(message_t *this, uint16_t *received, uint16_t *total);
```

### 使用示例

```c
message_t *defrag = message_create_defrag(fragment);
status_t status = defrag->add_fragment(defrag, msg);

if (status == NEED_MORE)
{
    // 检查是否超时
    if (defrag->is_fragment_timeout(defrag))
    {
        // 获取缺失的分片
        uint16_t missing_count;
        uint16_t *missing_frags = defrag->get_missing_fragments(defrag, &missing_count);
        
        // 发送选择性重传请求
        send_selective_retransmission_request(missing_frags, missing_count);
    }
    
    // 获取进度信息
    uint16_t received, total;
    if (defrag->get_fragment_progress(defrag, &received, &total))
    {
        printf("Progress: %d/%d fragments received\n", received, total);
    }
}
```

## 实现细节

### 数据结构

```c
typedef struct {
    uint16_t last;                    // 总分片数
    size_t len;                       // 已接收数据长度
    size_t max_packet;                // 最大包大小
    time_t start_time;                // 开始时间
    uint32_t timeout;                 // 超时时间
    uint8_t *received_bitmap;         // 接收位图
    uint16_t missing_count;           // 缺失分片数
    uint16_t *missing_fragments;      // 缺失分片列表
} fragment_data_t;
```

### 关键算法

1. **位图管理**：
   - 使用位图高效跟踪已接收分片
   - 支持快速重复检测和缺失分片识别

2. **超时检测**：
   - 基于单调时钟的超时检测
   - 自动清理超时的分片上下文

3. **选择性重传**：
   - 使用NOTIFY载荷发送重传请求
   - 支持批量请求多个缺失分片

## 性能优化

1. **内存效率**：位图比数组更节省内存
2. **查找效率**：O(1)时间复杂度的分片状态查询
3. **网络效率**：只重传缺失的分片，减少网络开销

## 兼容性

- 向后兼容：不影响现有的分片功能
- 渐进式启用：可以通过配置选项控制功能
- 标准兼容：遵循IKEv2协议规范

## 测试建议

1. **功能测试**：
   - 测试分片丢失场景
   - 验证超时机制
   - 检查选择性重传

2. **性能测试**：
   - 大量分片场景下的性能
   - 内存使用情况
   - 网络效率提升

3. **压力测试**：
   - 高并发分片重组
   - 极端网络条件
   - 资源限制场景

## 故障排除

### 常见问题

1. **分片重组超时**：
   - 检查网络连接
   - 调整超时时间
   - 查看详细日志

2. **内存泄漏**：
   - 检查分片缓存清理
   - 监控内存使用
   - 调整缓存大小

3. **重传循环**：
   - 检查重传次数限制
   - 调整重传间隔
   - 分析网络状况

### 调试技巧

1. 启用详细日志：
   ```conf
   charon.fragment_progress_logging = yes
   ```

2. 使用调试工具：
   - 网络抓包分析
   - 内存使用监控
   - 性能分析工具

## 未来改进

1. **自适应超时**：根据网络状况动态调整超时时间
2. **预测性重传**：基于网络质量预测可能丢失的分片
3. **压缩优化**：对分片数据进行压缩以减少传输开销
4. **并行处理**：支持并行分片重组以提高性能 