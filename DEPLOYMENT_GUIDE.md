# strongSwan 分片选择重传机制部署指南

## 概述

本指南详细说明如何部署和使用strongSwan的分片选择重传机制，实现丢片的选择性重传而不是全部重传。

## 部署步骤

### 1. 编译和安装

#### 在两端机器上执行：

```bash
# 1. 进入strongSwan源码目录
cd /home/moon/Downloads/strongswan-6.0.1-oqs

# 2. 配置编译选项
./configure --prefix=/usr --sysconfdir=/etc --enable-unity --enable-eap-identity \
    --enable-eap-md5 --enable-eap-mschapv2 --enable-eap-tls --enable-eap-ttls \
    --enable-eap-peap --enable-eap-tnc --enable-eap-dynamic --enable-eap-radius \
    --enable-xauth-eap --enable-xauth-pam --enable-dhcp --enable-openssl \
    --enable-addrblock --enable-unity --enable-certexpire --enable-radattr \
    --enable-swanctl --enable-openssl --disable-gmp --enable-fragmentation

# 3. 编译
make -j4

# 4. 安装
sudo make install
```

### 2. 配置文件设置

#### 在两端机器的 `/etc/strongswan.conf` 中添加：

```conf
# 分片选择重传机制配置
charon {
    # 分片重组超时时间（秒）
    fragment_timeout = 30
    
    # 启用选择性重传
    selective_retransmission = yes
    
    # 最大重传尝试次数
    max_retransmission_attempts = 3
    
    # 重传请求间隔（秒）
    retransmission_interval = 5
    
    # 启用分片进度日志（调试时使用）
    fragment_progress_logging = yes
    
    # IKE_INTERMEDIATE响应缓存超时（秒）
    intermediate_cache_timeout = 300
    
    # 启用IKE_INTERMEDIATE选择性重传
    intermediate_selective_retransmission = yes
    
    # 启用分片功能
    fragmentation = yes
}

# 连接配置示例
conn %default {
    keyexchange = ikev2
    ike = aes256-sha256-modp2048!
    esp = aes256-sha256!
    keyingtries = 3
    
    # 启用分片
    fragmentation = yes
    
    # 启用IKE_INTERMEDIATE
    proposals = aes256-sha256-modp2048 aes256-sha256-modp3072 aes256-sha256-modp4096
}

conn site-to-site {
    left = 192.168.1.100
    leftid = left.example.com
    leftsubnet = 192.168.1.0/24
    
    right = 192.168.1.200
    rightid = right.example.com
    rightsubnet = 192.168.2.0/24
    
    auto = start
}
```

### 3. 启动服务

#### 在两端机器上执行：

```bash
# 重启strongSwan服务
sudo systemctl restart strongswan

# 检查服务状态
sudo systemctl status strongswan

# 查看日志确认分片功能已启用
sudo tail -f /var/log/strongswan.log
```

## 工作机制说明

### 1. 正常情况下的分片处理

```
发送端 → 分片消息 → 网络传输 → 接收端
                                    ↓
                              分片重组
                                    ↓
                              检查缺失分片
                                    ↓
                              选择性重传请求
```

### 2. 丢片情况下的选择性重传

```
接收端检测到分片丢失
        ↓
    生成缺失分片列表
        ↓
    发送选择性重传请求
        ↓
    发送端只重传缺失的分片
        ↓
    接收端完成分片重组
```

### 3. IKE_INTERMEDIATE响应缓存

```
IKE_INTERMEDIATE响应
        ↓
    缓存响应内容
        ↓
    收到重传请求时
        ↓
    直接返回缓存的响应
```

## 验证部署

### 1. 检查功能是否启用

```bash
# 查看strongSwan版本和功能
sudo ipsec version

# 查看详细配置
sudo ipsec statusall

# 查看日志中的分片相关信息
sudo grep -i fragment /var/log/strongswan.log
```

### 2. 测试连接建立

```bash
# 启动连接
sudo ipsec up site-to-site

# 查看连接状态
sudo ipsec status

# 查看详细日志
sudo tail -f /var/log/strongswan.log
```

### 3. 模拟分片丢失测试

```bash
# 使用网络工具模拟丢包
sudo tc qdisc add dev eth0 root netem loss 10%

# 建立连接，观察选择性重传
sudo ipsec up site-to-site

# 查看日志中的选择性重传信息
sudo grep -i "selective\|retransmission\|fragment" /var/log/strongswan.log
```

## 性能优势

### 1. 网络效率提升

- **传统方式**：丢失1个分片 → 重传所有分片
- **选择性重传**：丢失1个分片 → 只重传1个分片

### 2. 连接成功率提高

- **超时机制**：防止无限等待
- **智能重传**：准确识别缺失分片
- **缓存机制**：快速响应重传请求

### 3. 资源使用优化

- **内存效率**：位图跟踪比数组更节省内存
- **CPU效率**：O(1)时间复杂度的分片状态查询
- **网络效率**：减少不必要的重传

## 监控和调试

### 1. 日志监控

```bash
# 实时监控分片相关日志
sudo tail -f /var/log/strongswan.log | grep -E "(fragment|retransmission|selective)"

# 查看分片重组进度
sudo grep "fragment.*progress" /var/log/strongswan.log

# 查看选择性重传请求
sudo grep "selective.*retransmission" /var/log/strongswan.log
```

### 2. 性能监控

```bash
# 监控网络连接状态
sudo ipsec statusall

# 查看连接统计信息
sudo ipsec stats

# 监控系统资源使用
top -p $(pgrep charon)
```

### 3. 故障排除

```bash
# 检查配置文件语法
sudo ipsec verify

# 查看详细调试信息
sudo ipsec stroke loglevel ike 2

# 重置连接进行测试
sudo ipsec down site-to-site
sudo ipsec up site-to-site
```

## 配置调优建议

### 1. 超时设置

```conf
# 根据网络环境调整超时时间
charon.fragment_timeout = 30        # 网络较差时可增加
charon.intermediate_cache_timeout = 300  # 根据内存情况调整
```

### 2. 重传策略

```conf
# 根据网络质量调整重传参数
charon.max_retransmission_attempts = 3   # 网络较差时可增加
charon.retransmission_interval = 5       # 网络延迟高时可增加
```

### 3. 日志级别

```conf
# 生产环境建议关闭详细日志
charon.fragment_progress_logging = no
```

## 总结

通过部署这套分片选择重传机制，您将获得：

1. **高效的重传机制** - 只重传丢失的分片，而不是全部重传
2. **提高的连接成功率** - 智能超时和重传策略
3. **优化的资源使用** - 更少的内存和网络开销
4. **更好的用户体验** - 更快的连接建立和更稳定的连接

部署完成后，两端机器将自动使用选择性重传机制，无需额外的配置或操作。系统会自动检测分片丢失，发送选择性重传请求，并只重传必要的分片。 