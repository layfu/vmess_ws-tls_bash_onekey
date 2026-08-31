# V2Ray vmess+ws+tls 一键安装脚本

本项目源自 [wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey)，遵循原项目 MIT 协议，由衷感谢原作者的卓越贡献。

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
- VMess / AnyTLS 均支持路由规则（屏蔽国内/广告/BT/自定义域名/IP）
- 新增流量面板（单文件 Go 静态二进制），可视化每用户流量、在线状态、连接日志

### 管理脚本

```bash
./install.sh          # 进入管理菜单
./install.sh dat_update   # 更新 geoip.dat / geosite.dat
./install.sh singbox_update   # 升级 sing-box
./install.sh nginx_update   # 升级 Nginx（仅替换二进制，保留全部自定义配置）
```

> 升级 Nginx 时仅替换 `/etc/nginx/sbin/nginx` 一个文件，`nginx.conf`、`conf.d/*.conf`、`mime.types` 等所有配置均原样保留并自动备份；编译参数与原安装完全一致（PCRE2，无 `--with-pcre`）。

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

### 落地套 WARP

将节点的出站流量走 Cloudflare WARP，获得干净的 Cloudflare 出口 IP（仅支持 Debian/Ubuntu）。

1. 进入管理菜单 → `1 安装与升级` → `6 安装/卸载 WARP` → 安装并验证 `warp=on`
2. 配置出站模式（V2Ray 与 AnyTLS 各自独立）：
   - `V2Ray 配置` → `5 路由规则` → `6 WARP 出站模式`，在 `off`(直连) / `all`(全量走 WARP) / `user`(仅指定用户) 间切换
   - `AnyTLS 配置` → `3 路由规则` → `6 WARP 出站模式`，同上
3. `user` 模式下，用 `7 管理 WARP 用户` 添加需要走 WARP 的用户名（需与 VMess/AnyTLS 用户名一致）

> WARP 隧道为系统级，两协议共用；出站开关与用户列表各自独立。WARP 控制面显示 `Connected` 不代表转发正常，脚本通过 SOCKS 探活 `warp=on` 校验。可安装自愈守护（systemd timer 每 60s 检测，异常自动重启 `warp-svc`）。

### 流量面板

一个单文件 Go 静态二进制面板，复用现有 Nginx + Let's Encrypt 证书，在 `https://你的域名/panel/` 提供带 Basic Auth 的网页仪表盘：

- 每用户流量统计（上行/下行/总量 + 24h/3天/7天趋势）
- 在线状态与最近连接日志（客户端来源 IP → 访问目标域名/IP）
- VMess（v2fly）与 AnyTLS（sing-box）分别统计

**安装**：进入管理菜单 → `1 安装与升级` → `7 安装 流量面板`，按提示设置登录账号密码即可。访问 `https://你的域名/panel/`。

**说明**：

- 面板二进制从本仓库 Releases 下载（`panel-linux-<arch>`），通过 systemd 常驻，监听 `127.0.0.1:2052`，由 Nginx 反代并做 Basic Auth。
- 安装面板时会自动在 v2fly / sing-box 配置中注入统计接口（v2fly `api`+`stats`+`policy`；sing-box `experimental.v2ray_api`），并重启对应服务。
- VMess 每用户流量开箱即用；**AnyTLS 每用户流量与来源 IP 需要定制 sing-box**（官方二进制默认不含 v2ray_api，且 AnyTLS 连接日志不含来源地址）。安装面板时脚本会自动检测：若当前 sing-box 不含 v2ray_api，会提示下载 `sing-box-v2rayapi-linux-<arch>`（由 `.github/workflows/singbox-release.yml` 构建，已内置来源地址日志补丁）并替换（原二进制备份为 `sing-box.bak`）。使用官方 sing-box 时 AnyTLS 仅能查看连接目标（无来源 IP、无每用户流量）。
- VMess 来源 IP：由于 VMess 位于 Nginx 之后（Nginx 终结 TLS），v2ray 只能看到 `127.0.0.1`。面板通过 Nginx WebSocket 访问日志（`/var/log/nginx/ws-access.log`，安装面板时自动配置）与 v2ray 访问日志按时间戳关联，还原真实客户端 IP（Nginx 在连接关闭时才写日志，故来源 IP 会在连接结束后短暂延迟补全）。
- 修改面板密码：`其他` 菜单 → `5 修改 面板密码`；卸载面板：`其他` → `1 卸载`。
- 升级面板：`1 安装与升级` → `8 升级 流量面板`；更新定制 sing-box（含来源日志补丁）：`1 安装与升级` → `9 更新 sing-box (v2ray_api)`。

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
| `/etc/v2ray/warp_users` | VMess WARP 用户列表（user 模式） |
| `/etc/sing-box/config.json` | sing-box 服务端配置（AnyTLS） |
| `/etc/sing-box/users` | AnyTLS 用户列表 |
| `/etc/sing-box/routing.conf` | AnyTLS 路由规则开关 |
| `/etc/sing-box/block_domains` `/etc/sing-box/block_ips` | AnyTLS 自定义屏蔽域名/IP |
| `/etc/sing-box/warp_users` | AnyTLS WARP 用户列表（user 模式） |
| `/etc/sing-box/*.srs` | AnyTLS 路由规则集数据文件 |
| `/etc/panel/config.json` | 流量面板配置 |
| `/var/lib/panel/panel.db` | 流量面板历史数据库（SQLite） |
| `/etc/panel/panel.htpasswd` | 面板 Basic Auth 账号文件 |
| `/usr/local/bin/panel` | 流量面板二进制 |
| `/etc/nginx/` | Nginx 目录 |
| `/home/wwwroot/3DCEList` | Web 伪装站点 |
| `/data/v2ray.crt` `/data/v2ray.key` | SSL 证书 |
| `~/v2ray_info.inf` | V2Ray 客户端配置信息 |
| `~/anytls_info.inf` | AnyTLS 客户端配置信息 |

### 证书

脚本自动签发 Let's Encrypt 证书，有效期 3 个月。每周日凌晨 3 点 Nginx 自动重启配合续签。

自定义证书：将 crt 和 key 命名为 `v2ray.crt` `v2ray.key` 放入 `/data/` 目录即可。
