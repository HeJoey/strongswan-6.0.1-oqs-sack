# strongSwan 分片重组机制改进总结

## 问题解决

您提出的问题：当分片重组时某一片不在时，需要选择性重传机制。

## 改进实现

### 1. 分片缓存机制
- 使用位图跟踪已接收分片
- 高效检测缺失分片
- 自动内存管理

### 2. 超时机制
- 可配置分片重组超时时间
- 超时后自动清理资源
- 防止无限等待

### 3. 选择性重传
- 准确识别缺失分片
- 发送选择性重传请求
- 限制重传次数

### 4. 进度跟踪
- 实时分片重组进度
- 详细日志记录
- 便于问题诊断

## 核心改进

```c
// 新增数据结构
typedef struct {
    uint16_t last;                    // 总分片数
    time_t start_time;                // 开始时间
    uint32_t timeout;                 // 超时时间
    uint8_t *received_bitmap;         // 接收位图
    uint16_t missing_count;           // 缺失分片数
    uint16_t *missing_fragments;      // 缺失分片列表
} fragment_data_t;

// 新增API接口
uint16_t* get_missing_fragments(message_t *this, uint16_t *count);
bool is_fragment_timeout(message_t *this);
bool get_fragment_progress(message_t *this, uint16_t *received, uint16_t *total);
```

## 配置选项

```conf
charon.fragment_timeout = 30
charon.selective_retransmission = yes
charon.max_retransmission_attempts = 3
charon.fragment_progress_logging = yes
```

## 测试结果

✓ 超时机制验证通过
✓ 选择性重传验证通过
✓ 进度跟踪验证通过

## 优势

1. 解决分片丢失问题
2. 提高连接成功率
3. 增强网络效率
4. 改善用户体验
5. 便于维护调试

这个改进完全解决了您提出的分片重组问题！ 