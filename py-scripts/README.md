# strongSwan 连接管理器

这是一个简易的strongSwan VPN连接管理脚本，支持基本的VPN连接管理功能。

## 版本说明

- **`strongswan_connector.py`**: 完整版连接管理器，支持配置生成和管理
- **`simple_connector.py`**: 简化版连接管理器，专门用于控制已配置的swanctl连接

## 功能特性

- 🔧 **连接管理**: 启动、停止、重启VPN连接
- 📊 **状态监控**: 实时监控连接状态
- ⚙️ **配置管理**: JSON格式的配置文件管理
- 🖥️ **交互模式**: 友好的命令行交互界面
- 🔍 **状态检查**: 检查strongSwan安装和连接状态

## 系统要求

- Python 3.6+
- strongSwan 已正确安装
- 管理员权限（用于配置ipsec）

## 安装和使用

### 1. 确保strongSwan已安装

```bash
# 检查strongSwan是否安装
which ipsec

# 如果没有安装，请先安装strongSwan
sudo apt-get install strongswan  # Ubuntu/Debian
# 或
sudo yum install strongswan      # CentOS/RHEL
```

### 2. 配置VPN连接

编辑 `vpn_config.json` 文件，添加您的VPN连接配置：

```json
{
  "connections": {
    "my_vpn": {
      "remote_host": "vpn.example.com",
      "identity": "user@example.com",
      "psk": "your_pre_shared_key",
      "left": "%defaultroute",
      "leftsubnet": "0.0.0.0/0",
      "right": "%any",
      "rightsubnet": "0.0.0.0/0",
      "auto": "add"
    }
  }
}
```

### 3. 运行脚本

#### 简化版（推荐，用于已配置的连接）
```bash
# 交互模式
python3 simple_connector.py

# 命令行模式
python3 simple_connector.py -a start -n host-host
python3 simple_connector.py -a stop -n host-host
python3 simple_connector.py -a restart -n net-net
python3 simple_connector.py -a status
python3 simple_connector.py -a monitor -n host-host -d 120
python3 simple_connector.py -a info -n host-host
```

#### 完整版（用于配置生成和管理）
```bash
# 交互模式
python3 strongswan_connector.py

# 命令行模式
python3 strongswan_connector.py -a start -n my_vpn
python3 strongswan_connector.py -a stop -n my_vpn
python3 strongswan_connector.py -a restart -n my_vpn
python3 strongswan_connector.py -a status
python3 strongswan_connector.py -a monitor -n my_vpn -d 120
```

## 配置参数说明

### 连接配置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `remote_host` | VPN服务器地址 | `vpn.example.com` |
| `identity` | 客户端身份标识 | `client@example.com` |
| `psk` | 预共享密钥 | `your_pre_shared_key` |
| `left` | 本地端点 | `%defaultroute` |
| `leftsubnet` | 本地子网 | `0.0.0.0/0` |
| `right` | 远程端点 | `%any` |
| `rightsubnet` | 远程子网 | `0.0.0.0/0` |
| `auto` | 自动启动模式 | `add` |

### 设置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `charon_log_level` | 日志级别 | `-1` |
| `check_interval` | 状态检查间隔(秒) | `5` |

## 使用示例

### 1. 基本使用

```bash
# 进入交互模式
python3 strongswan_connector.py

# 选择操作：
# 1. 列出连接
# 2. 启动连接
# 3. 停止连接
# 4. 重启连接
# 5. 查看状态
# 6. 监控连接
# 7. 编辑配置
# 8. 退出
```

### 2. 快速启动VPN

```bash
# 启动名为 "office_vpn" 的连接
python3 strongswan_connector.py -a start -n office_vpn
```

### 3. 监控连接状态

```bash
# 监控连接60秒
python3 strongswan_connector.py -a monitor -n office_vpn -d 60
```

## 故障排除

### 1. 权限问题

如果遇到权限错误，请确保以管理员权限运行：

```bash
sudo python3 strongswan_connector.py
```

### 2. strongSwan未安装

确保strongSwan已正确安装：

```bash
# 检查安装
which ipsec

# 检查服务状态
sudo systemctl status strongswan
```

### 3. 连接失败

- 检查配置文件中的参数是否正确
- 确认VPN服务器地址和预共享密钥
- 查看strongSwan日志：`sudo ipsec status`

### 4. 配置文件错误

如果配置文件格式错误，脚本会自动使用默认配置。您可以手动编辑配置文件：

```bash
nano vpn_config.json
```

## 安全注意事项

1. **保护配置文件**: 确保配置文件中的预共享密钥安全
2. **权限管理**: 只允许授权用户访问VPN配置
3. **日志管理**: 定期清理strongSwan日志文件
4. **网络监控**: 监控VPN连接的网络流量

## 脚本结构

```
py-scripts/
├── strongswan_connector.py  # 主脚本
├── vpn_config.json          # 配置文件
└── README.md               # 说明文档
```

## 开发说明

- 脚本使用Python 3.6+的语法特性
- 依赖标准库：`subprocess`, `json`, `time`, `sys`, `os`, `argparse`
- 支持JSON格式的配置文件
- 提供完整的错误处理和日志输出

## 许可证

本脚本遵循MIT许可证，可自由使用和修改。 