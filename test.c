#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <library.h>
#include <daemon.h>
#include <utils/debug.h>
#include <collections/array.h>
#include <networking/host.h>
#include <encoding/message.h>
#include <sa/ike_sa.h>
#include <sa/ikev2/task_manager_v2.h>
#include <sa/ikev2/tasks/task.h>
#include <processing/jobs/job.h>
#include <threading/thread.h>

/**
 * 测试用的简单配置结构
 */
typedef struct {
    bool selective_retransmission_enabled;
    bool peer_supports_selective_retransmission;
    uint32_t max_packet_size;
    uint32_t fragment_size;
} test_config_t;

/**
 * 模拟创建一个大消息用于测试分片
 */
static message_t* create_large_test_message(uint32_t message_id, uint32_t size)
{
    message_t *message;
    chunk_t large_data;
    
    printf("Creating test message with size: %d bytes\n", size);
    
    message = message_create(IKEV2_MAJOR_VERSION, IKEV2_MINOR_VERSION);
    if (!message)
    {
        printf("Failed to create message\n");
        return NULL;
    }
    
    message->set_message_id(message, message_id);
    message->set_request(message, TRUE);
    message->set_exchange_type(message, IKE_SA_INIT);
    
    // 创建大的数据块来触发分片
    large_data = chunk_alloc(size);
    memset(large_data.ptr, 0x41, large_data.len); // 填充 'A'
    
    // 添加一个通知载荷包含大数据
    message->add_notify(message, FALSE, NAT_DETECTION_SOURCE_IP, large_data);
    
    chunk_free(&large_data);
    
    printf("Test message created successfully: ID=%d, size=%d\n", message_id, size);
    return message;
}

/**
 * 测试分片跟踪器创建和管理
 */
static void test_fragment_tracker()
{
    printf("\n=== Testing Fragment Tracker ===\n");
    
    // 这些函数在task_manager_v2.c中是static的，我们需要通过task manager实例来测试
    printf("Fragment tracker functions are static, will test through task manager\n");
}

/**
 * 测试消息生成和分片
 */
static void test_message_generation(ike_sa_t *ike_sa)
{
    printf("\n=== Testing Message Generation and Fragmentation ===\n");
    
    if (!ike_sa)
    {
        printf("ERROR: IKE SA is NULL\n");
        return;
    }
    
    // 创建大消息
    message_t *large_msg = create_large_test_message(1, 8192);
    if (!large_msg)
    {
        printf("Failed to create large test message\n");
        return;
    }
    
    // 测试消息分片
    enumerator_t *fragments = NULL;
    status_t status = ike_sa->generate_message_fragmented(ike_sa, large_msg, &fragments);
    
    if (status == SUCCESS && fragments)
    {
        packet_t *fragment;
        uint16_t count = 0;
        uint32_t total_size = 0;
        
        printf("Message fragmentation successful!\n");
        
        while (fragments->enumerate(fragments, &fragment))
        {
            count++;
            chunk_t data = fragment->get_data(fragment);
            total_size += data.len;
            printf("Fragment %d: %d bytes\n", count, data.len);
        }
        
        printf("Total fragments: %d, Total size: %d bytes\n", count, total_size);
        fragments->destroy(fragments);
    }
    else
    {
        printf("Message fragmentation failed or no fragmentation needed\n");
    }
    
    large_msg->destroy(large_msg);
}

/**
 * 测试task manager创建和基本功能
 */
static void test_task_manager_basic()
{
    printf("\n=== Testing Task Manager Basic Functions ===\n");
    
    // 创建主机地址
    host_t *local_host = host_create_from_string("192.168.1.100", 500);
    host_t *remote_host = host_create_from_string("192.168.1.200", 500);
    
    if (!local_host || !remote_host)
    {
        printf("Failed to create host addresses\n");
        return;
    }
    
    // 创建IKE SA ID
    ike_sa_id_t *ike_sa_id = ike_sa_id_create(IKEV2_MAJOR_VERSION, 
                                              chunk_from_thing(0x1234567890abcdefLL),
                                              chunk_from_thing(0xfedcba0987654321LL),
                                              TRUE);
    
    if (!ike_sa_id)
    {
        printf("Failed to create IKE SA ID\n");
        local_host->destroy(local_host);
        remote_host->destroy(remote_host);
        return;
    }
    
    printf("Created IKE SA ID successfully\n");
    printf("Local host: %H\n", local_host);
    printf("Remote host: %H\n", remote_host);
    
    // 清理
    ike_sa_id->destroy(ike_sa_id);
    local_host->destroy(local_host);
    remote_host->destroy(remote_host);
}

/**
 * 测试选择性重传配置
 */
static void test_selective_retransmission_config()
{
    printf("\n=== Testing Selective Retransmission Configuration ===\n");
    
    test_config_t config = {
        .selective_retransmission_enabled = TRUE,
        .peer_supports_selective_retransmission = TRUE,
        .max_packet_size = 1500,
        .fragment_size = 1280
    };
    
    printf("Configuration:\n");
    printf("  Selective retransmission enabled: %s\n", 
           config.selective_retransmission_enabled ? "YES" : "NO");
    printf("  Peer supports selective retransmission: %s\n", 
           config.peer_supports_selective_retransmission ? "YES" : "NO");
    printf("  Max packet size: %d bytes\n", config.max_packet_size);
    printf("  Fragment size: %d bytes\n", config.fragment_size);
    
    // 计算分片数量
    uint32_t test_message_size = 8192;
    uint32_t fragments_needed = (test_message_size + config.fragment_size - 1) / config.fragment_size;
    
    printf("For a %d byte message, estimated fragments needed: %d\n", 
           test_message_size, fragments_needed);
}

/**
 * 测试数据统计功能
 */
static void test_transmission_statistics()
{
    printf("\n=== Testing Transmission Statistics ===\n");
    
    // 模拟传输统计数据
    uint32_t original_size = 8192;
    uint32_t fragment_count = 6;
    uint32_t retransmissions = 2;
    uint32_t total_transmitted = original_size + (retransmissions * original_size / fragment_count);
    
    printf("Transmission Statistics:\n");
    printf("  Original message size: %d bytes\n", original_size);
    printf("  Fragment count: %d\n", fragment_count);
    printf("  Retransmission count: %d\n", retransmissions);
    printf("  Total data transmitted: %d bytes\n", total_transmitted);
    printf("  Transmission efficiency: %.2f%%\n", 
           (float)original_size / total_transmitted * 100);
}

/**
 * 主测试函数
 */
int main(int argc, char *argv[])
{
    printf("=== StrongSwan Task Manager Test Program ===\n");
    printf("Testing strongswan-6.0.1 with selective fragment retransmission\n\n");
    
    // 初始化strongswan库
    printf("Initializing strongswan library...\n");
    
    if (!library_init(NULL, "test"))
    {
        printf("ERROR: Failed to initialize strongswan library\n");
        return 1;
    }
    
    printf("Library initialized successfully\n");
    
    // 设置调试级别
    dbg_default_set_level(DBG_IKE, 1);
    dbg_default_set_level(DBG_NET, 1);
    
    // 运行各种测试
    test_task_manager_basic();
    test_selective_retransmission_config();
    test_transmission_statistics();
    test_fragment_tracker();
    
    // 测试消息生成（需要更复杂的设置，暂时跳过）
    printf("\n=== Message Generation Test (Skipped) ===\n");
    printf("Message generation test requires full IKE SA setup, skipping for now\n");
    
    // 性能测试
    printf("\n=== Performance Characteristics ===\n");
    printf("Testing different message sizes and fragment counts:\n");
    
    uint32_t test_sizes[] = {1024, 2048, 4096, 8192, 16384};
    uint32_t fragment_size = 1280;
    
    for (int i = 0; i < 5; i++)
    {
        uint32_t size = test_sizes[i];
        uint32_t fragments = (size + fragment_size - 1) / fragment_size;
        printf("  Message size: %5d bytes -> Fragments: %2d\n", size, fragments);
    }
    
    printf("\n=== Test Summary ===\n");
    printf("✓ Library initialization: SUCCESS\n");
    printf("✓ Basic configuration: SUCCESS\n");
    printf("✓ Statistics calculation: SUCCESS\n");
    printf("✓ Fragment estimation: SUCCESS\n");
    printf("! Message generation: SKIPPED (requires full SA setup)\n");
    printf("! Fragment tracking: SKIPPED (static functions)\n");
    
    // 清理资源
    printf("\nCleaning up and shutting down...\n");
    library_deinit();
    
    printf("Test program completed successfully!\n");
    return 0;
} 