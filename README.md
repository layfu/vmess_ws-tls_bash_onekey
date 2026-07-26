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
- 移除 bbr / mtproxy

### 管理脚本

```bash
./install.sh          # 进入管理菜单
./install.sh dat_update   # 更新 geoip.dat / geosite.dat
```

### 常用命令

```bash
systemctl start v2ray      # 启动 V2Ray
systemctl stop v2ray       # 停止 V2Ray
systemctl restart v2ray    # 重启 V2Ray
systemctl restart nginx    # 重启 Nginx
nginx -v                   # 查看 Nginx 版本
```

### 目录结构

| 路径 | 说明 |
|---|---|
| `/etc/v2ray/config.json` | V2Ray 服务端配置 |
| `/etc/nginx/` | Nginx 目录 |
| `/home/wwwroot/3DCEList` | Web 伪装站点 |
| `/data/v2ray.crt` `/data/v2ray.key` | SSL 证书 |
| `~/v2ray_info.inf` | 客户端配置信息 |

### 证书

脚本自动签发 Let's Encrypt 证书，有效期 3 个月。每周日凌晨 3 点 Nginx 自动重启配合续签。

自定义证书：将 crt 和 key 命名为 `v2ray.crt` `v2ray.key` 放入 `/data/` 目录即可。
