# StrongSwan 配置迁移指南

## 片段重传机制配置更新

### 概述

在实现完整的选择性片段重传机制后，旧的不完善的 `fragment_retransmission` 配置已被移除，替换为新的 `selective_fragment_retransmission` 配置。

### 旧配置（已删除）

```conf
charon {
    max_packet = 65536
    fragment_retransmission {
        enabled = yes
        timeout = 5
        max_retries = 3
    }
    
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}
```

### 新配置（推荐）

```conf
charon {
    max_packet = 65536
    
    # 启用选择性片段重传机制
    selective_fragment_retransmission = yes
    
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}
```

### 配置变更说明

1. **移除的配置项**：
   - `fragment_retransmission.enabled`
   - `fragment_retransmission.timeout`
   - `fragment_retransmission.max_retries`

2. **新增的配置项**：
   - `selective_fragment_retransmission` - 启用/禁用选择性片段重传

3. **为什么简化配置**：
   - 新机制使用更智能的自适应算法
   - 超时和重试参数由系统自动管理
   - 减少配置复杂性，提高易用性

### 功能改进

#### 旧机制的问题
- 发送方重传所有片段，即使只缺少一个
- 造成严重的带宽浪费（例如：7个片段中缺少1个，却重传全部7个）
- 效率低下，特别是在后量子密码学场景中

#### 新机制的优势
- **选择性重传**：只重传实际缺失的片段
- **带宽效率**：显著减少网络流量（节省高达85.7%的带宽）
- **智能确认**：实时片段确认机制
- **自适应**：根据网络条件自动调整
- **向后兼容**：自动检测对等方支持情况

### 迁移步骤

1. **备份当前配置**：
   ```bash
   sudo cp /etc/strongswan.conf /etc/strongswan.conf.backup
   ```

2. **更新配置文件**：
   ```bash
   sudo nano /etc/strongswan.conf
   ```

3. **移除旧配置**：
   删除 `fragment_retransmission` 整个配置块

4. **添加新配置**：
   ```conf
   selective_fragment_retransmission = yes
   ```

5. **重启服务**：
   ```bash
   sudo systemctl restart strongswan
   ```

6. **验证配置**：
   ```bash
   sudo ipsec statusall
   ```

### 测试新配置

使用提供的测试脚本验证新机制：

```bash
# 基本测试
sudo ./test_selective_fragment_retransmission.sh

# 高丢包率测试
sudo ./test_severe_packet_loss.sh
```

### 故障排除

如果遇到问题：

1. **检查日志**：
   ```bash
   sudo journalctl -u strongswan -f
   ```

2. **验证配置语法**：
   ```bash
   sudo ipsec start --nofork
   ```

3. **临时禁用新机制**：
   ```conf
   selective_fragment_retransmission = no
   ```

### 性能预期

在高丢包率环境中，新机制的性能改进：

- **1个片段缺失**：节省 85.7% 带宽
- **2个片段缺失**：节省 71.4% 带宽  
- **3个片段缺失**：节省 57.1% 带宽

### 注意事项

1. 新机制需要双方都支持才能生效
2. 如果对等方不支持，会自动回退到传统重传
3. 配置更改后需要重新建立连接才能生效
4. 建议在生产环境部署前进行充分测试 