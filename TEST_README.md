# StrongSwan Task Manager Test Suite

这个测试套件用于理解和测试 StrongSwan IKEv2 任务管理器的选择性分片重传功能。

## 文件说明

### 测试程序
- `test.c` - 完整的 StrongSwan 集成测试程序（需要 StrongSwan 库）
- `test_simple.c` - 简化的独立测试程序（无外部依赖）

### 编译文件
- `Makefile.test` - 完整版本的编译文件
- `Makefile.simple` - 简化版本的编译文件

## 快速开始

### 方法1：运行简化版本（推荐）

```bash
# 使用简化版本，无需任何依赖
make -f Makefile.simple
make -f Makefile.simple run
```

### 方法2：尝试完整版本

```bash
# 先检查环境
make -f Makefile.simple check

# 如果有 StrongSwan 开发库
make -f Makefile.test
./test_task_manager

# 或者使用本地编译的 StrongSwan
make -f Makefile.test local
```

## 测试内容

### 简化版本测试 (`test_simple.c`)

这个版本模拟了 task_manager_v2.c 中的核心逻辑，包括：

1. **分片跟踪器管理**
   - 创建和销毁分片跟踪器
   - 添加分片到跟踪器
   - 管理分片状态

2. **选择性重传逻辑**
   - 模拟分片丢失场景
   - 处理 Fragment ACK 消息
   - 计算需要重传的分片
   - 指数退避算法

3. **传输统计**
   - 计算传输效率
   - 重传开销分析
   - 分片效率评估

### 完整版本测试 (`test.c`)

完整版本尝试使用真实的 StrongSwan API：

1. **库初始化**
   - StrongSwan 库初始化
   - 调试级别设置

2. **消息处理**
   - 创建大消息用于分片测试
   - 调用真实的消息分片功能

3. **任务管理器集成**
   - 创建 IKE SA
   - 测试任务管理器功能

## 测试场景演示

### 场景1：正常分片传输
```
消息大小: 8192 bytes
分片数量: 6 个
分片大小: 1400, 1400, 1400, 1400, 1400, 1192 bytes
```

### 场景2：部分分片丢失
```
发送: 分片 1,2,3,4,5,6
接收: 分片 1,2,4,6 (丢失 3,5)
重传: 仅重传分片 3,5
```

### 场景3：ACK处理
```
收到 ACK: 确认分片 1,2,3,4,6
状态更新: 标记已确认分片
重传决策: 仅重传分片 5
```

## 关键数据结构

### Fragment Tracker（分片跟踪器）
```c
typedef struct {
    uint32_t message_id;              // 消息ID
    uint16_t total_fragments;         // 总分片数
    uint16_t acked_fragments;         // 已确认分片数
    uint32_t total_original_size;     // 原始消息大小
    uint32_t total_transmitted_size;  // 累计传输大小
    // ... 其他字段
} fragment_tracker_t;
```

### Fragment State（分片状态）
```c
typedef struct {
    uint16_t fragment_id;             // 分片ID
    bool acknowledged;                // 是否已确认
    uint32_t retransmit_count;        // 重传次数
    uint32_t data_size;              // 分片大小
    uint32_t total_transmitted;      // 累计传输量
    // ... 其他字段
} fragment_state_t;
```

## 核心算法

### 1. 选择性重传算法
```c
// 只重传未确认的分片
for each fragment in tracker->fragments:
    if not fragment->acknowledged:
        if time_since_last_sent >= exponential_backoff_delay:
            retransmit(fragment)
            fragment->retransmit_count++
```

### 2. 指数退避算法
```c
// 计算重传延迟
time_t delay = 1 << min(retransmit_count, 4);  // 最大16秒
```

### 3. Fragment ACK 处理
```c
// 使用位图表示已接收的分片
uint16_t ack_bitmap[8];  // 支持最多64个分片
for (int i = 0; i < total_fragments; i++) {
    int word_index = i / 16;
    int bit_index = i % 16;
    bool is_acked = (ack_bitmap[word_index] & (1 << bit_index)) != 0;
    fragments[i]->acknowledged = is_acked;
}
```

## 性能指标

### 传输效率计算
```
效率 = 原始消息大小 / 总传输数据量 × 100%
```

### 重传开销
```
开销 = (总传输量 - 原始消息大小) / 原始消息大小 × 100%
```

### 分片效率分析
```
消息大小 | 分片数 | 效率  | 开销
1024     |   1    | 94.1% | 6.3%
8192     |   6    | 92.8% | 7.8%
16384    |  12    | 91.5% | 9.3%
```

## 调试和日志

程序输出详细的调试信息，包括：

- 分片创建和管理
- ACK 消息处理
- 重传决策过程
- 传输统计数据

### 示例输出
```
=== Testing Selective Retransmission Scenario ===
Creating fragment tracker: message_id=12345, total_fragments=6
Fragment tracker created successfully

--- Adding fragments to tracker ---
Added fragment 1: data_size=1400 bytes
Added fragment 2: data_size=1400 bytes
...

--- Scenario 1: Partial fragments received ---
Processing Fragment ACK: message_id=12345, received_count=4/6
Fragment 3 still missing
Fragment 5 still missing

--- Selective Retransmission Analysis ---
Message ID: 12345
Total fragments: 6
Acknowledged fragments: 4

Missing fragments analysis:
  Fragment 3: NEEDS RETRANSMIT
  Fragment 5: NEEDS RETRANSMIT

Retransmission summary:
  Fragments retransmitted: 2
  Data retransmitted: 2800 bytes
  Overall efficiency: 74.5%
```

## 扩展和修改

这个测试套件为你提供了理解和修改 StrongSwan 任务管理器的基础。你可以：

1. **修改算法参数**
   - 调整指数退避参数
   - 修改 ACK 超时时间
   - 改变分片大小策略

2. **添加新功能**
   - 实现新的重传策略
   - 添加拥塞控制
   - 增强统计功能

3. **测试不同场景**
   - 高丢包率环境
   - 大消息分片
   - 网络延迟变化

## 故障排除

### 编译问题
```bash
# 检查编译环境
make -f Makefile.simple check

# 只编译简化版本
make -f Makefile.simple
```

### 运行问题
```bash
# 查看详细输出
make -f Makefile.simple run-verbose

# 检查日志文件
cat test_output.log
```

### StrongSwan 库依赖
```bash
# Ubuntu/Debian
sudo apt-get install libstrongswan-dev strongswan-dev

# 或使用本地编译版本
make -f Makefile.test local
```

## 总结

这个测试套件帮助你：

1. 理解 StrongSwan 选择性分片重传的工作原理
2. 测试不同场景下的性能表现
3. 为修改和优化代码提供基础
4. 验证新功能的正确性

通过运行这些测试，你可以深入了解 IKE 消息分片处理的内部机制，为后续的开发和优化工作打下坚实基础。 