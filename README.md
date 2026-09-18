# VMess + AnyTLS (sing-box) 一键安装脚本

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
- 移除 bbr / mtproxy / http/2 安装模式
- **VMess (ws+tls) 与 AnyTLS 均基于 sing-box**：Nginx 终止 TLS 并把 WS 反代到 sing-box 的 `vmess-in`；两协议共用同一个 sing-box 实例、同一套路由与统计
- VMess / AnyTLS 均支持多用户管理
- VMess / AnyTLS 共用路由规则（屏蔽国内/广告/BT/自定义域名/IP）
- 新增流量面板（单文件 Go 静态二进制），可视化每用户流量、在线状态、连接日志与路由拓扑

### 管理脚本

```bash
./install.sh                  # 进入管理菜单
./install.sh singbox_update   # 升级 sing-box
./install.sh nginx_update     # 升级 Nginx（仅替换二进制，保留全部自定义配置）
```

> 升级 Nginx 时仅替换 `/etc/nginx/sbin/nginx` 一个文件，`nginx.conf`、`conf.d/*.conf`、`mime.types` 等所有配置均原样保留并自动备份；编译参数与原安装完全一致（PCRE2，无 `--with-pcre`）。

### 安装

进入管理菜单后：

- `1 安装与升级` → `1 安装 VMess (Nginx+ws+tls)`（基于 [sing-box](https://sing-box.sagernet.org/)）
- `1 安装与升级` → `2 安装 AnyTLS`（基于 sing-box，独立监听端口，默认 8443，与 Nginx 的 443 互不冲突）

两者都复用 `/data/v2ray.crt` `/data/v2ray.key` 证书（**不自签证书**），证书续签后 sing-box 自动热加载。

VMess 安装信息保存在 `~/v2ray_info.inf`，AnyTLS 保存在 `~/anytls_info.inf`（含 Surge 配置行与 `anytls://` URI）。

Surge 配置示例（iOS 5.17.0+ / Mac 6.4.3+）：

```ini
[Proxy]
AnyTLS = anytls, your.domain.com, 8443, password=xxxxxxxxxxxxxxxx, sni=your.domain.com, reuse=true
```

### 落地套 WARP

将节点的出站流量走 Cloudflare WARP，获得干净的 Cloudflare 出口 IP（仅支持 Debian/Ubuntu）。

1. 进入管理菜单 → `1 安装与升级` → `5 安装/卸载 WARP` → 安装并验证 `warp=on`
2. 配置出站模式（VMess/AnyTLS 共用）：`VMess 配置`（或 `AnyTLS 配置`）→ `路由规则` → `WARP 出站模式`，在 `off`(直连) / `all`(全量走 WARP) / `user`(仅指定用户) 间切换
3. `user` 模式下，用 `管理 WARP 用户` 添加需要走 WARP 的用户名（需与 VMess/AnyTLS 用户名一致）

> WARP 隧道为系统级，VMess/AnyTLS 共用同一个 sing-box 实例与同一套路由。WARP 控制面显示 `Connected` 不代表转发正常，脚本通过 SOCKS 探活 `warp=on` 校验。可安装自愈守护（systemd timer 每 60s 检测，异常自动重启 `warp-svc`）。

### 流量面板

一个单文件 Go 静态二进制面板，复用现有 Nginx + Let's Encrypt 证书，在 `https://你的域名/panel/` 提供带 Basic Auth 的网页仪表盘：

- 每用户流量统计（上行/下行/总量 + 24h/3天/7天趋势）
- 在线状态与最近连接日志（客户端来源 IP → 访问目标域名/IP）
- 路由拓扑：用户 → 协议 → 服务器 → 出口 → 目标，按精确字节绘制，悬停任意节点查看该切片流量

**安装**：进入管理菜单 → `1 安装与升级` → `6 安装 流量面板`，按提示设置登录账号密码即可。访问 `https://你的域名/panel/`。

**说明**：

- 面板二进制从本仓库 Releases 下载（`panel-linux-<arch>`），通过 systemd 常驻，监听 `127.0.0.1:2052`，由 Nginx 反代并做 Basic Auth。
- 安装面板时会自动在 sing-box 配置中注入统计接口（`experimental.v2ray_api` + `experimental.clash_api`），并重启服务。
- 每用户、每协议、每出口、每目标的精确流量依赖**定制 sing-box**（官方二进制默认不含 v2ray_api，且缺少用户/已关闭连接补丁）。脚本会自动检测：若当前 sing-box 不含 v2ray_api，会提示下载 `sing-box-v2rayapi-linux-<arch>`（由 `.github/workflows/build-release.yml` 构建，已内置来源地址日志、Clash 用户、已关闭连接、`user_outbound` 计数器等补丁）并替换（原二进制备份为 `sing-box.bak`）。
- VMess 来源 IP：由于 VMess 位于 Nginx 之后（Nginx 终结 TLS），sing-box 只能看到 `127.0.0.1`。面板通过 Nginx WebSocket 访问日志（`/var/log/nginx/ws-access.log`，安装面板时自动配置）与 sing-box 日志按时间戳关联，还原真实客户端 IP（Nginx 在连接关闭时才写日志，故来源 IP 会在连接结束后短暂延迟补全）。
- 修改面板密码：`其他` 菜单 → `4 修改 面板密码`；卸载面板：`其他` → `1 卸载`。
- 升级面板：`1 安装与升级` → `7 升级 流量面板`；更新定制 sing-box：`1 安装与升级` → `8 更新 sing-box (v2ray_api)`。

### 常用命令

```bash
systemctl restart nginx    # 重启 Nginx
nginx -v                   # 查看 Nginx 版本
systemctl restart sing-box # 重启 sing-box (VMess/AnyTLS)
```

### 目录结构

| 路径 | 说明 |
|---|---|
| `/etc/v2ray/users` | VMess 用户列表 |
| `/usr/local/vmess_qr.json` | VMess 客户端配置（生成导入链接用） |
| `/etc/sing-box/config.json` | sing-box 服务端配置（VMess + AnyTLS） |
| `/etc/sing-box/users` | AnyTLS 用户列表 |
| `/etc/sing-box/routing.conf` | 路由规则开关 |
| `/etc/sing-box/block_domains` `/etc/sing-box/block_ips` | 自定义屏蔽域名/IP |
| `/etc/sing-box/warp_users` | WARP 用户列表（user 模式） |
| `/etc/sing-box/*.srs` | 路由规则集数据文件 |
| `/etc/panel/config.json` | 流量面板配置 |
| `/var/lib/panel/panel.db` | 流量面板历史数据库（SQLite） |
| `/etc/panel/panel.htpasswd` | 面板 Basic Auth 账号文件 |
| `/usr/local/bin/panel` | 流量面板二进制 |
| `/etc/nginx/` | Nginx 目录 |
| `/home/wwwroot/3DCEList` | Web 伪装站点 |
| `/data/v2ray.crt` `/data/v2ray.key` | SSL 证书 |
| `~/v2ray_info.inf` | VMess 客户端配置信息 |
| `~/anytls_info.inf` | AnyTLS 客户端配置信息 |

### 证书

脚本自动签发 Let's Encrypt 证书，有效期 3 个月。每周日凌晨 3 点 Nginx 自动重启配合续签。

自定义证书：将 crt 和 key 命名为 `v2ray.crt` `v2ray.key` 放入 `/data/` 目录即可。
