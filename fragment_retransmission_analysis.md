# strongSwan 分片选择重传机制问题分析与改进方案

## 当前问题分析

### 1. 日志问题分析

从你提供的日志中可以看出以下问题：

#### 接收端状态（sun机器）
```
received fragment #1 of 7, waiting for complete IKE message
received fragment #2 of 7, waiting for complete IKE message
received fragment #3 of 7, waiting for complete IKE message
received fragment #4 of 7, waiting for complete IKE message
received fragment #5 of 7, waiting for complete IKE message
received fragment #7 of 7, waiting for complete IKE message
received duplicate fragment #1
received duplicate fragment #3
received duplicate fragment #4
received fragment #6 of 7, reassembled fragmented IKE message (7328 bytes)
```

#### 发送端状态（moon机器）
```
retransmit 1 of request with message ID 1
retransmit 2 of request with message ID 1
retransmit 3 of request with message ID 1
retransmit 4 of request with message ID 1
```

#### 问题总结
1. **接收端已收到分片**: #1, #2, #3, #4, #5, #7
2. **接收端缺失分片**: #6
3. **发送端行为**: 每次重传都发送所有7个分片
4. **效率问题**: 重复传输大量已收到的数据

### 2. 代码层面问题

#### 当前重传机制 (`task_manager_v2.c`)
```c
METHOD(task_manager_t, retransmit, status_t,
    private_task_manager_t *this, uint32_t message_id)
{
    // ... 检查逻辑 ...
    
    // 问题：重传所有分片包
    send_packets(this, this->initiating.packets,
                 this->ike_sa->get_my_host(this->ike_sa),
                 this->ike_sa->get_other_host(this->ike_sa));
}
```

#### 选择性重传逻辑不完善
```c
// 当前的选择性重传只发送通知，不实际重传
if (status == NEED_MORE && (*defrag)->is_fragment_timeout(*defrag))
{
    // 发送选择性重传请求通知
    send_selective_retransmission_request(...);
}
```

## 改进方案

### 1. 分片状态跟踪机制

#### 发送端分片状态跟踪
```c
typedef struct {
    uint16_t fragment_id;
    packet_t *packet;
    bool acknowledged;          // 是否已确认收到
    time_t last_sent;          // 最后发送时间
    uint32_t retransmit_count; // 重传次数
} fragment_state_t;

typedef struct {
    array_t *fragments;        // fragment_state_t 数组
    uint16_t total_fragments;  // 总分片数
    uint16_t acked_fragments;  // 已确认分片数
    time_t last_ack_time;     // 最后确认时间
} fragment_tracker_t;
```

#### 接收端分片确认机制
```c
typedef struct {
    uint16_t *received_fragments;  // 已收到的分片ID列表
    uint16_t received_count;       // 已收到分片数
    uint16_t total_expected;       // 期望总分片数
    uint8_t *bitmap;              // 接收位图
} fragment_ack_t;
```

### 2. 选择性重传协议改进

#### 分片确认消息格式
```c
// 新的通知类型
#define FRAGMENT_ACK_NOTIFY 16430

// 分片确认数据格式
struct fragment_ack_data {
    uint16_t message_id;           // 消息ID
    uint16_t total_fragments;      // 总分片数
    uint16_t received_count;       // 已收到分片数
    uint16_t received_fragments[]; // 已收到分片ID列表
};
```

#### 改进的重传逻辑
```c
METHOD(task_manager_t, retransmit, status_t,
    private_task_manager_t *this, uint32_t message_id)
{
    fragment_tracker_t *tracker = get_fragment_tracker(this, message_id);
    
    if (tracker && tracker->fragments)
    {
        // 选择性重传：只重传未确认的分片
        return retransmit_missing_fragments(this, tracker);
    }
    else
    {
        // 传统重传：重传所有分片
        return retransmit_all_fragments(this, message_id);
    }
}

static status_t retransmit_missing_fragments(private_task_manager_t *this,
                                           fragment_tracker_t *tracker)
{
    enumerator_t *enumerator;
    fragment_state_t *fragment;
    array_t *missing_packets;
    
    missing_packets = array_create(0, 0);
    
    enumerator = array_create_enumerator(tracker->fragments);
    while (enumerator->enumerate(enumerator, &fragment))
    {
        if (!fragment->acknowledged)
        {
            // 只重传未确认的分片
            array_insert(missing_packets, ARRAY_TAIL, fragment->packet);
            fragment->retransmit_count++;
            fragment->last_sent = time_monotonic(NULL);
        }
    }
    enumerator->destroy(enumerator);
    
    if (array_count(missing_packets) > 0)
    {
        DBG1(DBG_IKE, "selective retransmit %d missing fragments for message ID %d",
             array_count(missing_packets), tracker->message_id);
        
        send_packets(this, missing_packets,
                     this->ike_sa->get_my_host(this->ike_sa),
                     this->ike_sa->get_other_host(this->ike_sa));
    }
    
    array_destroy(missing_packets);
    return SUCCESS;
}
```

### 3. 分片确认处理

#### 接收端发送确认
```c
static void send_fragment_ack(private_task_manager_t *this,
                             message_t *defrag, uint32_t message_id)
{
    uint16_t received_count;
    uint16_t *received_frags;
    chunk_t ack_data;
    message_t *ack_msg;
    
    // 获取已收到的分片列表
    received_frags = defrag->get_received_fragments(defrag, &received_count);
    
    // 构造确认数据
    struct fragment_ack_data *ack = malloc(sizeof(*ack) + 
                                          received_count * sizeof(uint16_t));
    ack->message_id = htons(message_id);
    ack->total_fragments = htons(defrag->get_total_fragments(defrag));
    ack->received_count = htons(received_count);
    memcpy(ack->received_fragments, received_frags, 
           received_count * sizeof(uint16_t));
    
    ack_data = chunk_create((uint8_t*)ack, 
                           sizeof(*ack) + received_count * sizeof(uint16_t));
    
    // 发送确认消息
    ack_msg = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
    ack_msg->set_exchange_type(ack_msg, INFORMATIONAL);
    ack_msg->set_request(ack_msg, FALSE);
    ack_msg->set_message_id(ack_msg, message_id);
    ack_msg->add_notify(ack_msg, FALSE, FRAGMENT_ACK_NOTIFY, ack_data);
    
    // 发送
    packet_t *packet;
    if (this->ike_sa->generate_message(this->ike_sa, ack_msg, &packet) == SUCCESS)
    {
        charon->sender->send(charon->sender, packet);
    }
    
    ack_msg->destroy(ack_msg);
    chunk_free(&ack_data);
    free(received_frags);
}
```

#### 发送端处理确认
```c
static void process_fragment_ack(private_task_manager_t *this, 
                                message_t *message)
{
    notify_payload_t *notify;
    chunk_t ack_data;
    struct fragment_ack_data *ack;
    fragment_tracker_t *tracker;
    
    notify = message->get_notify(message, FRAGMENT_ACK_NOTIFY);
    if (!notify)
    {
        return;
    }
    
    ack_data = notify->get_notification_data(notify);
    ack = (struct fragment_ack_data*)ack_data.ptr;
    
    tracker = get_fragment_tracker(this, ntohs(ack->message_id));
    if (!tracker)
    {
        return;
    }
    
    // 更新分片确认状态
    update_fragment_ack_status(tracker, ack);
    
    DBG1(DBG_IKE, "received fragment ack: %d/%d fragments confirmed",
         ntohs(ack->received_count), ntohs(ack->total_fragments));
}
```

### 4. 性能优化效果

#### 传统重传 vs 选择性重传对比

| 场景 | 传统重传 | 选择性重传 | 节省带宽 |
|------|----------|------------|----------|
| 丢失1个分片/共7个 | 重传7个分片 | 重传1个分片 | 85.7% |
| 丢失2个分片/共7个 | 重传7个分片 | 重传2个分片 | 71.4% |
| 丢失3个分片/共7个 | 重传7个分片 | 重传3个分片 | 57.1% |

#### 从你的日志看
- 总分片数: 7
- 丢失分片数: 1 (只缺少#6)
- 传统重传: 7个分片 × 1236字节 = 8652字节
- 选择性重传: 1个分片 × 1236字节 = 1236字节
- **节省带宽: 85.7%**

### 5. 实现建议

#### 配置选项
```conf
charon {
    # 启用分片选择重传
    fragment_selective_retransmission = yes
    
    # 分片确认超时时间（毫秒）
    fragment_ack_timeout = 1000
    
    # 最大选择性重传次数
    fragment_max_selective_retransmits = 3
    
    # 分片确认间隔（毫秒）
    fragment_ack_interval = 500
}
```

#### 实现步骤
1. **第一阶段**: 实现分片状态跟踪
2. **第二阶段**: 实现分片确认协议
3. **第三阶段**: 实现选择性重传逻辑
4. **第四阶段**: 性能优化和测试

### 6. 向后兼容性

#### 协商机制
```c
// 在IKE_SA_INIT中协商选择性重传能力
#define SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED 16431

// 检查对端是否支持
if (message->get_notify(message, SELECTIVE_FRAGMENT_RETRANSMISSION_SUPPORTED))
{
    this->selective_retransmission_supported = TRUE;
}
```

#### 回退机制
```c
// 如果对端不支持选择性重传，回退到传统重传
if (!this->selective_retransmission_supported)
{
    return retransmit_all_fragments(this, message_id);
}
```

## 总结

当前的分片重传机制确实存在效率问题，重复传输大量已收到的数据。通过实现分片状态跟踪、确认机制和选择性重传，可以显著提高网络效率，特别是在高丢包率环境下。

从你的日志来看，这种改进可以节省约85%的重传带宽，大大提高连接建立的效率。 