# 修改文件列表

## 必须复制的核心文件（2个）

### 1. `src/libcharon/encoding/payloads/notify_payload.h`
**修改内容**: 删除了旧的 `FRAGMENT_RETRANSMISSION_REQUEST` 通知类型

### 2. `src/libcharon/sa/ikev2/task_manager_v2.c`
**修改内容**: 
- 删除了旧的重传逻辑代码（约30行）
- 添加了前向函数声明
- 修正了 `array_destroy_function` 调用

## 可选文件（配置和文档）

### 3. `strongswan.conf.clean` - 清理后的配置示例
```conf
charon {
    max_packet = 65536
    
    # 新的选择性片段重传机制配置
    selective_fragment_retransmission = yes
    
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}

include strongswan.d/*.conf
```

### 4. `CONFIGURATION_MIGRATION.md` - 配置迁移指南
### 5. `CLEANUP_SUMMARY.md` - 清理工作总结
### 6. `verify_cleanup.sh` - 验证脚本

## 快速复制命令

```bash
# 方法1: 单独复制核心文件
scp src/libcharon/encoding/payloads/notify_payload.h user@remote:/path/to/strongswan/src/libcharon/encoding/payloads/
scp src/libcharon/sa/ikev2/task_manager_v2.c user@remote:/path/to/strongswan/src/libcharon/sa/ikev2/

# 方法2: 打包所有文件
tar -czf modified_files.tar.gz \
    src/libcharon/encoding/payloads/notify_payload.h \
    src/libcharon/sa/ikev2/task_manager_v2.c \
    strongswan.conf.clean \
    CONFIGURATION_MIGRATION.md \
    CLEANUP_SUMMARY.md \
    verify_cleanup.sh

# 然后传输压缩包
scp modified_files.tar.gz user@remote:/path/to/destination/
```

## 对端操作步骤

1. **备份原文件**:
   ```bash
   sudo cp /path/to/strongswan/src/libcharon/encoding/payloads/notify_payload.h notify_payload.h.backup
   sudo cp /path/to/strongswan/src/libcharon/sa/ikev2/task_manager_v2.c task_manager_v2.c.backup
   ```

2. **复制新文件**:
   ```bash
   # 如果使用单独文件
   sudo cp notify_payload.h /path/to/strongswan/src/libcharon/encoding/payloads/
   sudo cp task_manager_v2.c /path/to/strongswan/src/libcharon/sa/ikev2/
   
   # 如果使用压缩包
   tar -xzf modified_files.tar.gz
   sudo cp src/libcharon/encoding/payloads/notify_payload.h /path/to/strongswan/src/libcharon/encoding/payloads/
   sudo cp src/libcharon/sa/ikev2/task_manager_v2.c /path/to/strongswan/src/libcharon/sa/ikev2/
   ```

3. **编译**:
   ```bash
   cd /path/to/strongswan
   make -j4
   sudo make install
   ```

4. **更新配置**:
   ```bash
   # 删除旧配置
   sudo sed -i '/fragment_retransmission {/,/}/d' /etc/strongswan.conf
   
   # 添加新配置
   sudo echo "selective_fragment_retransmission = yes" >> /etc/strongswan.conf
   ```

5. **重启服务**:
   ```bash
   sudo systemctl restart strongswan
   ```

6. **验证**:
   ```bash
   sudo ipsec statusall
   ./verify_cleanup.sh  # 如果复制了验证脚本
   ```

## 文件说明

- **notify_payload.h**: 移除了 `FRAGMENT_RETRANSMISSION_REQUEST = 40970` 
- **task_manager_v2.c**: 主要修改包括：
  - 删除旧的 `fragment_retransmission.enabled` 配置逻辑
  - 添加函数前向声明解决编译错误
  - 修正 `array_destroy_function` 参数类型

## 编译验证

✅ 编译成功确认 - 所有修改都已通过编译测试 