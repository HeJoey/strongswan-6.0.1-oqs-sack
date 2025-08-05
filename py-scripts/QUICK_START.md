# 快速使用指南

## 适用于已配置的strongSwan连接

如果您已经配置好了 `/etc/swanctl/swanctl.conf` 文件，请使用简化版连接管理器。

### 🚀 快速开始

1. **检查配置**
```bash
# 查看当前配置的连接
python3 simple_connector.py -a info -n host-host
python3 simple_connector.py -a info -n net-net
```

2. **启动连接**
```bash
# 启动主机到主机连接
sudo python3 simple_connector.py -a start -n host-host

# 启动网络到网络连接
sudo python3 simple_connector.py -a start -n net-net
```

3. **查看状态**
```bash
# 查看所有连接状态
python3 simple_connector.py -a status

# 监控特定连接
python3 simple_connector.py -a monitor -n host-host -d 60
```

4. **停止连接**
```bash
# 停止连接
sudo python3 simple_connector.py -a stop -n host-host
sudo python3 simple_connector.py -a stop -n net-net
```

### 🖥️ 交互模式

```bash
# 启动交互模式
python3 simple_connector.py
```

交互模式提供以下功能：
- 列出所有可用连接
- 显示连接详细信息
- 启动/停止/重启连接
- 实时监控连接状态
- 查看连接状态

### 📋 可用连接

根据您的配置文件，可用连接包括：

1. **host-host** (主机到主机)
   - 远程主机: 192.168.230.234
   - 类型: 主机到主机连接

2. **net-net** (网络到网络)
   - 远程主机: 192.168.31.138
   - 类型: 网络到网络连接

### ⚠️ 注意事项

1. **权限要求**: 启动和停止连接需要管理员权限
2. **配置文件**: 脚本会自动检查 `/etc/swanctl/swanctl.conf` 中的配置
3. **连接状态**: 使用 `swanctl --list-sas` 检查连接状态

### 🔧 故障排除

1. **权限错误**
```bash
sudo python3 simple_connector.py -a start -n host-host
```

2. **连接失败**
```bash
# 检查strongSwan服务状态
sudo systemctl status strongswan

# 查看详细日志
sudo swanctl --list-sas
```

3. **配置检查**
```bash
# 检查配置文件是否存在
ls -la /etc/swanctl/swanctl.conf

# 检查连接配置
python3 simple_connector.py -a info -n host-host
```

### 📝 示例用法

```bash
# 1. 检查连接信息
python3 simple_connector.py -a info -n host-host

# 2. 启动连接
sudo python3 simple_connector.py -a start -n host-host

# 3. 监控连接状态
python3 simple_connector.py -a monitor -n host-host -d 30

# 4. 停止连接
sudo python3 simple_connector.py -a stop -n host-host
```

### 🎯 常用命令

```bash
# 快速启动所有连接
sudo python3 simple_connector.py -a start -n host-host
sudo python3 simple_connector.py -a start -n net-net

# 快速停止所有连接
sudo python3 simple_connector.py -a stop -n host-host
sudo python3 simple_connector.py -a stop -n net-net

# 重启连接
sudo python3 simple_connector.py -a restart -n host-host

# 查看状态
python3 simple_connector.py -a status
``` 