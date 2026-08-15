# V2Ray vmess+ws+tls 一键安装脚本

fork 自 [wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey)，适配新版系统并持续维护。

### 系统要求

Debian 11+ / Ubuntu 20.04+ / CentOS 7+

### 一键安装

```bash
wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/master/install.sh" && chmod +x install.sh && bash install.sh
```

### 主要变更

- Nginx 1.30.4 源码编译（OpenSSL 3.5.7 / jemalloc 5.3.1 / PCRE2）
- alterId 默认 0（VMess MD5 已废弃）
- 最低系统要求提高至 Debian 11 / Ubuntu 20.04
- SSL cipher 适配 OpenSSL 3.x
- 支持更新 geoip.dat / geosite.dat
- 移除 bbr / mtproxy / http/2 安装模式
- 新增 AnyTLS 协议（基于 sing-box），复用 Let's Encrypt 证书，不自签证书
- VMess / AnyTLS 均支持多用户管理
- VMess 支持路由规则（屏蔽国内/广告/BT/自定义域名/IP）

### 管理脚本

```bash
./install.sh          # 进入管理菜单
./install.sh dat_update   # 更新 geoip.dat / geosite.dat
./install.sh singbox_update   # 升级 sing-box
```

### AnyTLS 安装

进入管理菜单后选择 `1 安装与升级` → `3 安装 AnyTLS`（基于 [sing-box](https://sing-box.sagernet.org/)）：

- 独立监听端口（默认 8443，与 Nginx 的 443 互不冲突）
- 复用 `/data/v2ray.crt` `/data/v2ray.key` 证书（**不自签证书**）
- 证书续签后 sing-box 会自动热加载，无需额外操作
- 支持多用户：`3 AnyTLS 配置` → `1 管理 AnyTLS 用户`（查看/添加/删除/改密码）
- 安装信息保存在 `~/anytls_info.inf`，包含 Surge 配置行与 `anytls://` URI

Surge 配置示例（iOS 5.17.0+ / Mac 6.4.3+）：

```ini
[Proxy]
AnyTLS = anytls, your.domain.com, 8443, password=xxxxxxxxxxxxxxxx, sni=your.domain.com, reuse=true
```

### 常用命令

```bash
systemctl start v2ray      # 启动 V2Ray
systemctl stop v2ray       # 停止 V2Ray
systemctl restart v2ray    # 重启 V2Ray
systemctl restart nginx    # 重启 Nginx
nginx -v                   # 查看 Nginx 版本
systemctl restart sing-box # 重启 sing-box (AnyTLS)
```

### 目录结构

| 路径 | 说明 |
|---|---|
| `/etc/v2ray/config.json` | V2Ray 服务端配置 |
| `/etc/v2ray/users` | VMess 用户列表 |
| `/etc/v2ray/routing.conf` | 路由规则开关 |
| `/etc/v2ray/block_domains` `/etc/v2ray/block_ips` | 自定义屏蔽域名/IP |
| `/etc/sing-box/config.json` | sing-box 服务端配置（AnyTLS） |
| `/etc/sing-box/users` | AnyTLS 用户列表 |
| `/etc/nginx/` | Nginx 目录 |
| `/home/wwwroot/3DCEList` | Web 伪装站点 |
| `/data/v2ray.crt` `/data/v2ray.key` | SSL 证书 |
| `~/v2ray_info.inf` | V2Ray 客户端配置信息 |
| `~/anytls_info.inf` | AnyTLS 客户端配置信息 |

### 证书

脚本自动签发 Let's Encrypt 证书，有效期 3 个月。每周日凌晨 3 点 Nginx 自动重启配合续签。

自定义证书：将 crt 和 key 命名为 `v2ray.crt` `v2ray.key` 放入 `/data/` 目录即可。
