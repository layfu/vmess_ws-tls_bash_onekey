#!/bin/bash

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

#fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
GreenBG="\033[48;5;28m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="1.6.9.34"
shell_mode="None"
github_branch="master"
version_cmp="/tmp/version_cmp.tmp"
v2ray_conf_dir="/etc/v2ray"
nginx_conf_dir="/etc/nginx/conf/conf.d"
v2ray_conf="${v2ray_conf_dir}/config.json"
nginx_conf="${nginx_conf_dir}/v2ray.conf"
nginx_dir="/etc/nginx"
web_dir="/home/wwwroot"
nginx_openssl_src="/usr/local/src"
v2ray_bin_dir_old="/usr/bin/v2ray"
v2ray_bin_dir="/usr/local/bin/v2ray"
v2ctl_bin_dir="/usr/local/bin/v2ctl"
v2ray_info_file="$HOME/v2ray_info.inf"
v2ray_qr_config_file="/usr/local/vmess_qr.json"
vmess_users_file="/etc/v2ray/users"
routing_conf_file="/etc/v2ray/routing.conf"
block_domains_file="/etc/v2ray/block_domains"
block_ips_file="/etc/v2ray/block_ips"
warp_socks_port="40000"
warp_users_file="/etc/v2ray/warp_users"
anytls_warp_users_file="/etc/sing-box/warp_users"
warp_healthcheck_file="/usr/local/bin/warp-healthcheck.sh"
warp_systemd_service="/etc/systemd/system/warp-healthcheck.service"
warp_systemd_timer="/etc/systemd/system/warp-healthcheck.timer"
nginx_systemd_file="/etc/systemd/system/nginx.service"
v2ray_systemd_file="/etc/systemd/system/v2ray.service"
v2ray_access_log="/var/log/v2ray/access.log"
v2ray_error_log="/var/log/v2ray/error.log"
singbox_bin_dir="/usr/local/bin/sing-box"
singbox_conf_dir="/etc/sing-box"
singbox_conf="${singbox_conf_dir}/config.json"
singbox_systemd_file="/etc/systemd/system/sing-box.service"
anytls_info_file="$HOME/anytls_info.inf"
anytls_domain_file="/etc/sing-box/domain"
anytls_users_file="/etc/sing-box/users"
anytls_routing_conf_file="/etc/sing-box/routing.conf"
anytls_block_domains_file="/etc/sing-box/block_domains"
anytls_block_ips_file="/etc/sing-box/block_ips"
anytls_port=""
amce_sh_file="/root/.acme.sh/acme.sh"
ssl_update_file="/usr/bin/ssl_update.sh"
nginx_version="1.30.4"
openssl_version="3.5.7"
jemalloc_version="5.3.1"
old_config_status="off"
# 流量面板
panel_bin_dir="/usr/local/bin/panel"
panel_conf_dir="/etc/panel"
panel_conf="${panel_conf_dir}/config.json"
panel_db_dir="/var/lib/panel"
panel_db="${panel_db_dir}/panel.db"
panel_systemd_file="/etc/systemd/system/panel.service"
panel_auth_file="/etc/panel/panel.htpasswd"
panel_session_key="/etc/panel/panel.key"
panel_listen_addr="127.0.0.1:2052"
panel_v2ray_api_port="50085"
panel_singbox_api_port="50086"
panel_clash_api_port="50087"
panel_geo_db="/etc/panel/ip2region_v4.xdb"
singbox_log_file="/var/log/sing-box/sing-box.log"
singbox_vmess_port_file="/etc/sing-box/vmess_port"
singbox_anytls_port_file="/etc/sing-box/anytls_port"
nginx_ws_access_log="/var/log/nginx/ws-access.log"
panel_repo="layfu/vmess_ws-tls_bash_onekey"
# v2ray_plugin_version="$(wget -qO- "https://github.com/shadowsocks/v2ray-plugin/tags" | grep -E "/shadowsocks/v2ray-plugin/releases/tag/" | head -1 | sed -r 's/.*tag\/v(.+)\">.*/\1/')"

#移动旧版本配置信息 对小于 1.1.0 版本适配
[[ -f "/etc/v2ray/vmess_qr.json" ]] && mv /etc/v2ray/vmess_qr.json $v2ray_qr_config_file

#简易随机数
random_num=$((RANDOM%12+4))
#生成伪装路径
camouflage="/$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})/"

THREAD=$(grep 'processor' /proc/cpuinfo | sort -u | wc -l)

source '/etc/os-release'

#从VERSION中提取发行版系统的英文名称，为了在debian/ubuntu下添加相对应的Nginx apt源
VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

check_system() {
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 11 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        $INS update
        ## 添加 Nginx apt源
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 20 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        rm /var/lib/dpkg/lock
        dpkg --configure -a
        rm /var/lib/apt/lists/lock
        rm /var/cache/apt/archives/lock
        $INS update
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi

    $INS install dbus

    systemctl stop firewalld
    systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

    systemctl stop ufw
    systemctl disable ufw
    echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

is_root() {
    if [ 0 == $UID ]; then
        echo -e "${OK} ${GreenBG} 当前用户是root用户，进入安装流程 ${Font}"
        sleep 3
    else
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

chrony_install() {
    ${INS} -y install chrony
    judge "安装 chrony 时间同步服务 "

    timedatectl set-ntp true

    if [[ "${ID}" == "centos" ]]; then
        systemctl enable chronyd && systemctl restart chronyd
    else
        systemctl enable chrony && systemctl restart chrony
    fi

    judge "chronyd 启动 "

    timedatectl set-timezone Asia/Shanghai

    echo -e "${OK} ${GreenBG} 等待时间同步 ${Font}"
    sleep 10

    chronyc sourcestats -v
    chronyc tracking -v
    date
    read -rp "请确认时间是否准确,误差范围±3分钟(Y/N): " chrony_install
    [[ -z ${chrony_install} ]] && chrony_install="Y"
    case $chrony_install in
    [yY][eE][sS] | [yY])
        echo -e "${GreenBG} 继续安装 ${Font}"
        sleep 2
        ;;
    *)
        echo -e "${RedBG} 安装终止 ${Font}"
        exit 2
        ;;
    esac
}

dependency_install() {
    if [[ "${ID}" == "centos" ]]; then
        ${INS} install wget git lsof bind-utils -y
    else
        ${INS} install wget git lsof dnsutils -y
    fi

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install crontabs
    else
        ${INS} -y install cron
    fi
    judge "安装 crontab"

    if [[ "${ID}" == "centos" ]]; then
        touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
        systemctl start crond && systemctl enable crond
    else
        touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
        systemctl start cron && systemctl enable cron

    fi
    judge "crontab 自启动配置 "

    ${INS} -y install bc
    judge "安装 bc"

    ${INS} -y install unzip
    judge "安装 unzip"

    ${INS} -y install curl
    judge "安装 curl"

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y groupinstall "Development tools"
    else
        ${INS} -y install build-essential
    fi
    judge "编译工具包 安装"

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install pcre2-devel zlib-devel epel-release
    else
        ${INS} -y install libpcre2-dev zlib1g-dev dbus
    fi

    #    ${INS} -y install rng-tools
    #    judge "rng-tools 安装"

    ${INS} -y install haveged
    #    judge "haveged 安装"

    #    sed -i -r '/^HRNGDEVICE/d;/#HRNGDEVICE=\/dev\/null/a HRNGDEVICE=/dev/urandom' /etc/default/rng-tools

    if [[ "${ID}" == "centos" ]]; then
        #       systemctl start rngd && systemctl enable rngd
        #       judge "rng-tools 启动"
        systemctl start haveged && systemctl enable haveged
        #       judge "haveged 启动"
    else
        #       systemctl start rng-tools && systemctl enable rng-tools
        #       judge "rng-tools 启动"
        systemctl start haveged && systemctl enable haveged
        #       judge "haveged 启动"
    fi

    mkdir -p /usr/local/bin >/dev/null 2>&1
}

basic_optimization() {
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >>/etc/security/limits.conf
    echo '* hard nofile 65536' >>/etc/security/limits.conf

    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi

}

port_alterid_set() {
    if [[ "on" != "$old_config_status" ]]; then
        read -rp "请输入连接端口（default:443）:" port
        [[ -z ${port} ]] && port="443"
        alterID="0"
    fi
}

modify_nginx_port() {
    if [[ "on" == "$old_config_status" ]]; then
        port="$(info_extraction '\"port\"')"
    fi
    sed -i "/ssl;$/c \\\tlisten ${port} ssl;" ${nginx_conf}
    sed -i "3c \\\tlisten [::]:${port} ssl;" ${nginx_conf}
    judge "V2ray port 修改"
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"port\"/c \\  \"port\": \"${port}\"," ${v2ray_qr_config_file}
    echo -e "${OK} ${GreenBG} 端口号:${port} ${Font}"
}

modify_nginx_other() {
    sed -i "/server_name/c \\\tserver_name ${domain};" ${nginx_conf}
    sed -i "/location/c \\\tlocation ${camouflage}" ${nginx_conf}
    sed -i "/proxy_pass/c \\\tproxy_pass http://127.0.0.1:${PORT};" ${nginx_conf}
    sed -i "/return/c \\\treturn 301 https://${domain}\$request_uri;" ${nginx_conf}
    #sed -i "27i \\\tproxy_intercept_errors on;"  ${nginx_dir}/conf/nginx.conf
}

web_camouflage() {
    ##请注意 这里和LNMP脚本的默认路径冲突，千万不要在安装了LNMP的环境下使用本脚本，否则后果自负
    rm -rf /home/wwwroot
    mkdir -p /home/wwwroot
    cd /home/wwwroot || exit
    git clone https://github.com/wulabing/3DCEList.git
    judge "web 站点伪装"
}

v2ray_install() {
    if [[ -d /root/v2ray ]]; then
        rm -rf /root/v2ray
    fi
    if [[ -d /etc/v2ray ]]; then
        rm -rf /etc/v2ray
    fi
    mkdir -p /root/v2ray
    cd /root/v2ray || exit
    wget -N --no-check-certificate https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/${github_branch}/v2ray.sh

    if [[ -f v2ray.sh ]]; then
        rm -rf $v2ray_systemd_file
        systemctl daemon-reload
        bash v2ray.sh --force
        judge "安装 V2ray"
    else
        echo -e "${Error} ${RedBG} V2ray 安装文件下载失败，请检查下载地址是否可用 ${Font}"
        exit 4
    fi
    # 清除临时文件
    rm -rf /root/v2ray
}

v2ray_update() {
    if [[ ! -f "${v2ray_bin_dir}" ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 V2Ray ${Font}"
        return 1
    fi

    local current_ver
    current_ver="$(${v2ray_bin_dir} version | head -n 1 | awk '{print $2}')"
    echo -e "${OK} ${GreenBG} 当前 V2Ray 版本: ${current_ver} ${Font}"

    echo -e "${OK} ${GreenBG} 正在检查最新版本... ${Font}"
    local tmp_file latest_ver
    tmp_file="$(mktemp)"
    if ! curl -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest'; then
        rm -f "$tmp_file"
        echo -e "${Error} ${RedBG} 获取版本信息失败，请检查网络连接 ${Font}"
        return 1
    fi
    latest_ver="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm -f "$tmp_file"

    if [[ -z "$latest_ver" ]]; then
        echo -e "${Error} ${RedBG} 获取版本信息失败 ${Font}"
        return 1
    fi

    latest_ver="${latest_ver#v}"
    current_ver="${current_ver#v}"

    if [[ "${current_ver}" == "${latest_ver}" ]]; then
        echo -e "${OK} ${GreenBG} 当前已是最新版本 ${latest_ver}，无需升级 ${Font}"
        return 0
    fi

    echo -e "${OK} ${GreenBG} 发现新版本: ${latest_ver} (当前: ${current_ver}) ${Font}"
    read -rp "是否升级? [Y/N]: " update_confirm
    case $update_confirm in
        [yY][eE][sS]|[yY])
            ;;
        *)
            echo -e "${OK} ${GreenBG} 已取消升级 ${Font}"
            return 0
            ;;
    esac

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    cd "$tmp_dir" || return 1

    echo -e "${OK} ${GreenBG} 正在下载升级脚本... ${Font}"
    if ! wget --no-check-certificate -O v2ray.sh "https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/${github_branch}/v2ray.sh?t=$(date +%s)"; then
        echo -e "${Error} ${RedBG} 下载升级脚本失败 ${Font}"
        rm -rf "$tmp_dir"
        return 1
    fi

    echo -e "${OK} ${GreenBG} 正在升级 V2Ray... ${Font}"
    if bash v2ray.sh --force; then
        judge "V2Ray 升级"
    else
        echo -e "${Error} ${RedBG} V2Ray 升级失败 ${Font}"
        cd /tmp || true
        rm -rf "$tmp_dir"
        return 1
    fi

    cd /tmp || true
    rm -rf "$tmp_dir"

    local new_ver
    new_ver="$(${v2ray_bin_dir} version | head -n 1 | awk '{print $2}')"
    echo -e "${OK} ${GreenBG} V2Ray 已升级至 ${new_ver} ${Font}"
}

singbox_arch() {
    case "$(uname -m)" in
        'i386' | 'i686')
            echo '386'
            ;;
        'amd64' | 'x86_64')
            echo 'amd64'
            ;;
        'armv5tel')
            echo 'armv5'
            ;;
        'armv6l')
            echo 'armv6'
            ;;
        'armv7' | 'armv7l')
            echo 'armv7'
            ;;
        'armv8' | 'aarch64')
            echo 'arm64'
            ;;
        'mips64le')
            echo 'mips64le'
            ;;
        'mipsle')
            echo 'mipsle'
            ;;
        'ppc64le')
            echo 'ppc64le'
            ;;
        'riscv64')
            echo 'riscv64'
            ;;
        's390x')
            echo 's390x'
            ;;
        'loongarch64')
            echo 'loong64'
            ;;
        *)
            echo -e "${Error} ${RedBG} 不支持的架构: $(uname -m) ${Font}"
            exit 1
            ;;
    esac
}

singbox_download() {
    local tmp_file latest_ver
    tmp_file="$(mktemp)"
    if ! curl -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/SagerNet/sing-box/releases/latest'; then
        rm -f "$tmp_file"
        echo -e "${Error} ${RedBG} 获取 sing-box 版本信息失败，请检查网络连接 ${Font}"
        return 1
    fi
    latest_ver="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm -f "$tmp_file"

    if [[ -z "$latest_ver" ]]; then
        echo -e "${Error} ${RedBG} 获取 sing-box 版本信息失败 ${Font}"
        return 1
    fi

    local arch tmp_dir
    arch="$(singbox_arch)"
    tmp_dir="$(mktemp -d)"
    cd "$tmp_dir" || return 1

    echo -e "${OK} ${GreenBG} 正在下载 sing-box ${latest_ver} (linux-${arch}) ... ${Font}"
    local download_link
    download_link="https://github.com/SagerNet/sing-box/releases/download/${latest_ver}/sing-box-${latest_ver#v}-linux-${arch}.tar.gz"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 -o "sing-box.tar.gz" "$download_link"; then
        echo -e "${Error} ${RedBG} sing-box 下载失败: ${download_link} ${Font}"
        cd /tmp || true
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf sing-box.tar.gz
    if [[ ! -f "${tmp_dir}/sing-box/sing-box" ]] && [[ ! -f "${tmp_dir}/sing-box-${latest_ver#v}-linux-${arch}/sing-box" ]]; then
        echo -e "${Error} ${RedBG} 解压后未找到 sing-box 二进制文件 ${Font}"
        cd /tmp || true
        rm -rf "$tmp_dir"
        return 1
    fi

    local bin_path
    bin_path="$(find "$tmp_dir" -type f -name 'sing-box' -path '*sing-box*' | head -1)"
    install -m 755 "$bin_path" "${singbox_bin_dir}"
    judge "sing-box 安装"

    cd /tmp || true
    rm -rf "$tmp_dir"
    return 0
}

singbox_systemd() {
    cat >${singbox_systemd_file} <<EOF
[Unit]
Description=sing-box Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${singbox_bin_dir} run -c ${singbox_conf}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    judge "sing-box systemd ServerFile 添加"
    systemctl daemon-reload
}

singbox_install() {
    if [[ -f "${singbox_bin_dir}" ]]; then
        echo -e "${OK} ${GreenBG} sing-box 已存在，跳过下载安装过程 ${Font}"
        sleep 1
    else
        singbox_download
        [[ $? -eq 0 ]] || exit 1
    fi
    mkdir -p ${singbox_conf_dir}
    singbox_systemd
}

singbox_update() {
    if [[ ! -f "${singbox_bin_dir}" ]]; then
        echo -e "${Error} ${RedBG} sing-box 未安装，请先安装 AnyTLS ${Font}"
        return 1
    fi

    if singbox_has_v2ray_api; then
        echo -e "${Red} 检测到当前内核为带 v2ray_api 的定制版 sing-box。${Font}"
        echo -e "${Red} 「升级 sing-box」将替换为官方版（不含 v2ray_api），会导致 AnyTLS 每用户流量统计失效，且现有配置可能无法启动。${Font}"
        read -rp "是否改用「更新 sing-box (v2ray_api)」继续更新?（输入 n 取消本次升级）[Y/n]: " confirm
        [[ -z "${confirm}" ]] && confirm="Y"
        case "${confirm}" in
        [yY][eE][sS] | [yY])
            singbox_v2rayapi_update
            ;;
        *)
            echo -e "${OK} ${GreenBG} 已取消，本次未做任何更改 ${Font}"
            ;;
        esac
        return 0
    fi

    local current_ver
    current_ver="$(${singbox_bin_dir} version -n 2>/dev/null | head -n 1)"
    echo -e "${OK} ${GreenBG} 当前 sing-box 版本: ${current_ver} ${Font}"

    local tmp_file latest_ver
    tmp_file="$(mktemp)"
    if ! curl -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" 'https://api.github.com/repos/SagerNet/sing-box/releases/latest'; then
        rm -f "$tmp_file"
        echo -e "${Error} ${RedBG} 获取版本信息失败，请检查网络连接 ${Font}"
        return 1
    fi
    latest_ver="$(sed 'y/,/\n/' "$tmp_file" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm -f "$tmp_file"

    if [[ -z "$latest_ver" ]]; then
        echo -e "${Error} ${RedBG} 获取版本信息失败 ${Font}"
        return 1
    fi
    latest_ver="${latest_ver#v}"

    if [[ "${current_ver}" == "${latest_ver}" ]]; then
        echo -e "${OK} ${GreenBG} 当前已是最新版本 ${latest_ver}，无需升级 ${Font}"
        return 0
    fi

    echo -e "${OK} ${GreenBG} 发现新版本: ${latest_ver} (当前: ${current_ver}) ${Font}"
    read -rp "是否升级? [Y/N]: " update_confirm
    case $update_confirm in
        [yY][eE][sS]|[yY])
            ;;
        *)
            echo -e "${OK} ${GreenBG} 已取消升级 ${Font}"
            return 0
            ;;
    esac

    systemctl stop sing-box
    if singbox_download; then
        judge "sing-box 升级"
    else
        echo -e "${Error} ${RedBG} sing-box 升级失败 ${Font}"
        systemctl start sing-box
        return 1
    fi
    systemctl start sing-box

    local new_ver
    new_ver="$(${singbox_bin_dir} version -n 2>/dev/null | head -n 1)"
    echo -e "${OK} ${GreenBG} sing-box 已升级至 ${new_ver} ${Font}"
}

panel_installed() {
    [[ -f "${panel_bin_dir}" ]]
}

singbox_has_v2ray_api() {
    [[ -x "${singbox_bin_dir}" ]] || return 1
    local tmp
    tmp="$(mktemp)"
    cat >"${tmp}" <<'EOF'
{ "experimental": { "v2ray_api": { "listen": "127.0.0.1:50086", "stats": { "enabled": true } } } }
EOF
    "${singbox_bin_dir}" check -c "${tmp}" >/dev/null 2>&1
    local rc=$?
    rm -f "${tmp}"
    return "${rc}"
}

singbox_v2rayapi_download() {
    local arch tmp_dir
    arch="$(singbox_arch)"
    tmp_dir="$(mktemp -d)"
    local url="https://github.com/${panel_repo}/releases/latest/download/sing-box-v2rayapi-linux-${arch}"
    echo -e "${OK} ${GreenBG} 正在下载带 v2ray_api 的 sing-box (linux-${arch}) ... ${Font}"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 -o "${tmp_dir}/sing-box" "${url}"; then
        echo -e "${Error} ${RedBG} 下载失败: ${url} ${Font}"
        rm -rf "${tmp_dir}"
        return 1
    fi
    chmod +x "${tmp_dir}/sing-box"
    if curl -L -q --retry 3 --retry-delay 5 -o "${tmp_dir}/sing-box.sha256" "${url}.sha256" 2>/dev/null; then
        local expected actual
        expected="$(awk '{print $1}' "${tmp_dir}/sing-box.sha256")"
        actual="$(sha256sum "${tmp_dir}/sing-box" | awk '{print $1}')"
        if [[ -n "${expected}" && "${expected}" != "${actual}" ]]; then
            echo -e "${Error} ${RedBG} sing-box 校验失败 ${Font}"
            rm -rf "${tmp_dir}"
            return 1
        fi
    fi
    if [[ -f "${singbox_bin_dir}" ]]; then
        cp -f "${singbox_bin_dir}" "${singbox_bin_dir}.bak" 2>/dev/null
        echo -e "${OK} ${GreenBG} 原 sing-box 已备份为 ${singbox_bin_dir}.bak ${Font}"
    fi
    install -m 755 "${tmp_dir}/sing-box" "${singbox_bin_dir}"
    rm -rf "${tmp_dir}"
    judge "sing-box (v2ray_api) 替换"
    return 0
}

singbox_v2rayapi_ensure() {
    [[ -f "${singbox_conf}" ]] || return 0
    singbox_has_v2ray_api && return 0
    local confirm=""
    echo -e "${Red} 当前 sing-box 未编译 v2ray_api，AnyTLS 每用户流量统计不可用。 ${Font}"
    read -rp "是否下载带 v2ray_api 的 sing-box 并替换（默认 Y，原二进制备份为 .bak）? [Y/n]: " confirm
    [[ -z "${confirm}" ]] && confirm="Y"
    case "${confirm}" in
    [yY][eE][sS] | [yY])
        singbox_v2rayapi_download || echo -e "${Error} ${RedBG} 下载失败，AnyTLS 每用户统计仍不可用（可稍后重试） ${Font}"
        ;;
    *) ;;
    esac
    return 0
}

singbox_v2rayapi_update() {
    [[ -f "${singbox_conf}" ]] || { echo -e "${Error} ${RedBG} AnyTLS 未安装，无需更新 ${Font}"; return 0; }
    if ! singbox_has_v2ray_api; then
        singbox_v2rayapi_ensure
        if singbox_has_v2ray_api; then
            anytls_conf_add
            systemctl restart sing-box >/dev/null 2>&1
            judge "sing-box (v2ray_api) 替换"
        fi
        return 0
    fi

    local current_ver
    current_ver="$(${singbox_bin_dir} version -n 2>/dev/null | head -n 1)"
    echo -e "${OK} ${GreenBG} 当前 sing-box 版本: ${current_ver} ${Font}"

    local tmp_file latest_ver
    tmp_file="$(mktemp)"
    if ! curl -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" "https://api.github.com/repos/${panel_repo}/releases/latest"; then
        rm -f "$tmp_file"
        echo -e "${Error} ${RedBG} 获取版本信息失败，请检查网络连接 ${Font}"
        return 1
    fi
    latest_ver="$(sed 'y/,/\n/' "$tmp_file" | grep '"body"' | grep -oE 'sing-box: *v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $NF}')"
    rm -f "$tmp_file"

    if [[ -z "$latest_ver" ]]; then
        echo -e "${Error} ${RedBG} 无法获取带 v2ray_api 的 sing-box 版本信息，将直接下载 ${Font}"
    else
        latest_ver="${latest_ver#v}"
        if [[ "${current_ver}" == "${latest_ver}" ]]; then
            echo -e "${OK} ${GreenBG} 当前已是最新版本 ${latest_ver}，无需更新 ${Font}"
            return 0
        fi
        echo -e "${OK} ${GreenBG} 发现新版本: ${latest_ver} (当前: ${current_ver}) ${Font}"
    fi

    local confirm=""
    read -rp "是否下载最新 sing-box (v2ray_api) 并替换（默认 Y，原二进制备份为 .bak）? [Y/n]: " confirm
    [[ -z "${confirm}" ]] && confirm="Y"
    case "${confirm}" in
    [yY][eE][sS] | [yY])
        if singbox_v2rayapi_download; then
            anytls_conf_add
            systemctl restart sing-box >/dev/null 2>&1
            judge "sing-box (v2ray_api) 更新"
        fi
        ;;
    *) ;;
    esac
    return 0
}

panel_download() {
    local arch tmp_dir
    arch="$(singbox_arch)"
    tmp_dir="$(mktemp -d)"
    local url="https://github.com/${panel_repo}/releases/latest/download/panel-linux-${arch}"
    echo -e "${OK} ${GreenBG} 正在下载流量面板 (linux-${arch}) ... ${Font}"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 -o "${tmp_dir}/panel" "${url}"; then
        echo -e "${Error} ${RedBG} 面板下载失败: ${url} ${Font}"
        echo -e "${Red} 请先在 GitHub 仓库打 tag 发布 panel 二进制，或手动放入 ${panel_bin_dir} ${Font}"
        rm -rf "${tmp_dir}"
        return 1
    fi
    chmod +x "${tmp_dir}/panel"
    if curl -L -q --retry 3 --retry-delay 5 -o "${tmp_dir}/panel.sha256" "${url}.sha256" 2>/dev/null; then
        local expected actual
        expected="$(awk '{print $1}' "${tmp_dir}/panel.sha256")"
        actual="$(sha256sum "${tmp_dir}/panel" | awk '{print $1}')"
        if [[ -n "${expected}" && "${expected}" != "${actual}" ]]; then
            echo -e "${Error} ${RedBG} 面板校验失败 ${Font}"
            rm -rf "${tmp_dir}"
            return 1
        fi
    fi
    install -m 755 "${tmp_dir}/panel" "${panel_bin_dir}"
    rm -rf "${tmp_dir}"
    judge "面板安装"
    return 0
}

panel_geo_download() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local url="https://raw.githubusercontent.com/lionsoul2014/ip2region/master/data/ip2region_v4.xdb"
    echo -e "${OK} ${GreenBG} 正在下载 IP 归属地数据库 (ip2region) ... ${Font}"
    if ! curl -L -q --retry 3 --retry-delay 5 --retry-max-time 120 -o "${tmp_dir}/ip2region_v4.xdb" "${url}"; then
        echo -e "${Error} ${RedBG} IP 归属地数据库下载失败: ${url} ${Font}"
        echo -e "${Red} 面板「最近连接」的来源 IP 将不显示归属地（不影响其他功能） ${Font}"
        rm -rf "${tmp_dir}"
        return 1
    fi
    mkdir -p "$(dirname "${panel_geo_db}")"
    install -m 644 "${tmp_dir}/ip2region_v4.xdb" "${panel_geo_db}"
    rm -rf "${tmp_dir}"
    judge "IP 归属地数据库安装"
    return 0
}

panel_geo_update() {
    if ! panel_installed; then
        echo -e "${Error} ${RedBG} 面板未安装，无需更新 ${Font}"
        return 0
    fi
    if panel_geo_download; then
        systemctl restart panel >/dev/null 2>&1
        judge "面板重启加载 IP 归属地数据库"
    fi
    return 0
}

panel_config_gen() {
    mkdir -p "${panel_conf_dir}" "${panel_db_dir}"
    local v2ray_enabled="false" singbox_enabled="false"
    [[ -s "${vmess_users_file}" ]] && v2ray_enabled="true"
    # VMess 与 AnyTLS 都由 sing-box 承载，装了 sing-box 即视为启用
    [[ -f "${singbox_conf}" ]] && singbox_enabled="true"
    cat >"${panel_conf}" <<EOF
{
  "listen": "${panel_listen_addr}",
  "db_path": "${panel_db}",
  "poll_interval_sec": 15,
  "online_window_sec": 90,
  "retention_days": 1095,
  "geo_db": "${panel_geo_db}",
  "auth_file": "${panel_auth_file}",
  "session_secret_file": "${panel_session_key}",
  "session_ttl_sec": 604800,
  "login_max_fails": 5,
  "login_lock_sec": 1800,
  "v2ray": {
    "enabled": ${v2ray_enabled},
    "api_addr": "127.0.0.1:${panel_singbox_api_port}",
    "access_log": "",
    "ws_access_log": "${nginx_ws_access_log}",
    "users_file": "${vmess_users_file}",
    "config_file": "${singbox_conf}",
    "qr_file": "${v2ray_qr_config_file}"
  },
  "singbox": {
    "enabled": ${singbox_enabled},
    "api_addr": "127.0.0.1:${panel_singbox_api_port}",
    "log_file": "${singbox_log_file}",
    "users_file": "${anytls_users_file}",
    "vmess_users_file": "${vmess_users_file}",
    "clash_api_addr": "127.0.0.1:${panel_clash_api_port}",
    "config_file": "${singbox_conf}",
    "domain_file": "${anytls_domain_file}"
  }
}
EOF
    judge "面板配置生成"
}

panel_auth_set() {
    local panel_user="" panel_pass=""
    read -rp "请输入面板登录用户名（default:admin）:" panel_user
    [[ -z "${panel_user}" ]] && panel_user="admin"
    read -rp "请输入面板登录密码（留空则随机生成）:" panel_pass
    if [[ -z "${panel_pass}" ]]; then
        panel_pass="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)"
    fi
    mkdir -p "${panel_conf_dir}"
    local salt hash
    salt="$(head -c 8 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 8)"
    hash="$(openssl passwd -apr1 -salt "${salt}" "${panel_pass}" 2>/dev/null)"
    if [[ -z "${hash}" ]]; then
        echo -e "${Error} ${RedBG} 生成密码哈希失败（openssl 不可用） ${Font}"
        return 1
    fi
    printf '%s:%s\n' "${panel_user}" "${hash}" >"${panel_auth_file}"
    echo -e "${OK} ${GreenBG} 面板登录账号: ${panel_user}  密码: ${panel_pass} ${Font}"
    echo -e "${Red} 请妥善保存上述密码 ${Font}"
}

panel_session_secret_ensure() {
    if [[ ! -f "${panel_session_key}" ]]; then
        mkdir -p "${panel_conf_dir}"
        head -c 32 /dev/urandom | base64 >"${panel_session_key}"
        chmod 600 "${panel_session_key}"
    fi
}

panel_nginx_location_add() {
    [[ -f "${nginx_conf}" ]] || return 0
    grep -q 'location /panel/' "${nginx_conf}" && return 0
    local tmpfile
    tmpfile="$(mktemp)"
    cat >"${tmpfile}" <<EOF
        location = /panel { return 301 /panel/; }
        location /panel/ {
            proxy_pass http://${panel_listen_addr}/;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
EOF
    awk 'NR==FNR { block=block $0 "\n"; next } /^}[[:space:]]*$/ && !done { printf "%s", block; done=1 } { print }' "${tmpfile}" "${nginx_conf}" >"${nginx_conf}.panel.tmp"
    rm -f "${tmpfile}"
    mv "${nginx_conf}.panel.tmp" "${nginx_conf}"
    judge "Nginx /panel/ 反代配置"
}

panel_nginx_location_del() {
    [[ -f "${nginx_conf}" ]] || return 0
    grep -q 'location /panel/' "${nginx_conf}" || return 0
    sed -i '/location = \/panel { return 301 \/panel\/; }/d' "${nginx_conf}"
    awk '
        BEGIN { skip = 0 }
        /location \/panel\/ \{/ { skip = 1 }
        !skip { print }
        skip && /^[[:space:]]*\}/ { skip = 0 }
    ' "${nginx_conf}" >"${nginx_conf}.panel.tmp" && mv "${nginx_conf}.panel.tmp" "${nginx_conf}"
}

nginx_ws_access_log_add() {
    [[ -f "${nginx_conf}" ]] || return 0
    if ! grep -q 'log_format panel_ws' "${nginx_conf}"; then
        printf "log_format panel_ws '\$remote_addr \$time_iso8601 \$request_uri \$status';\n" >"${nginx_conf}.panel.hdr"
        cat "${nginx_conf}.panel.hdr" "${nginx_conf}" >"${nginx_conf}.panel.tmp"
        mv "${nginx_conf}.panel.tmp" "${nginx_conf}"
        rm -f "${nginx_conf}.panel.hdr"
    fi
    if ! grep -q 'ws-access.log' "${nginx_conf}"; then
        awk -v al="        access_log ${nginx_ws_access_log} panel_ws;" '
            /proxy_redirect off;/ && !done { print al; done = 1 }
            { print }
        ' "${nginx_conf}" >"${nginx_conf}.panel.tmp" && mv "${nginx_conf}.panel.tmp" "${nginx_conf}"
    fi
    mkdir -p /var/log/nginx
    touch "${nginx_ws_access_log}"
}

nginx_ws_access_log_del() {
    [[ -f "${nginx_conf}" ]] || return 0
    sed -i '/ws-access.log/d' "${nginx_conf}"
    sed -i '/log_format panel_ws/d' "${nginx_conf}"
}

panel_systemd() {
    cat >"${panel_systemd_file}" <<EOF
[Unit]
Description=Traffic Panel
After=network.target

[Service]
Type=simple
ExecStart=${panel_bin_dir} -c ${panel_conf}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    judge "面板 systemd 配置"
}

panel_install() {
    if panel_installed; then
        echo -e "${Error} ${RedBG} 已安装 流量面板，拒绝重复安装 ${Font}"
        return 1
    fi
    panel_download || return 1
    panel_config_gen
    panel_geo_download
    panel_session_secret_ensure
    if [[ ! -f "${panel_auth_file}" ]]; then
        panel_auth_set
    fi
    mkdir -p /var/log/sing-box
    panel_nginx_location_add
    nginx_ws_access_log_add
    panel_systemd
    singbox_v2rayapi_ensure
    [[ -f "${v2ray_conf}" ]] && v2ray_conf_add
    [[ -f "${singbox_conf}" ]] && anytls_conf_add
    systemctl restart sing-box >/dev/null 2>&1
    [[ -f "${singbox_systemd_file}" ]] && systemctl restart sing-box >/dev/null 2>&1
    systemctl enable panel >/dev/null 2>&1
    systemctl restart panel
    judge "面板启动"
    systemctl restart nginx >/dev/null 2>&1
    if [[ -f "${singbox_conf}" ]] && ! singbox_has_v2ray_api; then
        echo -e "${Red} 提示：sing-box 未编译 v2ray_api，AnyTLS 每用户流量统计不可用（连接日志仍可查看）。 ${Font}"
    fi
    local domain=""
    [[ -f "${v2ray_qr_config_file}" ]] && domain="$(grep '\"add\"' "${v2ray_qr_config_file}" | awk -F '"' '{print $4}')"
    [[ -z "${domain}" && -f "${anytls_domain_file}" ]] && domain="$(cat "${anytls_domain_file}")"
    echo -e "${Green} 面板访问地址: ${Font} https://${domain}/panel/"
}

panel_update() {
    if ! panel_installed; then
        echo -e "${Error} ${RedBG} 面板未安装，请先安装 ${Font}"
        return 1
    fi

    # 清理旧版 Nginx 遗留的 basic auth（幂等，面板鉴权已改由面板自实现）
    if [[ -f "${nginx_conf}" ]] && grep -q 'auth_basic' "${nginx_conf}"; then
        sed -i '/auth_basic/d' "${nginx_conf}"
        systemctl restart nginx >/dev/null 2>&1
        echo -e "${OK} ${GreenBG} 已移除 Nginx 旧鉴权配置 ${Font}"
    fi

    local current_ver
    current_ver="$("${panel_bin_dir}" -v 2>/dev/null | head -n 1)"
    [[ -n "${current_ver}" ]] && echo -e "${OK} ${GreenBG} 当前面板版本: ${current_ver} ${Font}"

    local tmp_file latest_ver
    tmp_file="$(mktemp)"
    if curl -sS -H "Accept: application/vnd.github.v3+json" -o "$tmp_file" "https://api.github.com/repos/${panel_repo}/releases/latest"; then
        latest_ver="$(sed 'y/,/\n/' "$tmp_file" | grep '"body"' | grep -oE 'panel: *[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | awk '{print $NF}')"
    fi
    rm -f "$tmp_file"

    if [[ -n "${latest_ver}" && -n "${current_ver}" && "${current_ver}" == "${latest_ver}" ]]; then
        echo -e "${OK} ${GreenBG} 当前已是最新版本 ${latest_ver}，无需更新 ${Font}"
        return 0
    fi
    if [[ -n "${latest_ver}" && -n "${current_ver}" ]]; then
        echo -e "${OK} ${GreenBG} 发现新版本: ${latest_ver} (当前: ${current_ver}) ${Font}"
    fi

    local confirm=""
    read -rp "是否下载最新流量面板并升级（默认 Y）? [Y/n]: " confirm
    [[ -z "${confirm}" ]] && confirm="Y"
    case "${confirm}" in
    [yY][eE][sS] | [yY]) ;;
    *)
        echo -e "${OK} ${GreenBG} 已取消升级 ${Font}"
        return 0
        ;;
    esac

    if panel_download; then
        systemctl stop panel >/dev/null 2>&1
        panel_config_gen
        panel_geo_download
        panel_session_secret_ensure
        nginx_ws_access_log_add
        singbox_v2rayapi_ensure
        [[ -f "${v2ray_conf}" ]] && v2ray_conf_add
        [[ -f "${singbox_conf}" ]] && anytls_conf_add
        systemctl restart sing-box >/dev/null 2>&1
        [[ -f "${singbox_systemd_file}" ]] && systemctl restart sing-box >/dev/null 2>&1
        systemctl start panel >/dev/null 2>&1
        if systemctl is-active --quiet panel; then
            judge "面板升级"
        else
            echo -e "${Error} ${RedBG} 面板启动失败，请执行 journalctl -u panel -n 50 查看日志 ${Font}"
        fi
        systemctl restart nginx >/dev/null 2>&1
    else
        return 1
    fi
}

panel_uninstall() {
    systemctl disable panel >/dev/null 2>&1
    systemctl stop panel >/dev/null 2>&1
    rm -f "${panel_systemd_file}"
    rm -f "${panel_bin_dir}"
    panel_nginx_location_del
    nginx_ws_access_log_del
    [[ -f "${v2ray_conf}" ]] && v2ray_conf_add && systemctl restart sing-box >/dev/null 2>&1
    [[ -f "${singbox_conf}" ]] && anytls_conf_add && [[ -f "${singbox_systemd_file}" ]] && systemctl restart sing-box >/dev/null 2>&1
    systemctl restart nginx >/dev/null 2>&1
    systemctl daemon-reload
    echo -e "${OK} ${GreenBG} 已卸载流量面板（配置与历史数据库已保留，可重新安装恢复） ${Font}"
}

anytls_port_set() {
    read -rp "请输入 AnyTLS 连接端口（default:8443）:" anytls_port
    [[ -z ${anytls_port} ]] && anytls_port="8443"
}

anytls_gen_password() {
    head -c 16 /dev/urandom | md5sum | head -c 16
}

# 用户名合法性：非空、无空格、无冒号（冒号用于 sing-box 内部的协议前缀 v:/a:）。
check_user_name() {
    local name="$1"
    if [[ -z "${name}" ]]; then
        echo -e "${Error} ${RedBG} 用户名不能为空 ${Font}"
        return 1
    fi
    if [[ "${name}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含空格 ${Font}"
        return 1
    fi
    if [[ "${name}" == *:* ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含冒号 :（用于协议区分） ${Font}"
        return 1
    fi
    return 0
}

# 跨协议同名提醒：若同名已存在于另一个协议，提示并二次确认（视为同一用户，流量合并）。
confirm_cross_protocol_name() {
    local name="$1" other_file="$2" other_label="$3"
    if [[ -s "${other_file}" ]] && grep -q "^${name} " "${other_file}"; then
        echo -e "${OK} ${Green} 提示：用户名 ${name} 已存在于 ${other_label}，将视为同一用户，流量在拓扑中合并统计。 ${Font}"
        read -rp "确认继续? [y/N]: " confirm_cross
        case "${confirm_cross}" in
        [yY][eE][sS] | [yY]) return 0 ;;
        *) return 1 ;;
        esac
    fi
    return 0
}

anytls_users_ensure() {
    if [[ ! -f "${anytls_users_file}" ]]; then
        mkdir -p "${singbox_conf_dir}"
        local existing_pass=""
        if [[ -f "${singbox_conf}" ]]; then
            existing_pass="$(grep -o '\"password\":\"[^\"]*\"' "${singbox_conf}" | head -1 | cut -d'\"' -f4)"
        fi
        [[ -z "${existing_pass}" ]] && existing_pass="$(anytls_gen_password)"
        echo "anytls ${existing_pass}" >"${anytls_users_file}"
    fi
}

anytls_user_list() {
    anytls_users_ensure
    echo -e "${OK} ${GreenBG} 当前 AnyTLS 用户列表 ${Font}"
    local idx=0
    while read -r name password; do
        [[ -z "${name}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} 名称: ${name}   密码: ${password}"
    done <"${anytls_users_file}"
}

anytls_user_add() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    local next_num=1
    while grep -q "^user${next_num} " "${anytls_users_file}"; do
        next_num=$((next_num + 1))
    done
    read -rp "请输入用户名（default:user${next_num}）:" user_name
    [[ -z "${user_name}" ]] && user_name="user${next_num}"
    check_user_name "${user_name}" || return 1
    if grep -q "^${user_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${user_name} 已存在 ${Font}"
        return 1
    fi
    confirm_cross_protocol_name "${user_name}" "${vmess_users_file}" "VMess" || return 1
    echo "${user_name} $(anytls_gen_password)" >>"${anytls_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS 用户添加"
    surge_config_output
}

anytls_user_del() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    anytls_user_list
    local count
    count="$(wc -l <"${anytls_users_file}")"
    if [[ "${count}" -le 1 ]]; then
        echo -e "${Error} ${RedBG} 至少保留一个用户，无法删除 ${Font}"
        return 1
    fi
    read -rp "请输入要删除的用户名:" del_name
    [[ -z "${del_name}" ]] && return 1
    if ! grep -q "^${del_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${del_name} 不存在 ${Font}"
        return 1
    fi
    sed -i "/^${del_name} /d" "${anytls_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS 用户删除"
    surge_config_output
}

anytls_user_password() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    anytls_user_list
    read -rp "请输入要修改密码的用户名:" chg_name
    [[ -z "${chg_name}" ]] && return 1
    if ! grep -q "^${chg_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${chg_name} 不存在 ${Font}"
        return 1
    fi
    sed -i "s/^${chg_name} .*/${chg_name} $(anytls_gen_password)/" "${anytls_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS 用户密码变更"
    surge_config_output
}

anytls_user_rename() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    anytls_user_list
    read -rp "请输入要修改的用户名:" old_name
    [[ -z "${old_name}" ]] && return 1
    if ! grep -q "^${old_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${old_name} 不存在 ${Font}"
        return 1
    fi
    read -rp "请输入新的用户名:" new_name
    [[ -z "${new_name}" ]] && return 1
    check_user_name "${new_name}" || return 1
    if grep -q "^${new_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${new_name} 已存在 ${Font}"
        return 1
    fi
    confirm_cross_protocol_name "${new_name}" "${vmess_users_file}" "VMess" || return 1
    local old_password
    old_password="$(grep "^${old_name} " "${anytls_users_file}" | head -1 | awk '{print $2}')"
    sed -i "/^${old_name} /d" "${anytls_users_file}"
    echo "${new_name} ${old_password}" >>"${anytls_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS 用户名修改"
    surge_config_output
}

anytls_user_menu() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        pause_continue
        return 1
    fi
    while true; do
        clear_screen
        echo -e "\t AnyTLS 用户管理"
        echo -e "${Green}1.${Font} 查看用户列表"
        echo -e "${Green}2.${Font} 添加用户"
        echo -e "${Green}3.${Font} 删除用户"
        echo -e "${Green}4.${Font} 修改用户密码"
        echo -e "${Green}5.${Font} 修改用户名"
        echo -e "${Green}6.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" user_menu_num
        case ${user_menu_num} in
        1)
            anytls_user_list
            ;;
        2)
            anytls_user_add
            ;;
        3)
            anytls_user_del
            ;;
        4)
            anytls_user_password
            ;;
        5)
            anytls_user_rename
            ;;
        6)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

anytls_routing_load() {
    anytls_block_cn=0
    anytls_block_ads=0
    anytls_block_bt=1
    anytls_warp_mode="off"
    if [[ -f "${anytls_routing_conf_file}" ]]; then
        anytls_block_cn="$(grep '^block_cn=' "${anytls_routing_conf_file}" | head -1 | cut -d= -f2)"
        anytls_block_ads="$(grep '^block_ads=' "${anytls_routing_conf_file}" | head -1 | cut -d= -f2)"
        anytls_block_bt="$(grep '^block_bt=' "${anytls_routing_conf_file}" | head -1 | cut -d= -f2)"
        anytls_warp_mode="$(grep '^warp_mode=' "${anytls_routing_conf_file}" | head -1 | cut -d= -f2)"
    fi
    [[ -z "${anytls_block_cn}" ]] && anytls_block_cn=0
    [[ -z "${anytls_block_ads}" ]] && anytls_block_ads=0
    [[ -z "${anytls_block_bt}" ]] && anytls_block_bt=1
    [[ "${anytls_warp_mode}" != "all" && "${anytls_warp_mode}" != "user" ]] && anytls_warp_mode="off"
}

anytls_routing_save() {
    mkdir -p "${singbox_conf_dir}"
    cat >"${anytls_routing_conf_file}" <<EOF
block_cn=${anytls_block_cn}
block_ads=${anytls_block_ads}
block_bt=${anytls_block_bt}
warp_mode=${anytls_warp_mode}
EOF
}

_anytls_rules_first=1
ANYTLS_ROUTING_RULES=""

_anytls_rules_append() {
    if [[ ${_anytls_rules_first} -eq 1 ]]; then
        _anytls_rules_first=0
        ANYTLS_ROUTING_RULES="$1"
    else
        ANYTLS_ROUTING_RULES="${ANYTLS_ROUTING_RULES},$1"
    fi
}

anytls_routing_rules_gen() {
    ANYTLS_ROUTING_RULES=""
    _anytls_rules_first=1

    if [[ "${anytls_block_bt}" == "1" ]]; then
        _anytls_rules_append '{"action":"sniff"}'
        _anytls_rules_append '{"protocol":"bittorrent","outbound":"block"}'
    fi
    if [[ "${anytls_block_ads}" == "1" ]]; then
        _anytls_rules_append '{"rule_set":"geosite-category-ads","outbound":"block"}'
    fi
    if [[ "${anytls_block_cn}" == "1" ]]; then
        _anytls_rules_append '{"rule_set":"geosite-cn","outbound":"block"}'
        _anytls_rules_append '{"rule_set":"geoip-cn","outbound":"block"}'
    fi

    local domains_json="" d first_d=1
    if [[ -f "${anytls_block_domains_file}" ]]; then
        while read -r d; do
            [[ -z "${d}" ]] && continue
            if [[ ${first_d} -eq 1 ]]; then first_d=0; else domains_json="${domains_json},"; fi
            domains_json="${domains_json}\"${d}\""
        done <"${anytls_block_domains_file}"
    fi
    [[ -n "${domains_json}" ]] && _anytls_rules_append "{\"domain_suffix\":[${domains_json}],\"outbound\":\"block\"}"

    local ips_json="" ip first_i=1
    if [[ -f "${anytls_block_ips_file}" ]]; then
        while read -r ip; do
            [[ -z "${ip}" ]] && continue
            if [[ ${first_i} -eq 1 ]]; then first_i=0; else ips_json="${ips_json},"; fi
            ips_json="${ips_json}\"${ip}\""
        done <"${anytls_block_ips_file}"
    fi
    [[ -n "${ips_json}" ]] && _anytls_rules_append "{\"ip_cidr\":[${ips_json}],\"outbound\":\"block\"}"

    if [[ "${anytls_warp_mode}" == "user" ]]; then
        # 用户名校验：配置里的用户名带 v:/a: 前缀，这里对名单里每个用户两个前缀都加，
        # 使 WARP 对该用户的 VMess 与 AnyTLS 流量都生效。
        local warp_users_json="" u
        if [[ -f "${anytls_warp_users_file}" ]]; then
            while read -r u; do
                [[ -z "${u}" ]] && continue
                warp_users_json="${warp_users_json}${warp_users_json:+,}\"v:${u}\",\"a:${u}\""
            done <"${anytls_warp_users_file}"
        fi
        [[ -n "${warp_users_json}" ]] && _anytls_rules_append "{\"auth_user\":[${warp_users_json}],\"outbound\":\"warp\"}"
    fi

    echo "${ANYTLS_ROUTING_RULES}"
}

_anytls_rs_first=1
ANYTLS_ROUTING_RULESET=""

_anytls_rs_append() {
    if [[ ${_anytls_rs_first} -eq 1 ]]; then
        _anytls_rs_first=0
        ANYTLS_ROUTING_RULESET="$1"
    else
        ANYTLS_ROUTING_RULESET="${ANYTLS_ROUTING_RULESET},$1"
    fi
}

anytls_routing_rule_set_gen() {
    ANYTLS_ROUTING_RULESET=""
    _anytls_rs_first=1
    if [[ "${anytls_block_ads}" == "1" ]]; then
        _anytls_rs_append "{\"type\":\"local\",\"tag\":\"geosite-category-ads\",\"format\":\"binary\",\"path\":\"${singbox_conf_dir}/geosite-category-ads.srs\"}"
    fi
    if [[ "${anytls_block_cn}" == "1" ]]; then
        _anytls_rs_append "{\"type\":\"local\",\"tag\":\"geosite-cn\",\"format\":\"binary\",\"path\":\"${singbox_conf_dir}/geosite-cn.srs\"}"
        _anytls_rs_append "{\"type\":\"local\",\"tag\":\"geoip-cn\",\"format\":\"binary\",\"path\":\"${singbox_conf_dir}/geoip-cn.srs\"}"
    fi
    echo "${ANYTLS_ROUTING_RULESET}"
}

singbox_geodata_download() {
    mkdir -p "${singbox_conf_dir}"
    local base_geosite="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set"
    local base_geoip="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set"
    local f
    for f in geosite-category-ads geosite-cn; do
        if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
            -o "${singbox_conf_dir}/${f}.srs" "${base_geosite}/${f}.srs"; then
            echo -e "${Error} ${RedBG} ${f}.srs 下载失败 ${Font}"
            return 1
        fi
    done
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
        -o "${singbox_conf_dir}/geoip-cn.srs" "${base_geoip}/geoip-cn.srs"; then
        echo -e "${Error} ${RedBG} geoip-cn.srs 下载失败 ${Font}"
        return 1
    fi
    judge "sing-box geodata 下载"
}

anytls_routing_ensure_geodata() {
    local f missing=0
    if [[ "${anytls_block_ads}" == "1" ]]; then
        [[ -f "${singbox_conf_dir}/geosite-category-ads.srs" ]] || missing=1
    fi
    if [[ "${anytls_block_cn}" == "1" ]]; then
        [[ -f "${singbox_conf_dir}/geosite-cn.srs" ]] || missing=1
        [[ -f "${singbox_conf_dir}/geoip-cn.srs" ]] || missing=1
    fi
    [[ ${missing} -eq 1 ]] && singbox_geodata_download
}

singbox_geodata_update() {
    if [[ ! -f "${singbox_bin_dir}" ]]; then
        echo -e "${Error} ${RedBG} sing-box 未安装，请先安装 AnyTLS ${Font}"
        return 1
    fi
    singbox_geodata_download
}

anytls_block_domain_list() {
    echo -e "${OK} ${GreenBG} 当前屏蔽域名列表 ${Font}"
    if [[ ! -f "${anytls_block_domains_file}" ]] || [[ ! -s "${anytls_block_domains_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r d; do
        [[ -z "${d}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${d}"
    done <"${anytls_block_domains_file}"
}

anytls_block_domain_add() {
    read -rp "请输入要屏蔽的域名（eg: example.com）:" domain_item
    [[ -z "${domain_item}" ]] && return 1
    if [[ "${domain_item}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 域名不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p "${singbox_conf_dir}"
    echo "${domain_item}" >>"${anytls_block_domains_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "屏蔽域名添加"
}

anytls_block_domain_del() {
    if [[ ! -s "${anytls_block_domains_file}" ]]; then
        echo -e "${Error} ${RedBG} 屏蔽域名列表为空 ${Font}"
        return 1
    fi
    anytls_block_domain_list
    read -rp "请输入要删除的域名:" del_domain
    [[ -z "${del_domain}" ]] && return 1
    sed -i "/^${del_domain}$/d" "${anytls_block_domains_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "屏蔽域名删除"
}

anytls_block_ip_list() {
    echo -e "${OK} ${GreenBG} 当前屏蔽 IP 列表 ${Font}"
    if [[ ! -f "${anytls_block_ips_file}" ]] || [[ ! -s "${anytls_block_ips_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r ip_item; do
        [[ -z "${ip_item}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${ip_item}"
    done <"${anytls_block_ips_file}"
}

anytls_block_ip_add() {
    read -rp "请输入要屏蔽的 IP 或 CIDR（eg: 1.2.3.4 或 10.0.0.0/8）:" ip_item
    [[ -z "${ip_item}" ]] && return 1
    if [[ "${ip_item}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} IP 不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p "${singbox_conf_dir}"
    echo "${ip_item}" >>"${anytls_block_ips_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "屏蔽 IP 添加"
}

anytls_block_ip_del() {
    if [[ ! -s "${anytls_block_ips_file}" ]]; then
        echo -e "${Error} ${RedBG} 屏蔽 IP 列表为空 ${Font}"
        return 1
    fi
    anytls_block_ip_list
    read -rp "请输入要删除的 IP 或 CIDR:" del_ip
    [[ -z "${del_ip}" ]] && return 1
    sed -i "/^${del_ip}$/d" "${anytls_block_ips_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "屏蔽 IP 删除"
}

anytls_block_domain_menu() {
    while true; do
        clear_screen
        echo -e "\t 禁止自定义域名"
        echo -e "${Green}1.${Font} 查看屏蔽域名列表"
        echo -e "${Green}2.${Font} 添加屏蔽域名"
        echo -e "${Green}3.${Font} 删除屏蔽域名"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" bd_num
        case ${bd_num} in
        1)
            anytls_block_domain_list
            ;;
        2)
            anytls_block_domain_add
            ;;
        3)
            anytls_block_domain_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

anytls_block_ip_menu() {
    while true; do
        clear_screen
        echo -e "\t 禁止自定义 IP"
        echo -e "${Green}1.${Font} 查看屏蔽 IP 列表"
        echo -e "${Green}2.${Font} 添加屏蔽 IP"
        echo -e "${Green}3.${Font} 删除屏蔽 IP"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" bi_num
        case ${bi_num} in
        1)
            anytls_block_ip_list
            ;;
        2)
            anytls_block_ip_add
            ;;
        3)
            anytls_block_ip_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

anytls_warp_user_list() {
    echo -e "${OK} ${GreenBG} 当前 AnyTLS WARP 用户列表（仅 user 模式生效）${Font}"
    if [[ ! -f "${anytls_warp_users_file}" ]] || [[ ! -s "${anytls_warp_users_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r u; do
        [[ -z "${u}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${u}"
    done <"${anytls_warp_users_file}"
}

anytls_warp_user_add() {
    read -rp "请输入要走 WARP 的用户名（需与 AnyTLS 用户名一致）:" warp_user
    [[ -z "${warp_user}" ]] && return 1
    if [[ "${warp_user}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p "${singbox_conf_dir}"
    echo "${warp_user}" >>"${anytls_warp_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS WARP 用户添加"
}

anytls_warp_user_del() {
    if [[ ! -s "${anytls_warp_users_file}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS WARP 用户列表为空 ${Font}"
        return 1
    fi
    anytls_warp_user_list
    read -rp "请输入要删除的用户名:" del_user
    [[ -z "${del_user}" ]] && return 1
    sed -i "/^${del_user}$/d" "${anytls_warp_users_file}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS WARP 用户删除"
}

anytls_warp_user_menu() {
    while true; do
        clear_screen
        echo -e "\t 管理 AnyTLS WARP 用户"
        echo -e "${Green}1.${Font} 查看 WARP 用户列表"
        echo -e "${Green}2.${Font} 添加 WARP 用户"
        echo -e "${Green}3.${Font} 删除 WARP 用户"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" wu_num
        case ${wu_num} in
        1)
            anytls_warp_user_list
            ;;
        2)
            anytls_warp_user_add
            ;;
        3)
            anytls_warp_user_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

anytls_routing_menu() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        pause_continue
        return 1
    fi
    while true; do
        clear_screen
        anytls_routing_load
        local cn_s="关" ads_s="关" bt_s="关" warp_s="off(直连)"
        [[ "${anytls_block_cn}" == "1" ]] && cn_s="开"
        [[ "${anytls_block_ads}" == "1" ]] && ads_s="开"
        [[ "${anytls_block_bt}" == "1" ]] && bt_s="开"
        [[ "${anytls_warp_mode}" == "all" ]] && warp_s="all(全量WARP)"
        [[ "${anytls_warp_mode}" == "user" ]] && warp_s="user(指定用户)"
        echo -e "\t 路由规则（屏蔽）"
        echo -e "${Green}1.${Font} 禁止国内地址  [${cn_s}]"
        echo -e "${Green}2.${Font} 禁止广告地址  [${ads_s}]"
        echo -e "${Green}3.${Font} 禁止 BT 协议  [${bt_s}]"
        echo -e "${Green}4.${Font} 禁止自定义域名"
        echo -e "${Green}5.${Font} 禁止自定义 IP"
        echo -e "${Green}6.${Font} WARP 出站模式  [${warp_s}]"
        echo -e "${Green}7.${Font} 管理 WARP 用户"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" routing_num
        case ${routing_num} in
        1)
            if [[ "${anytls_block_cn}" == "1" ]]; then anytls_block_cn=0; else anytls_block_cn=1; fi
            anytls_routing_save
            anytls_conf_add
            systemctl restart sing-box
            judge "禁止国内地址 切换"
            ;;
        2)
            if [[ "${anytls_block_ads}" == "1" ]]; then anytls_block_ads=0; else anytls_block_ads=1; fi
            anytls_routing_save
            anytls_conf_add
            systemctl restart sing-box
            judge "禁止广告地址 切换"
            ;;
        3)
            if [[ "${anytls_block_bt}" == "1" ]]; then anytls_block_bt=0; else anytls_block_bt=1; fi
            anytls_routing_save
            anytls_conf_add
            systemctl restart sing-box
            judge "禁止 BT 协议 切换"
            ;;
        4)
            anytls_block_domain_menu
            continue
            ;;
        5)
            anytls_block_ip_menu
            continue
            ;;
        6)
            case "${anytls_warp_mode}" in
            off) anytls_warp_mode="all" ;;
            all) anytls_warp_mode="user" ;;
            *) anytls_warp_mode="off" ;;
            esac
            if [[ "${anytls_warp_mode}" != "off" ]] && ! warp_installed; then
                echo -e "${Error} ${RedBG} WARP 未安装，请先在「安装与升级 → WARP」中安装，否则出站将失败 ${Font}"
            fi
            anytls_routing_save
            anytls_conf_add
            systemctl restart sing-box
            judge "AnyTLS WARP 出站模式 切换"
            ;;
        7)
            anytls_warp_user_menu
            continue
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

singbox_conf_add() {
    # 伪装路径沿用 QR 配置（若存在）
    local ws_path="${camouflage}"
    [[ -f "${v2ray_qr_config_file}" ]] && ws_path="$(grep '\"path\"' "${v2ray_qr_config_file}" | awk -F '"' '{print $4}')"
    [[ -n "${ws_path}" ]] && camouflage="${ws_path}"

    # AnyTLS 用户
    local anytls_users_json="" name password first=1
    if [[ -s "${anytls_users_file}" ]]; then
        while read -r name password; do
            [[ -z "${name}" ]] && continue
            if [[ ${first} -eq 1 ]]; then first=0; else anytls_users_json="${anytls_users_json},"; fi
            anytls_users_json="${anytls_users_json}{\"name\":\"a:${name}\",\"password\":\"${password}\"}"
        done <"${anytls_users_file}"
    fi

    # VMess 用户：由 sing-box 承载，TLS/WS 仍由 Nginx 终止与反代
    local vmess_users_json="" vname vuuid vfirst=1 vmess_inbound=""
    if [[ -s "${vmess_users_file}" ]]; then
        while read -r vname vuuid; do
            [[ -z "${vname}" ]] && continue
            if [[ ${vfirst} -eq 1 ]]; then vfirst=0; else vmess_users_json="${vmess_users_json},"; fi
            vmess_users_json="${vmess_users_json}{\"name\":\"v:${vname}\",\"uuid\":\"${vuuid}\"}"
        done <"${vmess_users_file}"
        if [[ -n "${vmess_users_json}" ]]; then
            local vmess_port=""
            [[ -f "${singbox_vmess_port_file}" ]] && vmess_port="$(cat "${singbox_vmess_port_file}")"
            [[ -z "${vmess_port}" ]] && vmess_port=$((RANDOM + 20000))
            echo "${vmess_port}" >"${singbox_vmess_port_file}"
            PORT="${vmess_port}"
            vmess_inbound="{\"type\":\"vmess\",\"tag\":\"vmess-in\",\"listen\":\"127.0.0.1\",\"listen_port\":${vmess_port},\"users\":[${vmess_users_json}],\"transport\":{\"type\":\"ws\",\"path\":\"${camouflage}\"}}"
        fi
    fi

    # AnyTLS 端口：优先用调用方传入的全局值，其次读端口文件，最后默认 8443。
    # 注意：不能再从 config.json 里 awk 解析——两个入口在同一行，会解析出错误字符串。
    if [[ -z "${anytls_port}" && -f "${singbox_anytls_port_file}" ]]; then
        anytls_port="$(cat "${singbox_anytls_port_file}")"
    fi
    [[ ! "${anytls_port}" =~ ^[0-9]+$ ]] && anytls_port="8443"
    mkdir -p "${singbox_conf_dir}"
    echo "${anytls_port}" >"${singbox_anytls_port_file}"

    local anytls_inbound=""
    if [[ -n "${anytls_users_json}" ]]; then
        anytls_inbound="{\"type\":\"anytls\",\"tag\":\"anytls-in\",\"listen\":\"::\",\"listen_port\":${anytls_port},\"users\":[${anytls_users_json}],\"tls\":{\"enabled\":true,\"certificate_path\":\"/data/v2ray.crt\",\"key_path\":\"/data/v2ray.key\"}}"
    fi

    local inbounds_json="${vmess_inbound}"
    if [[ -n "${anytls_inbound}" ]]; then
        [[ -n "${inbounds_json}" ]] && inbounds_json="${inbounds_json},"
        inbounds_json="${inbounds_json}${anytls_inbound}"
    fi

    anytls_routing_load
    anytls_routing_ensure_geodata
    local routing_rules_json rule_set_json route_final="direct"
    routing_rules_json="$(anytls_routing_rules_gen)"
    rule_set_json="$(anytls_routing_rule_set_gen)"
    [[ "${anytls_warp_mode}" == "all" ]] && route_final="warp"

    local panel_log_output="" panel_experimental=""
    if panel_installed; then
        panel_log_output=",
    \"output\": \"${singbox_log_file}\""
    fi
    if panel_installed && singbox_has_v2ray_api; then
        local stats_users_json="" su first_su=1 stats_inbounds_json=""
        if [[ -n "${vmess_users_json}" ]]; then
            stats_inbounds_json="\"vmess-in\""
        fi
        if [[ -n "${anytls_users_json}" ]]; then
            [[ -n "${stats_inbounds_json}" ]] && stats_inbounds_json="${stats_inbounds_json},"
            stats_inbounds_json="${stats_inbounds_json}\"anytls-in\""
        fi
        # 用户名按协议加前缀（v:/a:），使 sing-box 的 user>>> 计数器按协议独立，
        # 从而能精确统计「某用户在某协议的流量」；面板读取时去掉前缀还原显示名。
        if [[ -s "${anytls_users_file}" ]]; then
            while read -r su _; do
                [[ -z "${su}" ]] && continue
                if [[ ${first_su} -eq 1 ]]; then first_su=0; else stats_users_json="${stats_users_json},"; fi
                stats_users_json="${stats_users_json}\"a:${su}\""
            done <"${anytls_users_file}"
        fi
        if [[ -s "${vmess_users_file}" ]]; then
            while read -r su _; do
                [[ -z "${su}" ]] && continue
                if [[ ${first_su} -eq 1 ]]; then first_su=0; else stats_users_json="${stats_users_json},"; fi
                stats_users_json="${stats_users_json}\"v:${su}\""
            done <"${vmess_users_file}"
        fi
        panel_experimental=$(
            cat <<PANEL_EXP
,
  "experimental": {
    "v2ray_api": {
      "listen": "127.0.0.1:${panel_singbox_api_port}",
      "stats": {
        "enabled": true,
        "inbounds": [${stats_inbounds_json}],
        "outbounds": ["direct", "block", "warp"],
        "users": [${stats_users_json}]
      }
    },
    "clash_api": {
      "external_controller": "127.0.0.1:${panel_clash_api_port}"
    }
  }
PANEL_EXP
        )
    fi

    cat >${singbox_conf} <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true${panel_log_output}
  },
  "inbounds": [
    ${inbounds_json}
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" },
    { "type": "socks", "tag": "warp", "server": "127.0.0.1", "server_port": ${warp_socks_port}, "version": "5" }
  ],
  "route": {
    "rule_set": [
      ${rule_set_json}
    ],
    "rules": [
      ${routing_rules_json}
    ],
    "final": "${route_final}"
  }${panel_experimental}
}
EOF
    judge "sing-box 配置写入"
}
anytls_conf_add() { singbox_conf_add; }
v2ray_conf_add() { singbox_conf_add; }

surge_config_output() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    if [[ -z "${anytls_port}" && -f "${singbox_anytls_port_file}" ]]; then
        anytls_port="$(cat "${singbox_anytls_port_file}")"
    fi
    [[ ! "${anytls_port}" =~ ^[0-9]+$ ]] && anytls_port="8443"
    local domain=""
    [[ -f "${anytls_domain_file}" ]] && domain="$(cat ${anytls_domain_file})"
    [[ -z "${domain}" && -f "${v2ray_qr_config_file}" ]] && domain="$(grep '\"add\"' ${v2ray_qr_config_file} | awk -F '"' '{print $4}')"

    {
        echo -e "${OK} ${GreenBG} AnyTLS 安装成功"
        echo -e "${Red} AnyTLS 配置信息 ${Font}"
        echo -e "${Red} 地址（address）:${Font} ${domain}"
        echo -e "${Red} 端口（port）：${Font} ${anytls_port}"
        echo -e "${Red} SNI：${Font} ${domain}"
        echo -e ""
        echo -e "${Red} Surge 配置（iOS 5.17.0+ / Mac 6.4.3+）${Font}"
        echo -e "[Proxy]"
        while read -r name password; do
            [[ -z "${name}" ]] && continue
            echo -e "AnyTLS-${name} = anytls, ${domain}, ${anytls_port}, password=${password}, sni=${domain}, reuse=true"
        done <"${anytls_users_file}"
        echo -e ""
        echo -e "${Red} 其他客户端 URI ${Font}"
        while read -r name password; do
            [[ -z "${name}" ]] && continue
            echo -e "anytls://${password}@${domain}:${anytls_port}?sni=${domain}#AnyTLS-${name}"
        done <"${anytls_users_file}"
    } >"${anytls_info_file}"

    cat "${anytls_info_file}"
}

anytls_port_change() {
    if [[ ! -f ${singbox_conf} ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    read -rp "请输入新的 AnyTLS 端口:" anytls_port
    port_exist_check "${anytls_port}"
    anytls_conf_add
    systemctl restart sing-box
    judge "AnyTLS 端口变更"
    surge_config_output
}

nginx_exist_check() {
    if [[ -f "/etc/nginx/sbin/nginx" ]]; then
        echo -e "${OK} ${GreenBG} Nginx已存在，跳过编译安装过程 ${Font}"
        sleep 2
    elif [[ -d "/usr/local/nginx/" ]]; then
        echo -e "${OK} ${GreenBG} 检测到其他套件安装的Nginx，继续安装会造成冲突，请处理后安装${Font}"
        exit 1
    else
        nginx_install
    fi
}

nginx_install() {
    #    if [[ -d "/etc/nginx" ]];then
    #        rm -rf /etc/nginx
    #    fi

    wget -nc --no-check-certificate http://nginx.org/download/nginx-${nginx_version}.tar.gz -P ${nginx_openssl_src}
    judge "Nginx 下载"
    wget -nc --no-check-certificate https://www.openssl.org/source/openssl-${openssl_version}.tar.gz -P ${nginx_openssl_src}
    judge "openssl 下载"
    wget -nc --no-check-certificate https://github.com/jemalloc/jemalloc/releases/download/${jemalloc_version}/jemalloc-${jemalloc_version}.tar.bz2 -P ${nginx_openssl_src}
    judge "jemalloc 下载"

    cd ${nginx_openssl_src} || exit

    [[ -d nginx-"$nginx_version" ]] && rm -rf nginx-"$nginx_version"
    tar -zxvf nginx-"$nginx_version".tar.gz

    [[ -d openssl-"$openssl_version" ]] && rm -rf openssl-"$openssl_version"
    tar -zxvf openssl-"$openssl_version".tar.gz

    [[ -d jemalloc-"${jemalloc_version}" ]] && rm -rf jemalloc-"${jemalloc_version}"
    tar -xvf jemalloc-"${jemalloc_version}".tar.bz2

    [[ -d "$nginx_dir" ]] && rm -rf ${nginx_dir}

    echo -e "${OK} ${GreenBG} 即将开始编译安装 jemalloc ${Font}"
    sleep 2

    cd jemalloc-${jemalloc_version} || exit
    ./configure
    judge "编译检查"
    make -j "${THREAD}" && make install
    judge "jemalloc 编译安装"
    echo '/usr/local/lib' >/etc/ld.so.conf.d/local.conf
    ldconfig

    echo -e "${OK} ${GreenBG} 即将开始编译安装 Nginx, 过程稍久，请耐心等待 ${Font}"
    sleep 4

    cd ../nginx-${nginx_version} || exit

    ./configure --prefix="${nginx_dir}" \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_secure_link_module \
        --with-http_v2_module \
        --with-cc-opt='-O3' \
        --with-ld-opt="-ljemalloc" \
        --with-openssl=../openssl-"$openssl_version"
    judge "编译检查"
    make -j "${THREAD}" && make install
    judge "Nginx 编译安装"

    ln -sf /etc/nginx/sbin/nginx /usr/local/sbin/nginx

    # 修改基本配置
    sed -i 's/#user  nobody;/user  root;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/worker_processes  1;/worker_processes  3;/' ${nginx_dir}/conf/nginx.conf
    sed -i 's/    worker_connections  1024;/    worker_connections  4096;/' ${nginx_dir}/conf/nginx.conf
    sed -i '$i include conf.d/*.conf;' ${nginx_dir}/conf/nginx.conf

    # 删除临时文件
    rm -rf ../nginx-"${nginx_version}"
    rm -rf ../openssl-"${openssl_version}"
    rm -rf ../nginx-"${nginx_version}".tar.gz
    rm -rf ../openssl-"${openssl_version}".tar.gz

    # 添加配置文件夹，适配旧版脚本
    mkdir ${nginx_dir}/conf/conf.d
}

ssl_install() {
    if [[ "${ID}" == "centos" ]]; then
        ${INS} install socat nc -y
	elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 12 ]]; then
		${INS} install socat netcat-openbsd -y
    else
        ${INS} install socat netcat -y
    fi
    judge "安装 SSL 证书生成脚本依赖"

    curl https://get.acme.sh | sh
    judge "安装 SSL 证书生成脚本"
}

domain_check() {
    read -rp "请输入你的域名信息(eg:www.example.com):" domain
    domain_ipv4="$(dig +short "${domain}" a)"
    domain_ipv6="$(dig +short "${domain}" aaaa)"
    echo -e "${OK} ${GreenBG} 正在获取 公网ip 信息，请耐心等待 ${Font}"
    wgcfv4_status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv6_status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ${wgcfv4_status} =~ on|plus ]] || [[ ${wgcfv6_status} =~ on|plus ]]; then
        # 关闭wgcf-warp，以防误判VPS IP情况
        wg-quick down wgcf >/dev/null 2>&1
        echo -e "${OK} ${GreenBG} 已关闭 wgcf-warp ${Font}"
    fi
    local_ipv4=$(curl -s4m8 http://ip.sb)
    local_ipv6=$(curl -s6m8 http://ip.sb)
    if [[ -z ${local_ipv4} && -n ${local_ipv6} ]]; then
        echo -e nameserver 2a01:4f8:c2c:123f::1 > /etc/resolv.conf
        echo -e "${OK} ${GreenBG} 识别为 IPv6 Only 的 VPS，自动添加 DNS64 服务器 ${Font}"
    fi
    echo -e "域名 DNS 解析到的 IPv4：${domain_ipv4}"
    echo -e "域名 DNS 解析到的 IPv6：${domain_ipv6}"
    echo -e "本机IPv4: ${local_ipv4}"
    echo -e "本机IPv6: ${local_ipv6}"
    sleep 2
    if [[ ${domain_ipv4} == ${local_ipv4} ]]; then
        echo -e "${OK} ${GreenBG} 域名 DNS 解析 IP 与 本机 IPv4 匹配 ${Font}"
        sleep 2
    elif [[ ${domain_ipv6} == ${local_ipv6} ]]; then
        echo -e "${OK} ${GreenBG} 域名 DNS 解析 IP 与 本机 IPv6 匹配 ${Font}"
        sleep 2
    else
        echo -e "${Error} ${RedBG} 请确保域名添加了正确的 A / AAAA 记录，否则将无法正常使用 V2ray ${Font}"
        echo -e "${Error} ${RedBG} 域名 DNS 解析 IP 与 本机 IPv4 / IPv6 不匹配 是否继续安装？（y/n）${Font}" && read -r install
        case $install in
        [yY][eE][sS] | [yY])
            echo -e "${GreenBG} 继续安装 ${Font}"
            sleep 2
            ;;
        *)
            echo -e "${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用，以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        echo -e "${OK} ${GreenBG} 5s 后将尝试自动 kill 占用进程 ${Font}"
        sleep 5
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
        sleep 1
    fi
}
acme() {
    "$HOME"/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    if "$HOME"/.acme.sh/acme.sh --issue -d "${domain}" --standalone -k ec-256 --force; then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        sleep 2
        mkdir /data
        if "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc --force; then
            echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
            sleep 2
            if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
                echo -e "${OK} ${GreenBG} 已启动 wgcf-warp ${Font}"
            fi
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
            wg-quick up wgcf >/dev/null 2>&1
            echo -e "${OK} ${GreenBG} 已启动 wgcf-warp ${Font}"
        fi
        exit 1
    fi
}

vmess_users_ensure() {
    if [[ ! -f "${vmess_users_file}" ]]; then
        mkdir -p /etc/v2ray
        local existing_uuid=""
        if [[ -f "${v2ray_qr_config_file}" ]]; then
            existing_uuid="$(info_extraction '\"id\"')"
        fi
        [[ -z "${existing_uuid}" ]] && existing_uuid="$(cat /proc/sys/kernel/random/uuid)"
        echo "vmess ${existing_uuid}" >"${vmess_users_file}"
    fi
}

vmess_user_list() {
    vmess_users_ensure
    echo -e "${OK} ${GreenBG} 当前 VMess 用户列表 ${Font}"
    local idx=0
    while read -r name uuid; do
        [[ -z "${name}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} 名称: ${name}   UUID: ${uuid}"
    done <"${vmess_users_file}"
}

vmess_user_add() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    vmess_users_ensure
    local next_num=1
    while grep -q "^user${next_num} " "${vmess_users_file}"; do
        next_num=$((next_num + 1))
    done
    read -rp "请输入用户名（default:user${next_num}）:" user_name
    [[ -z "${user_name}" ]] && user_name="user${next_num}"
    check_user_name "${user_name}" || return 1
    if grep -q "^${user_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${user_name} 已存在 ${Font}"
        return 1
    fi
    confirm_cross_protocol_name "${user_name}" "${anytls_users_file}" "AnyTLS" || return 1
    echo "${user_name} $(cat /proc/sys/kernel/random/uuid)" >>"${vmess_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "VMess 用户添加"
    v2ray_config_output
}

vmess_user_del() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    vmess_users_ensure
    vmess_user_list
    local count
    count="$(wc -l <"${vmess_users_file}")"
    if [[ "${count}" -le 1 ]]; then
        echo -e "${Error} ${RedBG} 至少保留一个用户，无法删除 ${Font}"
        return 1
    fi
    read -rp "请输入要删除的用户名:" del_name
    [[ -z "${del_name}" ]] && return 1
    if ! grep -q "^${del_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${del_name} 不存在 ${Font}"
        return 1
    fi
    sed -i "/^${del_name} /d" "${vmess_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "VMess 用户删除"
    v2ray_config_output
}

vmess_user_uuid() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    vmess_users_ensure
    vmess_user_list
    read -rp "请输入要更换 UUID 的用户名:" chg_name
    [[ -z "${chg_name}" ]] && return 1
    if ! grep -q "^${chg_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${chg_name} 不存在 ${Font}"
        return 1
    fi
    sed -i "s/^${chg_name} .*/${chg_name} $(cat /proc/sys/kernel/random/uuid)/" "${vmess_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "VMess 用户 UUID 更换"
    v2ray_config_output
}

vmess_user_rename() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    vmess_users_ensure
    vmess_user_list
    read -rp "请输入要修改的用户名:" old_name
    [[ -z "${old_name}" ]] && return 1
    if ! grep -q "^${old_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${old_name} 不存在 ${Font}"
        return 1
    fi
    read -rp "请输入新的用户名:" new_name
    [[ -z "${new_name}" ]] && return 1
    check_user_name "${new_name}" || return 1
    if grep -q "^${new_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${new_name} 已存在 ${Font}"
        return 1
    fi
    confirm_cross_protocol_name "${new_name}" "${anytls_users_file}" "AnyTLS" || return 1
    local old_uuid
    old_uuid="$(grep "^${old_name} " "${vmess_users_file}" | head -1 | awk '{print $2}')"
    sed -i "/^${old_name} /d" "${vmess_users_file}"
    echo "${new_name} ${old_uuid}" >>"${vmess_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "VMess 用户名修改"
    v2ray_config_output
}

vmess_user_menu() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        pause_continue
        return 1
    fi
    while true; do
        clear_screen
        echo -e "\t VMess 用户管理"
        echo -e "${Green}1.${Font} 查看用户列表"
        echo -e "${Green}2.${Font} 添加用户"
        echo -e "${Green}3.${Font} 删除用户"
        echo -e "${Green}4.${Font} 更换用户 UUID"
        echo -e "${Green}5.${Font} 修改用户名"
        echo -e "${Green}6.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" user_menu_num
        case ${user_menu_num} in
        1)
            vmess_user_list
            ;;
        2)
            vmess_user_add
            ;;
        3)
            vmess_user_del
            ;;
        4)
            vmess_user_uuid
            ;;
        5)
            vmess_user_rename
            ;;
        6)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

routing_load() {
    block_cn=0
    block_ads=0
    block_bt=1
    warp_mode="off"
    if [[ -f "${routing_conf_file}" ]]; then
        block_cn="$(grep '^block_cn=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
        block_ads="$(grep '^block_ads=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
        block_bt="$(grep '^block_bt=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
        warp_mode="$(grep '^warp_mode=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
    fi
    [[ -z "${block_cn}" ]] && block_cn=0
    [[ -z "${block_ads}" ]] && block_ads=0
    [[ -z "${block_bt}" ]] && block_bt=1
    [[ "${warp_mode}" != "all" && "${warp_mode}" != "user" ]] && warp_mode="off"
}

routing_save() {
    mkdir -p /etc/v2ray
    cat >"${routing_conf_file}" <<EOF
block_cn=${block_cn}
block_ads=${block_ads}
block_bt=${block_bt}
warp_mode=${warp_mode}
EOF
}

_rules_first=1
ROUTING_RULES=""

_rules_append() {
    if [[ ${_rules_first} -eq 1 ]]; then
        _rules_first=0
        ROUTING_RULES="$1"
    else
        ROUTING_RULES="${ROUTING_RULES},$1"
    fi
}

routing_rules_gen() {
    ROUTING_RULES=""
    _rules_first=1

    if [[ "${block_bt}" == "1" ]]; then
        _rules_append '{"type":"field","protocol":["bittorrent"],"outboundTag":"blocked"}'
    fi
    if [[ "${block_ads}" == "1" ]]; then
        _rules_append '{"type":"field","domains":["geosite:category-ads"],"outboundTag":"blocked"}'
    fi
    if [[ "${block_cn}" == "1" ]]; then
        _rules_append '{"type":"field","domains":["geosite:cn"],"outboundTag":"blocked"}'
        _rules_append '{"type":"field","ip":["geoip:cn"],"outboundTag":"blocked"}'
    fi

    local domains_json="" d first_d=1
    if [[ -f "${block_domains_file}" ]]; then
        while read -r d; do
            [[ -z "${d}" ]] && continue
            if [[ ${first_d} -eq 1 ]]; then first_d=0; else domains_json="${domains_json},"; fi
            domains_json="${domains_json}\"domain:${d}\""
        done <"${block_domains_file}"
    fi
    [[ -n "${domains_json}" ]] && _rules_append "{\"type\":\"field\",\"domains\":[${domains_json}],\"outboundTag\":\"blocked\"}"

    local ips_json="" ip first_i=1
    if [[ -f "${block_ips_file}" ]]; then
        while read -r ip; do
            [[ -z "${ip}" ]] && continue
            if [[ ${first_i} -eq 1 ]]; then first_i=0; else ips_json="${ips_json},"; fi
            ips_json="${ips_json}\"${ip}\""
        done <"${block_ips_file}"
    fi
    [[ -n "${ips_json}" ]] && _rules_append "{\"type\":\"field\",\"ip\":[${ips_json}],\"outboundTag\":\"blocked\"}"

    if [[ "${warp_mode}" == "all" ]]; then
        _rules_append '{"type":"field","network":"tcp,udp","outboundTag":"warp"}'
    elif [[ "${warp_mode}" == "user" ]]; then
        local warp_users_json="" u first_u=1
        if [[ -f "${warp_users_file}" ]]; then
            while read -r u; do
                [[ -z "${u}" ]] && continue
                if [[ ${first_u} -eq 1 ]]; then first_u=0; else warp_users_json="${warp_users_json},"; fi
                warp_users_json="${warp_users_json}\"${u}\""
            done <"${warp_users_file}"
        fi
        [[ -n "${warp_users_json}" ]] && _rules_append "{\"type\":\"field\",\"user\":[${warp_users_json}],\"outboundTag\":\"warp\"}"
    fi

    echo "${ROUTING_RULES}"
}

routing_domain_strategy() {
    if [[ "${block_cn}" == "1" ]] || [[ -s "${block_ips_file}" ]]; then
        echo "IPIfNonMatch"
    else
        echo "AsIs"
    fi
}

routing_sniffing_gen() {
    if [[ "${block_bt}" == "1" ]]; then
        echo '      "sniffing": { "enabled": true },'
    fi
}

block_domain_list() {
    echo -e "${OK} ${GreenBG} 当前屏蔽域名列表 ${Font}"
    if [[ ! -f "${block_domains_file}" ]] || [[ ! -s "${block_domains_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r d; do
        [[ -z "${d}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${d}"
    done <"${block_domains_file}"
}

block_domain_add() {
    read -rp "请输入要屏蔽的域名（eg: example.com）:" domain_item
    [[ -z "${domain_item}" ]] && return 1
    if [[ "${domain_item}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 域名不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p /etc/v2ray
    echo "${domain_item}" >>"${block_domains_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "屏蔽域名添加"
}

block_domain_del() {
    if [[ ! -s "${block_domains_file}" ]]; then
        echo -e "${Error} ${RedBG} 屏蔽域名列表为空 ${Font}"
        return 1
    fi
    block_domain_list
    read -rp "请输入要删除的域名:" del_domain
    [[ -z "${del_domain}" ]] && return 1
    sed -i "/^${del_domain}$/d" "${block_domains_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "屏蔽域名删除"
}

block_ip_list() {
    echo -e "${OK} ${GreenBG} 当前屏蔽 IP 列表 ${Font}"
    if [[ ! -f "${block_ips_file}" ]] || [[ ! -s "${block_ips_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r ip_item; do
        [[ -z "${ip_item}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${ip_item}"
    done <"${block_ips_file}"
}

block_ip_add() {
    read -rp "请输入要屏蔽的 IP 或 CIDR（eg: 1.2.3.4 或 10.0.0.0/8）:" ip_item
    [[ -z "${ip_item}" ]] && return 1
    if [[ "${ip_item}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} IP 不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p /etc/v2ray
    echo "${ip_item}" >>"${block_ips_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "屏蔽 IP 添加"
}

block_ip_del() {
    if [[ ! -s "${block_ips_file}" ]]; then
        echo -e "${Error} ${RedBG} 屏蔽 IP 列表为空 ${Font}"
        return 1
    fi
    block_ip_list
    read -rp "请输入要删除的 IP 或 CIDR:" del_ip
    [[ -z "${del_ip}" ]] && return 1
    sed -i "/^${del_ip}$/d" "${block_ips_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "屏蔽 IP 删除"
}

block_domain_menu() {
    while true; do
        clear_screen
        echo -e "\t 禁止自定义域名"
        echo -e "${Green}1.${Font} 查看屏蔽域名列表"
        echo -e "${Green}2.${Font} 添加屏蔽域名"
        echo -e "${Green}3.${Font} 删除屏蔽域名"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" bd_num
        case ${bd_num} in
        1)
            block_domain_list
            ;;
        2)
            block_domain_add
            ;;
        3)
            block_domain_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

block_ip_menu() {
    while true; do
        clear_screen
        echo -e "\t 禁止自定义 IP"
        echo -e "${Green}1.${Font} 查看屏蔽 IP 列表"
        echo -e "${Green}2.${Font} 添加屏蔽 IP"
        echo -e "${Green}3.${Font} 删除屏蔽 IP"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" bi_num
        case ${bi_num} in
        1)
            block_ip_list
            ;;
        2)
            block_ip_add
            ;;
        3)
            block_ip_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

warp_user_list() {
    echo -e "${OK} ${GreenBG} 当前 WARP 用户列表（仅 user 模式生效）${Font}"
    if [[ ! -f "${warp_users_file}" ]] || [[ ! -s "${warp_users_file}" ]]; then
        echo -e "${Red} 无 ${Font}"
        return 0
    fi
    local idx=0
    while read -r u; do
        [[ -z "${u}" ]] && continue
        idx=$((idx + 1))
        echo -e "${Green}${idx}.${Font} ${u}"
    done <"${warp_users_file}"
}

warp_user_add() {
    read -rp "请输入要走 WARP 的用户名（需与 VMess 用户名一致）:" warp_user
    [[ -z "${warp_user}" ]] && return 1
    if [[ "${warp_user}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含空格 ${Font}"
        return 1
    fi
    mkdir -p /etc/v2ray
    echo "${warp_user}" >>"${warp_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "WARP 用户添加"
}

warp_user_del() {
    if [[ ! -s "${warp_users_file}" ]]; then
        echo -e "${Error} ${RedBG} WARP 用户列表为空 ${Font}"
        return 1
    fi
    warp_user_list
    read -rp "请输入要删除的用户名:" del_user
    [[ -z "${del_user}" ]] && return 1
    sed -i "/^${del_user}$/d" "${warp_users_file}"
    v2ray_conf_add
    systemctl restart sing-box
    judge "WARP 用户删除"
}

warp_user_menu() {
    while true; do
        clear_screen
        echo -e "\t 管理 WARP 用户"
        echo -e "${Green}1.${Font} 查看 WARP 用户列表"
        echo -e "${Green}2.${Font} 添加 WARP 用户"
        echo -e "${Green}3.${Font} 删除 WARP 用户"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" wu_num
        case ${wu_num} in
        1)
            warp_user_list
            ;;
        2)
            warp_user_add
            ;;
        3)
            warp_user_del
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

routing_menu() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        pause_continue
        return 1
    fi
    while true; do
        clear_screen
        routing_load
        local cn_s="关" ads_s="关" bt_s="关" warp_s="off(直连)"
        [[ "${block_cn}" == "1" ]] && cn_s="开"
        [[ "${block_ads}" == "1" ]] && ads_s="开"
        [[ "${block_bt}" == "1" ]] && bt_s="开"
        [[ "${warp_mode}" == "all" ]] && warp_s="all(全量WARP)"
        [[ "${warp_mode}" == "user" ]] && warp_s="user(指定用户)"
        echo -e "\t 路由规则（屏蔽）"
        echo -e "${Green}1.${Font} 禁止国内地址  [${cn_s}]"
        echo -e "${Green}2.${Font} 禁止广告地址  [${ads_s}]"
        echo -e "${Green}3.${Font} 禁止 BT 协议  [${bt_s}]"
        echo -e "${Green}4.${Font} 禁止自定义域名"
        echo -e "${Green}5.${Font} 禁止自定义 IP"
        echo -e "${Green}6.${Font} WARP 出站模式  [${warp_s}]"
        echo -e "${Green}7.${Font} 管理 WARP 用户"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" routing_num
        case ${routing_num} in
        1)
            if [[ "${block_cn}" == "1" ]]; then block_cn=0; else block_cn=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart sing-box
            judge "禁止国内地址 切换"
            ;;
        2)
            if [[ "${block_ads}" == "1" ]]; then block_ads=0; else block_ads=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart sing-box
            judge "禁止广告地址 切换"
            ;;
        3)
            if [[ "${block_bt}" == "1" ]]; then block_bt=0; else block_bt=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart sing-box
            judge "禁止 BT 协议 切换"
            ;;
        4)
            block_domain_menu
            continue
            ;;
        5)
            block_ip_menu
            continue
            ;;
        6)
            case "${warp_mode}" in
            off) warp_mode="all" ;;
            all) warp_mode="user" ;;
            *) warp_mode="off" ;;
            esac
            if [[ "${warp_mode}" != "off" ]] && ! warp_installed; then
                echo -e "${Error} ${RedBG} WARP 未安装，请先在「安装与升级 → WARP」中安装，否则出站将失败 ${Font}"
            fi
            routing_save
            v2ray_conf_add
            systemctl restart sing-box
            judge "WARP 出站模式 切换"
            ;;
        7)
            warp_user_menu
            continue
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

# 原 v2ray_conf_add 已删除：VMess 现由 sing-box 承载，
# v2ray_conf_add 是 singbox_conf_add 的别名（见文件上方定义）。

old_config_exist_check() {
    if [[ -f $v2ray_qr_config_file ]]; then
        echo -e "${OK} ${GreenBG} 检测到旧配置文件，是否读取旧文件配置 [Y/N]? ${Font}"
        read -r ssl_delete
        case $ssl_delete in
        [yY][eE][sS] | [yY])
            echo -e "${OK} ${GreenBG} 已保留旧配置  ${Font}"
            old_config_status="on"
            port=$(info_extraction '\"port\"')
            ;;
        *)
            rm -rf $v2ray_qr_config_file
            echo -e "${OK} ${GreenBG} 已删除旧配置  ${Font}"
            ;;
        esac
    fi
}

nginx_conf_add() {
    touch ${nginx_conf_dir}/v2ray.conf
    cat >${nginx_conf_dir}/v2ray.conf <<EOF
     server {
        listen 443 ssl;
        listen [::]:443 ssl;
        ssl_certificate       /data/v2ray.crt;
        ssl_certificate_key   /data/v2ray.key;
        ssl_protocols         TLSv1.3;
        ssl_ciphers           TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:ECDHE+CHACHA20:ECDHE+ECDSA+AES128:ECDHE+RSA+AES128:RSA+AES128:ECDHE+ECDSA+AES256:ECDHE+RSA+AES256:RSA+AES256:!MD5;
        server_name           serveraddr.com;
        index index.html index.htm;
        root  /home/wwwroot/3DCEList;
        error_page 400 = /400.html;

        # Config for 0-RTT in TLSv1.3
        ssl_session_cache    shared:SSL:10m;
        ssl_early_data on;
        resolver             8.8.8.8 1.1.1.1 valid=300s;
        resolver_timeout     5s;
        add_header Strict-Transport-Security "max-age=31536000";

        location /ray/
        {
        proxy_redirect off;
        proxy_read_timeout 1200s;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Config for 0-RTT in TLSv1.3
        proxy_set_header Early-Data \$ssl_early_data;
        }
}
    server {
        listen 80;
        listen [::]:80;
        server_name serveraddr.com;
        return 301 https://${domain}\$request_uri;
    }
EOF

    modify_nginx_port
    modify_nginx_other
    judge "Nginx 配置修改"

}

start_process_systemd() {
    systemctl daemon-reload
    mkdir -p /var/log/sing-box
    systemctl restart nginx
    judge "Nginx 启动"
    if [[ -f ${singbox_systemd_file} ]]; then
        systemctl restart sing-box
        judge "sing-box 启动"
    fi
}

enable_process_systemd() {
    systemctl enable nginx
    judge "设置 Nginx 开机自启"
    if [[ -f ${singbox_systemd_file} ]]; then
        systemctl enable sing-box
        judge "设置 sing-box 开机自启"
    fi
}

stop_process_systemd() {
    systemctl stop nginx
    [[ -f ${singbox_systemd_file} ]] && systemctl stop sing-box
}
nginx_process_disabled() {
    [ -f $nginx_systemd_file ] && systemctl stop nginx && systemctl disable nginx
}

#debian 系 9 10 适配
#rc_local_initialization(){
#    if [[ -f /etc/rc.local ]];then
#        chmod +x /etc/rc.local
#    else
#        touch /etc/rc.local && chmod +x /etc/rc.local
#        echo "#!/bin/bash" >> /etc/rc.local
#        systemctl start rc-local
#    fi
#
#    judge "rc.local 配置"
#}

acme_cron_update() {
    wget -N -P /usr/bin --no-check-certificate "https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/${github_branch}/ssl_update.sh"
    if [[ $(crontab -l | grep -c "ssl_update.sh") -lt 1 ]]; then
      if [[ "${ID}" == "centos" ]]; then
          #        sed -i "/acme.sh/c 0 3 * * 0 \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
          #        &> /dev/null" /var/spool/cron/root
          sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/root
      else
          #        sed -i "/acme.sh/c 0 3 * * 0 \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" \
          #        &> /dev/null" /var/spool/cron/crontabs/root
          sed -i "/acme.sh/c 0 3 * * 0 bash ${ssl_update_file}" /var/spool/cron/crontabs/root
      fi
    fi
    judge "cron 计划任务更新"
}

vmess_link_gen() {
    local ps="$1" id="$2" add="$3" port="$4" path="$5"
    local json
    json="{\"v\":\"2\",\"ps\":\"${ps}\",\"add\":\"${add}\",\"port\":\"${port}\",\"id\":\"${id}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${add}\",\"path\":\"${path}\",\"tls\":\"tls\"}"
    echo -n "${json}" | base64 -w 0
}

vmess_node_conf() {
    vmess_users_ensure
    local ps="vmess_${domain}" first_id=""
    local first_line
    first_line="$(head -1 "${vmess_users_file}")"
    [[ -n "${first_line}" ]] && read -r ps first_id <<<"${first_line}"
    cat >$v2ray_qr_config_file <<-EOF
{
  "v": "2",
  "ps": "${ps}",
  "add": "${domain}",
  "port": "${port}",
  "id": "${first_id}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "${domain}",
  "path": "${camouflage}",
  "tls": "tls"
}
EOF
}

info_extraction() {
    grep "$1" $v2ray_qr_config_file | awk -F '"' '{print $4}'
}

v2ray_config_output() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    vmess_users_ensure
    local domain port path
    domain="$(info_extraction '\"add\"')"
    port="$(info_extraction '\"port\"')"
    path="$(info_extraction '\"path\"')"

    {
        echo -e "${OK} ${GreenBG} V2Ray 配置信息 ${Font}"
        echo -e "${Red} 地址（address）:${Font} ${domain}"
        echo -e "${Red} 端口（port）：${Font} ${port}"
        echo -e "${Red} 路径（path）：${Font} ${path}"
        echo -e ""
        while read -r name uuid; do
            [[ -z "${name}" ]] && continue
            echo -e "${Red} 用户：${name} ${Font}"
            echo -e "${Red}  UUID：${Font} ${uuid}"
            echo -e "${Red}  导入链接：${Font} vmess://$(vmess_link_gen "${name}" "${uuid}" "${domain}" "${port}" "${path}")"
        done <"${vmess_users_file}"
    } >"${v2ray_info_file}"

    cat "${v2ray_info_file}"
}

ssl_judge_and_install() {
    if [[ -f "/data/v2ray.key" || -f "/data/v2ray.crt" ]]; then
        echo "/data 目录下证书文件已存在"
        echo -e "${OK} ${GreenBG} 是否删除 [Y/N]? ${Font}"
        read -r ssl_delete
        case $ssl_delete in
        [yY][eE][sS] | [yY])
            rm -rf /data/v2ray.crt /data/v2ray.key
            echo -e "${OK} ${GreenBG} 已删除 ${Font}"
            ;;
        *) ;;

        esac
    fi

    if [[ -f "/data/v2ray.key" || -f "/data/v2ray.crt" ]]; then
        echo "证书文件已存在"
    elif [[ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
        echo "证书文件已存在"
        "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
        judge "证书应用"
    else
        ssl_install
        acme
    fi
}

nginx_systemd() {
    cat >$nginx_systemd_file <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/etc/nginx/logs/nginx.pid
ExecStartPre=/etc/nginx/sbin/nginx -t
ExecStart=/etc/nginx/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=/etc/nginx/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    judge "Nginx systemd ServerFile 添加"
    systemctl daemon-reload
}

tls_type() {
    if [[ -f "/etc/nginx/sbin/nginx" ]] && [[ -f "$nginx_conf" ]] && [[ "$shell_mode" == "ws" ]]; then
        echo "请选择支持的 TLS 版本（default:3）:"
        echo "请注意,如果你使用 Quantaumlt X / 路由器 / 旧版 Shadowrocket / 低于 4.18.1 版本的 V2ray core 请选择 兼容模式"
        echo "1: TLS1.1 TLS1.2 and TLS1.3（兼容模式）"
        echo "2: TLS1.2 and TLS1.3 (兼容模式)"
        echo "3: TLS1.3 only"
        read -rp "请输入：" tls_version
        [[ -z ${tls_version} ]] && tls_version=3
        if [[ $tls_version == 3 ]]; then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
        elif [[ $tls_version == 1 ]]; then
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.1 TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.1 TLS1.2 and TLS1.3 ${Font}"
        else
            sed -i 's/ssl_protocols.*/ssl_protocols         TLSv1.2 TLSv1.3;/' $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
        fi
        systemctl restart nginx
        judge "Nginx 重启"
    else
        echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在，请正确安装脚本后执行${Font}"
    fi
}

show_access_log() {
    [ -f ${v2ray_access_log} ] && tail -f ${v2ray_access_log} || echo -e "${RedBG}log文件不存在${Font}"
}

show_error_log() {
    [ -f ${v2ray_error_log} ] && tail -f ${v2ray_error_log} || echo -e "${RedBG}log文件不存在${Font}"
}

show_singbox_log() {
    [[ -f ${singbox_conf} ]] || { echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"; return 1; }
    if [[ -f "${singbox_log_file}" ]]; then
        tail -f "${singbox_log_file}"
    else
        journalctl -u sing-box --output cat -f
    fi
}

ssl_update_manuel() {
    [ -f ${amce_sh_file} ] && "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" || echo -e "${RedBG}证书签发工具不存在，请确认你是否使用了自己的证书${Font}"
    domain="$(info_extraction '\"add\"')"
    "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc
}

update_dat() {
    local dat_path='/usr/local/lib/v2ray/'

    if [[ ! -f "${v2ray_bin_dir}" ]] && [[ ! -f "${v2ray_bin_dir_old}/v2ray" ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 V2Ray ${Font}"
        return 1
    fi

    local dir_tmp
    dir_tmp="$(mktemp -d)"

    echo -e "${OK} ${GreenBG} 正在下载 geoip.dat ${Font}"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
        -o "${dir_tmp}/geoip.dat" \
        "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"; then
        echo -e "${Error} ${RedBG} geoip.dat 下载失败 ${Font}"
        rm -rf "${dir_tmp}"
        return 1
    fi

    echo -e "${OK} ${GreenBG} 正在下载 geosite.dat ${Font}"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
        -o "${dir_tmp}/dlc.dat" \
        "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"; then
        echo -e "${Error} ${RedBG} geosite.dat 下载失败 ${Font}"
        rm -rf "${dir_tmp}"
        return 1
    fi

    echo -e "${OK} ${GreenBG} 正在验证校验和 ${Font}"
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
        -o "${dir_tmp}/geoip.dat.sha256sum" \
        "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat.sha256sum"; then
        echo -e "${Error} ${RedBG} geoip.dat sha256sum 下载失败 ${Font}"
        rm -rf "${dir_tmp}"
        return 1
    fi
    if ! curl -L -q --retry 5 --retry-delay 10 --retry-max-time 60 \
        -o "${dir_tmp}/dlc.dat.sha256sum" \
        "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat.sha256sum"; then
        echo -e "${Error} ${RedBG} geosite.dat sha256sum 下载失败 ${Font}"
        rm -rf "${dir_tmp}"
        return 1
    fi

    (
        cd "${dir_tmp}" || exit 1
        if ! sha256sum -c "geoip.dat.sha256sum"; then
            echo -e "${Error} ${RedBG} geoip.dat 校验失败 ${Font}"
            exit 1
        fi
        if ! sha256sum -c "dlc.dat.sha256sum"; then
            echo -e "${Error} ${RedBG} geosite.dat 校验失败 ${Font}"
            exit 1
        fi
    ) || {
        rm -rf "${dir_tmp}"
        return 1
    }

    install -d "${dat_path}"
    systemctl stop v2ray
    install -m 644 "${dir_tmp}/geoip.dat" "${dat_path}geoip.dat"
    install -m 644 "${dir_tmp}/dlc.dat" "${dat_path}geosite.dat"
    systemctl start v2ray
    judge "geoip.dat geosite.dat 更新"

    rm -rf "${dir_tmp}"
}

uninstall_all() {
    local uninstalled_any=0
    if [[ -f $v2ray_bin_dir || -d $v2ray_bin_dir_old || -f $v2ray_systemd_file ]]; then
        echo -e "${OK} ${Green} 是否卸载 V2Ray [Y/N]? ${Font}"
        read -r uninstall_v2ray
        case $uninstall_v2ray in
        [yY][eE][sS] | [yY])
            systemctl disable v2ray >/dev/null 2>&1
            systemctl stop v2ray >/dev/null 2>&1
            rm -f $v2ray_systemd_file
            rm -f $v2ray_bin_dir
            rm -f $v2ctl_bin_dir
            rm -rf $v2ray_bin_dir_old
            rm -rf $v2ray_conf_dir
            rm -rf $web_dir
            rm -f $v2ray_qr_config_file
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 V2Ray ${Font}"
            ;;
        *) ;;

        esac
    fi
    if [[ -d $nginx_dir ]]; then
        echo -e "${OK} ${Green} 是否卸载 Nginx [Y/N]? ${Font}"
        read -r uninstall_nginx
        case $uninstall_nginx in
        [yY][eE][sS] | [yY])
            systemctl disable nginx >/dev/null 2>&1
            systemctl stop nginx >/dev/null 2>&1
            rm -rf $nginx_dir
            rm -rf $nginx_systemd_file
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 Nginx ${Font}"
            ;;
        *) ;;

        esac
    fi
    if [[ -s "${vmess_users_file}" || -f "${v2ray_qr_config_file}" ]]; then
        echo -e "${OK} ${Green} 是否卸载 VMess [Y/N]? ${Font}"
        read -r uninstall_vmess
        case $uninstall_vmess in
        [yY][eE][sS] | [yY])
            rm -f "${vmess_users_file}"
            rm -f "${v2ray_qr_config_file}"
            rm -f "${v2ray_info_file}"
            rm -f "${singbox_vmess_port_file}"
            # 若还装有 AnyTLS，重生成 sing-box 配置（去掉 vmess-in）并重启
            if [[ -s "${anytls_users_file}" && -f "${singbox_conf}" ]]; then
                anytls_conf_add
                [[ -f "${singbox_systemd_file}" ]] && systemctl restart sing-box >/dev/null 2>&1
            fi
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 VMess ${Font}"
            ;;
        *) ;;

        esac
    fi
    if [[ -f ${singbox_bin_dir} || -d ${singbox_conf_dir} || -f ${singbox_systemd_file} ]]; then
        echo -e "${OK} ${Green} 是否卸载 sing-box (VMess/AnyTLS) [Y/N]? ${Font}"
        read -r uninstall_singbox
        case $uninstall_singbox in
        [yY][eE][sS] | [yY])
            systemctl disable sing-box >/dev/null 2>&1
            systemctl stop sing-box >/dev/null 2>&1
            rm -f ${singbox_systemd_file}
            rm -f ${singbox_bin_dir}
            rm -rf ${singbox_conf_dir}
            rm -f ${anytls_info_file}
            rm -f "${vmess_users_file}"
            rm -f "${v2ray_qr_config_file}"
            rm -f "${v2ray_info_file}"
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 sing-box (VMess/AnyTLS) ${Font}"
            ;;
        *) ;;

        esac
    fi
    if warp_installed; then
        echo -e "${OK} ${Green} 是否卸载 WARP [Y/N]? ${Font}"
        read -r uninstall_warp
        case $uninstall_warp in
        [yY][eE][sS] | [yY])
            warp_uninstall
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 WARP ${Font}"
            ;;
        *) ;;

        esac
    fi
    if panel_installed || [[ -f "${panel_systemd_file}" ]]; then
        echo -e "${OK} ${Green} 是否卸载流量面板 [Y/N]? ${Font}"
        read -r uninstall_panel
        case $uninstall_panel in
        [yY][eE][sS] | [yY])
            panel_uninstall
            uninstalled_any=1
            ;;
        *) ;;

        esac
    fi
    echo -e "${OK} ${Green} 是否卸载acme.sh及证书 [Y/N]? ${Font}"
    read -r uninstall_acme
    case $uninstall_acme in
    [yY][eE][sS] | [yY])
      /root/.acme.sh/acme.sh --uninstall
      rm -rf /root/.acme.sh
      rm -rf /data/v2ray.crt /data/v2ray.key
      uninstalled_any=1
      ;;
    *) ;;
    esac
    systemctl daemon-reload
    if [[ "${uninstalled_any}" -eq 1 ]]; then
        echo -e "${OK} ${GreenBG} 已卸载 ${Font}"
    else
        echo -e "${OK} ${GreenBG} 未卸载任何组件 ${Font}"
    fi
}
delete_tls_key_and_crt() {
    [[ -f $HOME/.acme.sh/acme.sh ]] && /root/.acme.sh/acme.sh uninstall >/dev/null 2>&1
    [[ -d $HOME/.acme.sh ]] && rm -rf "$HOME/.acme.sh"
    echo -e "${OK} ${GreenBG} 已清空证书遗留文件 ${Font}"
}
judge_mode() {
    shell_mode="None"
    if [[ -s "${vmess_users_file}" ]] && grep -q "ws" "${v2ray_qr_config_file}" 2>/dev/null; then
        shell_mode="ws"
    fi
    if [[ -s "${anytls_users_file}" ]]; then
        if [[ "${shell_mode}" == "None" ]]; then
            shell_mode="anytls"
        else
            shell_mode="${shell_mode}+anytls"
        fi
    fi
}
install_v2ray_ws_tls() {
    is_root
    if [[ -s "${vmess_users_file}" ]] && [[ -f "${singbox_conf}" ]] && grep -q '"vmess-in"' "${singbox_conf}"; then
        echo -e "${Error} ${RedBG} 已安装 VMess (ws+tls)，拒绝重复安装 ${Font}"
        return 1
    fi
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    old_config_exist_check
    port_alterid_set
    singbox_install
    port_exist_check 80
    port_exist_check "${port}"
    nginx_exist_check
    mkdir -p /etc/v2ray
    if [[ "on" == "$old_config_status" ]] && [[ -f "$v2ray_qr_config_file" ]]; then
        echo "vmess $(info_extraction '\"id\"')" >"${vmess_users_file}"
    else
        read -rp "请输入首个用户名（default:vmess）:" first_user
        [[ -z "${first_user}" ]] && first_user="vmess"
        echo "${first_user} $(cat /proc/sys/kernel/random/uuid)" >"${vmess_users_file}"
    fi
    v2ray_conf_add
    nginx_conf_add
    web_camouflage
    ssl_judge_and_install
    nginx_systemd
    vmess_node_conf
    tls_type
    v2ray_config_output
    start_process_systemd
    enable_process_systemd
    acme_cron_update
}
install_anytls() {
    is_root
    if [[ -f "${anytls_users_file}" ]] && [[ -s "${anytls_users_file}" ]]; then
        echo -e "${Error} ${RedBG} 已安装 AnyTLS (sing-box)，拒绝重复安装 ${Font}"
        return 1
    fi
    check_system
    dependency_install
    basic_optimization
    domain_check
    mkdir -p ${singbox_conf_dir}
    echo "$domain" >${anytls_domain_file}
    anytls_port_set
    port_exist_check "${anytls_port}"
    singbox_install
    ssl_judge_and_install
    read -rp "请输入首个用户名（default:anytls）:" first_user
    [[ -z "${first_user}" ]] && first_user="anytls"
    echo "${first_user} $(anytls_gen_password)" >${anytls_users_file}
    anytls_conf_add
    systemctl restart sing-box
    judge "sing-box 启动"
    systemctl enable sing-box
    judge "设置 sing-box 开机自启"
    surge_config_output
}
update_sh() {
    ol_version=$(curl -L -s -H 'Cache-Control: no-cache' "https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/${github_branch}/install.sh?t=$(date +%s)" | grep "shell_version=" | head -1 | awk -F '=|"' '{print $3}')
    if [[ -z "${ol_version}" ]]; then
        echo -e "${Error} ${RedBG} 获取远程版本失败，跳过更新检查 ${Font}"
        return 0
    fi
    echo "$ol_version" >$version_cmp
    echo "$shell_version" >>$version_cmp
    if [[ "$shell_version" != "$(sort -rV $version_cmp | head -1)" ]]; then
        echo -e "${OK} ${GreenBG} 存在新版本，是否更新 [Y/N]? ${Font}"
        read -r update_confirm
        case $update_confirm in
        [yY][eE][sS] | [yY])
            wget --no-check-certificate -O install.sh "https://raw.githubusercontent.com/layfu/vmess_ws-tls_bash_onekey/${github_branch}/install.sh?t=$(date +%s)" && chmod +x install.sh
            echo -e "${OK} ${GreenBG} 更新完成 ${Font}"
            exit 0
            ;;
        *) ;;

        esac
    else
        echo -e "${OK} ${GreenBG} 当前版本为最新版本 ${Font}"
    fi

}
maintain() {
    echo -e "${RedBG}该选项暂时无法使用${Font}"
    echo -e "${RedBG}$1${Font}"
    exit 0
}
warp_installed() {
    [[ -x /usr/bin/warp-cli ]] && return 0
    return 1
}
warp_install() {
    is_root
    if [[ "${ID}" != "debian" && "${ID}" != "ubuntu" ]]; then
        echo -e "${Error} ${RedBG} WARP 官方源仅支持 Debian/Ubuntu，当前系统 ${ID} 不支持 ${Font}"
        return 1
    fi
    if warp_installed; then
        echo -e "${Error} ${RedBG} 已安装 WARP，拒绝重复安装 ${Font}"
        return 1
    fi
    command -v curl >/dev/null 2>&1 || apt-get install -y -qq curl >/dev/null
    apt-get install -y -qq gnupg >/dev/null
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" >/etc/apt/sources.list.d/cloudflare-client.list
    apt-get update -qq
    apt-get install -y -qq cloudflare-warp >/dev/null
    judge "cloudflare-warp 安装"
    warp-cli --accept-tos registration new >/dev/null 2>&1 || true
    warp-cli --accept-tos mode proxy >/dev/null 2>&1
    warp-cli --accept-tos proxy port ${warp_socks_port} >/dev/null 2>&1
    warp-cli --accept-tos connect >/dev/null 2>&1
    sleep 5
    echo -e "${OK} ${GreenBG} WARP 安装完成，正在验证（期望 warp=on）${Font}"
    warp_status
}
warp_uninstall() {
    if warp_installed; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos delete >/dev/null 2>&1
    fi
    systemctl stop warp-svc >/dev/null 2>&1
    systemctl disable warp-svc >/dev/null 2>&1
    apt-get remove -y -qq cloudflare-warp >/dev/null 2>&1
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    warp_watchdog_uninstall
    echo -e "${OK} ${GreenBG} WARP 已卸载 ${Font}"
}
warp_status() {
    if ! warp_installed; then
        echo -e "${Error} ${RedBG} WARP 未安装 ${Font}"
        return 1
    fi
    echo -e "${OK} ${GreenBG} WARP 服务状态 ${Font}"
    warp-cli status 2>/dev/null || true
    echo -e "${OK} ${GreenBG} 出口探测（经 SOCKS5 127.0.0.1:${warp_socks_port}）${Font}"
    if curl -s -x socks5h://127.0.0.1:${warp_socks_port} --max-time 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep -E 'ip=|warp='; then
        :
    else
        echo -e "${Red} 探测失败，WARP 可能未正常转发（控制面 Connected 不代表转发正常）${Font}"
    fi
}
warp_watchdog_install() {
    if ! warp_installed; then
        echo -e "${Error} ${RedBG} 请先安装 WARP ${Font}"
        return 1
    fi
    cat >"${warp_healthcheck_file}" <<'EOF'
#!/usr/bin/env bash
# WARP self-heal: verify egress through the SOCKS proxy; restart warp-svc if broken.
PORT="${WARP_SOCKS_PORT:-40000}"
if curl -s -x socks5h://127.0.0.1:${PORT} --max-time 10 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep -q 'warp=on'; then
    exit 0
fi
systemctl restart warp-svc
EOF
    chmod +x "${warp_healthcheck_file}"
    cat >"${warp_systemd_service}" <<EOF
[Unit]
Description=WARP proxy health check
After=network-online.target

[Service]
Type=oneshot
Environment=WARP_SOCKS_PORT=${warp_socks_port}
ExecStart=${warp_healthcheck_file}
EOF
    cat >"${warp_systemd_timer}" <<'EOF'
[Unit]
Description=Run WARP proxy health check every 60s

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=5

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now warp-healthcheck.timer >/dev/null 2>&1
    echo -e "${OK} ${GreenBG} WARP 自愈守护已安装（每 60s 检测）${Font}"
}
warp_watchdog_uninstall() {
    systemctl disable --now warp-healthcheck.timer >/dev/null 2>&1
    rm -f "${warp_systemd_timer}" "${warp_systemd_service}" "${warp_healthcheck_file}"
    systemctl daemon-reload
}
warp_menu() {
    while true; do
        clear_screen
        section_title "WARP"
        echo -e "${Green}1.${Font} 安装 WARP"
        echo -e "${Green}2.${Font} 卸载 WARP"
        echo -e "${Green}3.${Font} 查看 WARP 状态"
        echo -e "${Green}4.${Font} 自愈守护 安装/卸载"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" warp_num
        case ${warp_num} in
        1)
            warp_install
            ;;
        2)
            warp_uninstall
            ;;
        3)
            warp_status
            ;;
        4)
            if [[ -f "${warp_systemd_timer}" ]]; then
                warp_watchdog_uninstall
                judge "WARP 自愈守护 卸载"
            else
                warp_watchdog_install
                judge "WARP 自愈守护 安装"
            fi
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}
list() {
    case $1 in
    tls_modify)
        tls_type
        ;;
    uninstall)
        uninstall_all
        ;;
    crontab_modify)
        acme_cron_update
        ;;
    dat_update)
        update_dat
        ;;
    v2ray_update)
        v2ray_update
        ;;
    singbox_update)
        singbox_update
        ;;
    singbox_geodata_update)
        singbox_geodata_update
        ;;
    nginx_update)
        nginx_upgrade
        ;;
    *)
        menu
        ;;
    esac
}
nginx_upgrade_is_root() {
    if [[ 0 != "$UID" ]]; then
        echo -e "${Error} ${RedBG} 当前用户不是root用户，请切换到root用户后重新执行脚本 ${Font}"
        exit 1
    fi
}

nginx_upgrade_ensure_deps() {
    if [[ "${ID}" == "centos" ]]; then
        INS="yum"
    else
        INS="apt"
    fi

    command -v wget >/dev/null 2>&1 || ${INS} -y install wget
    command -v make >/dev/null 2>&1 || {
        if [[ "${ID}" == "centos" ]]; then
            ${INS} -y groupinstall "Development tools"
        else
            ${INS} -y install build-essential
        fi
    }

    if [[ "${ID}" == "centos" ]]; then
        ${INS} -y install pcre2-devel zlib-devel epel-release
    else
        ${INS} -y install libpcre2-dev zlib1g-dev
    fi
}

nginx_upgrade_check_mode() {
    local nginx_sbin="${nginx_dir}/sbin/nginx"
    if [[ ! -f "$nginx_sbin" ]]; then
        echo -e "${Error} ${RedBG} 未检测到 Nginx (${nginx_sbin})，请确认已通过 ws+tls 模式安装 ${Font}"
        exit 1
    fi
    if [[ ! -f "$nginx_conf" ]]; then
        echo -e "${Error} ${RedBG} 未检测到 v2ray.conf (${nginx_conf})，请确认已通过 ws+tls 模式安装 ${Font}"
        exit 1
    fi
    echo -e "${OK} ${GreenBG} 检测到 ws+tls 模式安装，进入 Nginx 升级流程 ${Font}"
}

nginx_upgrade_show_version() {
    local nginx_sbin="${nginx_dir}/sbin/nginx"
    current_nginx=$("$nginx_sbin" -v 2>&1 | awk -F '/' '{print $NF}')
    current_openssl=$("$nginx_sbin" -V 2>&1 | grep -oE 'built with OpenSSL [0-9]+\.[0-9]+\.[0-9]+[a-z]?' | head -1 | awk '{print $NF}')
    echo -e "${Green}当前 Nginx 版本: ${Red}${current_nginx}${Font}"
    echo -e "${Green}当前 OpenSSL 版本: ${Red}${current_openssl:-无法检测}${Font}"
    echo -e "${Green}当前 Jemalloc 版本: ${Red}未知 (默认安装为 5.3.1)${Font}"
    echo ""
}

nginx_upgrade_check_modules() {
    local load_mods
    load_mods=$(grep -rn "load_module" "${nginx_dir}/conf/" 2>/dev/null)
    if [[ -n "$load_mods" ]]; then
        echo -e "${RedBG}检测到 load_module 动态模块依赖:${Font}"
        echo "$load_mods"
        echo ""
        echo -e "${Red}说明: 动态模块(.so)与 Nginx 版本/ABI 严格绑定，升级二进制后这些模块可能加载失败，${Font}"
        echo -e "${Red}导致 Nginx 无法启动。${Font}"
        echo ""
        read -rp "是否仍要继续升级? [y/N]: " module_confirm
        [[ -z "$module_confirm" ]] && module_confirm="N"
        case $module_confirm in
            [yY][eE][sS] | [yY])
                echo -e "${Green}确认继续${Font}"
                sleep 1
                ;;
            *)
                echo -e "${RedBG} 已取消 ${Font}"
                exit 0
                ;;
        esac
    else
        echo -e "${OK} ${GreenBG} 未检测到动态模块依赖 ${Font}"
    fi
}

nginx_upgrade_check_conflicts() {
    echo -e "${GreenBG}>>> 环境冲突检测 <<<${Font}"
    echo ""
    local has_conflict=0

    if [[ "${ID}" == "centos" ]]; then
        if rpm -qa 2>/dev/null | grep -q '^nginx-'; then
            echo -e "${Red}[冲突] 检测到通过 yum/dnf 安装的 Nginx 包，升级可能覆盖其二进制与默认配置${Font}"
            has_conflict=1
        fi
    else
        if dpkg -l nginx nginx-full nginx-light nginx-extras nginx-common 2>/dev/null | grep -q '^ii'; then
            echo -e "${Red}[冲突] 检测到通过 apt 安装的 Nginx 包，升级可能覆盖其二进制与默认配置${Font}"
            has_conflict=1
        fi
    fi

    if [[ -d "$nginx_conf_dir" ]]; then
        local other_confs
        other_confs=$(ls "$nginx_conf_dir"/*.conf 2>/dev/null | grep -v 'v2ray.conf$')
        if [[ -n "$other_confs" ]]; then
            echo -e "${Red}[提示] conf.d/ 下存在其他站点配置，升级过程会短暂中断这些站点:${Font}"
            echo "$other_confs"
            echo -e "${Green}        这些配置会被完整保留并备份。${Font}"
        fi
    fi

    for svc in apache2 httpd caddy lighttpd; do
        if systemctl is-active "$svc" &>/dev/null; then
            echo -e "${Red}[冲突] 检测到其他 Web 服务正在运行: ${svc}${Font}"
            has_conflict=1
        fi
    done

    local nginx_was_running=""
    if systemctl is-active nginx &>/dev/null; then
        systemctl stop nginx 2>/dev/null
        nginx_was_running="1"
    fi
    sleep 1
    for port in 80 443; do
        local occupied proc_name
        occupied=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1)
        if [[ -n "$occupied" ]]; then
            proc_name=$(echo "$occupied" | awk '{print $NF}')
            echo -e "${Red}[冲突] 端口 ${port} 被占用 (${proc_name:-unknown})${Font}"
            has_conflict=1
        fi
    done
    if [[ "$nginx_was_running" == "1" ]]; then
        systemctl start nginx 2>/dev/null
    fi

    echo ""
    if [[ "$has_conflict" -eq 1 ]]; then
        echo -e "${RedBG}检测到以上冲突项，升级可能影响服务器上的其他服务${Font}"
        echo ""
        read -rp "是否仍要继续升级? [y/N]: " conflict_confirm
        [[ -z "$conflict_confirm" ]] && conflict_confirm="N"
        case $conflict_confirm in
            [yY][eE][sS] | [yY])
                echo -e "${Green}确认继续${Font}"
                sleep 1
                ;;
            *)
                echo -e "${RedBG} 已取消 ${Font}"
                exit 0
                ;;
        esac
    else
        echo -e "${OK} ${GreenBG} 未检测到冲突，可以安全升级 ${Font}"
        echo ""
        sleep 1
    fi
}

nginx_upgrade_input() {
    echo -e "${GreenBG}请输入要升级到的目标版本号，留空则跳过该项升级${Font}"
    echo ""

    read -rp "Nginx 目标版本 (如 1.30.4，留空跳过): " new_nginx
    read -rp "OpenSSL 目标版本 (如 3.5.7，留空跳过): " new_openssl
    read -rp "Jemalloc 目标版本 (如 5.3.1，留空跳过): " new_jemalloc

    if [[ -z "$new_nginx" && -z "$new_openssl" && -z "$new_jemalloc" ]]; then
        echo -e "${Error} ${RedBG} 未指定任何升级项，退出 ${Font}"
        exit 0
    fi

    if [[ -z "$new_nginx" ]] && [[ -n "$new_openssl" || -n "$new_jemalloc" ]]; then
        new_nginx="${current_nginx}"
        echo -e "${Green}[提示] OpenSSL/Jemalloc 静态编译于 Nginx，将使用当前 Nginx 版本 ${current_nginx} 重新编译以使其生效 ${Font}"
    fi

    openssl_for_nginx=""
    if [[ -n "$new_openssl" ]]; then
        openssl_for_nginx="$new_openssl"
    elif [[ -n "$current_openssl" ]]; then
        openssl_for_nginx="$current_openssl"
    fi

    if [[ -n "$new_nginx" ]]; then
        if [[ -z "$openssl_for_nginx" ]]; then
            echo -e "${Error} ${RedBG} 升级 Nginx 需要一份 OpenSSL 源码作为编译依赖，请输入 OpenSSL 版本号 ${Font}"
            read -rp "OpenSSL 目标版本: " openssl_for_nginx
            [[ -z "$openssl_for_nginx" ]] && exit 1
        fi
    fi

    echo ""
    echo -e "${Green}========== 升级计划 ==========${Font}"
    if [[ -n "$new_nginx" ]]; then
        if [[ "$new_nginx" == "$current_nginx" ]]; then
            echo -e "  Nginx:    ${current_nginx}  ${Red}(重建)${Font}"
        else
            echo -e "  Nginx:    ${current_nginx}  ->  ${Red}${new_nginx}${Font}"
        fi
    fi
    [[ -n "$new_openssl" ]] && echo -e "  OpenSSL:  ${current_openssl:-N/A}  ->  ${Red}${new_openssl}${Font}"
    [[ -n "$new_jemalloc" ]] && echo -e "  Jemalloc: 未知  ->  ${Red}${new_jemalloc}${Font}"
    echo -e "${Green}===============================${Font}"
    echo ""

    read -rp "确认升级? [Y/n]: " confirm
    [[ -z "$confirm" ]] && confirm="Y"
    case $confirm in
        [yY][eE][sS] | [yY])
            ;;
        *)
            echo -e "${RedBG} 已取消 ${Font}"
            exit 0
            ;;
    esac
}

nginx_upgrade_backup() {
    nginx_upgrade_backup_dir="/tmp/nginx_upgrade_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$nginx_upgrade_backup_dir"
    cp -a "${nginx_dir}/conf" "${nginx_upgrade_backup_dir}/conf" 2>/dev/null
    [[ -d "${nginx_dir}/html" ]] && cp -a "${nginx_dir}/html" "${nginx_upgrade_backup_dir}/html" 2>/dev/null
    cp -a "${nginx_dir}/sbin/nginx" "${nginx_upgrade_backup_dir}/nginx" 2>/dev/null
    judge "Nginx 配置与二进制备份"
    echo -e "${Green}备份目录: ${nginx_upgrade_backup_dir}${Font}"
    sleep 1
}

nginx_upgrade_download() {
    cd "$nginx_openssl_src" || exit 1

    if [[ -n "$new_nginx" ]]; then
        echo -e "${GreenBG}下载 Nginx ${new_nginx} ...${Font}"
        wget -nc --no-check-certificate "http://nginx.org/download/nginx-${new_nginx}.tar.gz" -P "$nginx_openssl_src"
        judge "Nginx 下载"
    fi

    local ossl_ver="${new_openssl:-$openssl_for_nginx}"
    if [[ -n "$ossl_ver" ]]; then
        echo -e "${GreenBG}下载 OpenSSL ${ossl_ver} ...${Font}"
        if ! wget -nc --no-check-certificate "https://www.openssl.org/source/openssl-${ossl_ver}.tar.gz" -P "$nginx_openssl_src"; then
            local ossl_major_minor
            ossl_major_minor=$(echo "$ossl_ver" | awk -F. '{print $1"."$2}')
            echo -e "${Green}[提示] 主源下载失败，尝试旧版本目录 /source/old/${ossl_major_minor}/ ...${Font}"
            wget -nc --no-check-certificate "https://www.openssl.org/source/old/${ossl_major_minor}/openssl-${ossl_ver}.tar.gz" -P "$nginx_openssl_src" || {
                echo -e "${Error} ${RedBG} OpenSSL 下载失败，请手动下载至 ${nginx_openssl_src} 后重试 ${Font}"
                exit 1
            }
        fi
        judge "OpenSSL 下载"
    fi

    if [[ -n "$new_jemalloc" ]]; then
        echo -e "${GreenBG}下载 Jemalloc ${new_jemalloc} ...${Font}"
        wget -nc --no-check-certificate "https://github.com/jemalloc/jemalloc/releases/download/${new_jemalloc}/jemalloc-${new_jemalloc}.tar.bz2" -P "$nginx_openssl_src"
        judge "Jemalloc 下载"
    fi
}

nginx_upgrade_extract() {
    cd "$nginx_openssl_src" || exit 1

    if [[ -n "$new_nginx" ]]; then
        [[ -d "nginx-${new_nginx}" ]] && rm -rf "nginx-${new_nginx}"
        tar -zxvf "nginx-${new_nginx}.tar.gz" >/dev/null 2>&1
    fi

    local ossl_ver="${new_openssl:-$openssl_for_nginx}"
    if [[ -n "$ossl_ver" ]]; then
        [[ -d "openssl-${ossl_ver}" ]] && rm -rf "openssl-${ossl_ver}"
        tar -zxvf "openssl-${ossl_ver}.tar.gz" >/dev/null 2>&1
    fi

    if [[ -n "$new_jemalloc" ]]; then
        [[ -d "jemalloc-${new_jemalloc}" ]] && rm -rf "jemalloc-${new_jemalloc}"
        tar -xvf "jemalloc-${new_jemalloc}.tar.bz2" >/dev/null 2>&1
    fi
    echo -e "${OK} ${GreenBG} 源码解压完成 ${Font}"
}

nginx_upgrade_compile_jemalloc() {
    if [[ -z "$new_jemalloc" ]]; then
        return
    fi
    echo -e "${GreenBG}编译安装 Jemalloc ${new_jemalloc} ...${Font}"
    sleep 2

    cd "${nginx_openssl_src}/jemalloc-${new_jemalloc}" || exit 1
    ./configure
    judge "Jemalloc configure"
    make -j "$THREAD" && make install
    judge "Jemalloc 编译安装"
    echo '/usr/local/lib' >/etc/ld.so.conf.d/local.conf
    ldconfig
}

nginx_upgrade_compile_nginx() {
    if [[ -z "$new_nginx" ]]; then
        return
    fi

    local ossl_ver="${new_openssl:-$openssl_for_nginx}"
    echo -e "${GreenBG}编译 Nginx ${new_nginx} (OpenSSL ${ossl_ver}) ...${Font}"
    echo -e "${Green}过程稍久，请耐心等待${Font}"
    sleep 4

    cd "${nginx_openssl_src}/nginx-${new_nginx}" || exit 1

    ./configure --prefix="${nginx_dir}" \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_gzip_static_module \
        --with-http_stub_status_module \
        --with-http_realip_module \
        --with-http_flv_module \
        --with-http_mp4_module \
        --with-http_secure_link_module \
        --with-http_v2_module \
        --with-cc-opt='-O3' \
        --with-ld-opt="-ljemalloc" \
        --with-openssl="../openssl-${ossl_ver}"
    judge "Nginx configure"
    make -j "$THREAD"
    judge "Nginx 编译"
}

nginx_upgrade_swap() {
    if [[ -z "$new_nginx" ]]; then
        return
    fi

    local nginx_sbin="${nginx_dir}/sbin/nginx"
    local src_bin="${nginx_openssl_src}/nginx-${new_nginx}/objs/nginx"

    echo -e "${GreenBG}验证新编译的 Nginx 配置 ...${Font}"
    if ! "${src_bin}" -t -c "${nginx_dir}/conf/nginx.conf"; then
        echo -e "${Error} ${RedBG} 新 Nginx 配置测试失败，未替换二进制，旧版本保持不变 ${Font}"
        exit 1
    fi

    echo -e "${GreenBG}替换 Nginx 二进制 ...${Font}"
    systemctl stop nginx 2>/dev/null
    sleep 1
    if ! cp -f "$src_bin" "$nginx_sbin"; then
        echo -e "${Error} ${RedBG} 替换二进制失败，尝试回滚 ${Font}"
        cp -f "${nginx_upgrade_backup_dir}/nginx" "$nginx_sbin" 2>/dev/null
        systemctl start nginx 2>/dev/null
        exit 1
    fi

    systemctl start nginx 2>/dev/null
    sleep 1
    if ! systemctl is-active --quiet nginx; then
        echo -e "${Error} ${RedBG} Nginx 启动失败，自动回滚旧版本 ${Font}"
        cp -f "${nginx_upgrade_backup_dir}/nginx" "$nginx_sbin" 2>/dev/null
        systemctl start nginx 2>/dev/null
        echo -e "${Red}已回滚，旧 Nginx 运行状态请用 systemctl status nginx 确认 ${Font}"
        exit 1
    fi
}

nginx_upgrade_verify() {
    local nginx_sbin="${nginx_dir}/sbin/nginx"
    echo ""
    echo "========== 升级后版本 =========="
    "$nginx_sbin" -v 2>&1
    echo "================================"
    echo ""

    echo -e "${GreenBG}升级完成！${Font}"
    echo -e "备份目录: ${Green}${nginx_upgrade_backup_dir}${Font}"
    echo -e "如需回滚: cp ${nginx_upgrade_backup_dir}/nginx ${nginx_dir}/sbin/nginx && systemctl restart nginx"

    cd "$nginx_openssl_src" || return
    [[ -n "$new_nginx" ]] && rm -rf "nginx-${new_nginx}" "nginx-${new_nginx}.tar.gz"
    local ossl_ver="${new_openssl:-$openssl_for_nginx}"
    [[ -n "$ossl_ver" ]] && rm -rf "openssl-${ossl_ver}" "openssl-${ossl_ver}.tar.gz"
    [[ -n "$new_jemalloc" ]] && rm -rf "jemalloc-${new_jemalloc}" "jemalloc-${new_jemalloc}.tar.bz2"
    echo -e "${OK} ${GreenBG} 临时文件清理完成 ${Font}"
}

nginx_upgrade() {
    nginx_upgrade_is_root
    nginx_upgrade_ensure_deps
    nginx_upgrade_check_mode
    nginx_upgrade_show_version
    nginx_upgrade_check_modules
    nginx_upgrade_check_conflicts
    nginx_upgrade_input
    nginx_upgrade_backup
    nginx_upgrade_download
    nginx_upgrade_extract
    nginx_upgrade_compile_jemalloc
    nginx_upgrade_compile_nginx
    nginx_upgrade_swap
    nginx_upgrade_verify
}

modify_camouflage_path() {
    [[ -z ${camouflage_path} ]] && camouflage_path=1
    sed -i "/location/c \\\tlocation \/${camouflage_path}\/" ${nginx_conf}          #Modify the camouflage path of the nginx configuration file
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"path\"/c \\  \"path\": \"\/${camouflage_path}\/\"," ${v2ray_qr_config_file}
    v2ray_conf_add
    judge "camouflage path modified"
}

section_title() {
    local title="$1" i c w=0 pad_l="" pad_r="" side total=50
    for ((i = 0; i < ${#title}; i++)); do
        c="${title:i:1}"
        if [[ "$(printf %s "$c" | LC_ALL=C wc -c)" -eq 1 ]]; then
            w=$((w + 1))
        else
            w=$((w + 2))
        fi
    done
    side=$(( (total - w - 2) / 2 ))
    for ((i = 0; i < side; i++)); do
        pad_l="${pad_l}—"
        pad_r="${pad_r}—"
    done
    [[ $(( (total - w - 2) % 2 )) -ne 0 ]] && pad_r="${pad_r}—"
    echo -e "${pad_l} ${title} ${pad_r}"
}

show_header() {
    judge_mode
    local mode_display="${shell_mode}"
    case "${shell_mode}" in
        "None") mode_display="未安装" ;;
        "ws") mode_display="V2Ray (vmess+ws+tls)" ;;
        "anytls") mode_display="AnyTLS" ;;
        "ws+anytls") mode_display="V2Ray (vmess+ws+tls) + AnyTLS" ;;
    esac
    echo -e "V2Ray / AnyTLS 安装管理脚本 ${Red}[${shell_version}]${Font}   当前已安装: ${mode_display}\n"
}

clear_screen() {
    printf '\033[2J\033[H'
}

pause_continue() {
    read -rp "按回车键返回菜单"
}

menu() {
    update_sh
    while true; do
        clear_screen
        show_header
        echo -e "${Green}1.${Font} 安装与升级"
        echo -e "${Green}2.${Font} V2Ray 配置"
        echo -e "${Green}3.${Font} AnyTLS 配置"
        echo -e "${Green}4.${Font} 查看信息"
        echo -e "${Green}5.${Font} 证书"
        echo -e "${Green}6.${Font} 其他"
        echo -e "${Green}0.${Font} 退出 \n"
        read -rp "请输入数字：" menu_num
        case ${menu_num} in
        1)
            install_menu
            continue
            ;;
        2)
            v2ray_config_menu
            continue
            ;;
        3)
            anytls_config_menu
            continue
            ;;
        4)
            view_menu
            continue
            ;;
        5)
            cert_menu
            continue
            ;;
        6)
            other_menu
            continue
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

install_menu() {
    while true; do
        clear_screen
        section_title "安装与升级"
        echo -e "${Green}1.${Font} 安装 VMess (Nginx+ws+tls, sing-box 内核)"
        echo -e "${Green}2.${Font} 升级 V2Ray (已弃用)"
        echo -e "${Green}3.${Font} 安装 AnyTLS (sing-box)"
        echo -e "${Green}4.${Font} 升级 sing-box"
        echo -e "${Green}5.${Font} 升级 Nginx"
        echo -e "${Green}6.${Font} 安装/卸载 WARP"
        echo -e "${Green}7.${Font} 安装 流量面板"
        echo -e "${Green}8.${Font} 升级 流量面板"
        echo -e "${Green}9.${Font} 更新 sing-box (v2ray_api)"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            shell_mode="ws"
            install_v2ray_ws_tls
            ;;
        2)
            echo -e "${Error} ${RedBG} 已弃用：VMess 现由 sing-box 承载，请使用「升级 sing-box」 ${Font}"
            ;;
        3)
            install_anytls
            ;;
        4)
            singbox_update
            ;;
        5)
            nginx_upgrade
            ;;
        6)
            warp_menu
            continue
            ;;
        7)
            panel_install
            ;;
        8)
            panel_update
            ;;
        9)
            singbox_v2rayapi_update
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

v2ray_config_menu() {
    while true; do
        clear_screen
        section_title "V2Ray 配置"
        echo -e "${Green}1.${Font} 管理 VMess 用户"
        echo -e "${Green}2.${Font} 变更 端口"
        echo -e "${Green}3.${Font} 变更 TLS 版本(仅ws+tls有效)"
        echo -e "${Green}4.${Font} 变更 伪装路径"
        echo -e "${Green}5.${Font} 路由规则"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            vmess_user_menu
            continue
            ;;
        2)
            read -rp "请输入连接端口:" port
            if grep -q "ws" $v2ray_qr_config_file; then
                modify_nginx_port
            fi
            start_process_systemd
            ;;
        3)
            tls_type
            ;;
        4)
            read -rp "请输入伪装路径(注意！不需要加斜杠 eg:ray):" camouflage_path
            modify_camouflage_path
            start_process_systemd
            ;;
        5)
            anytls_routing_menu
            continue
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

anytls_config_menu() {
    while true; do
        clear_screen
        section_title "AnyTLS 配置"
        echo -e "${Green}1.${Font} 管理 AnyTLS 用户"
        echo -e "${Green}2.${Font} 变更 AnyTLS 端口"
        echo -e "${Green}3.${Font} 路由规则"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            anytls_user_menu
            continue
            ;;
        2)
            anytls_port_change
            ;;
        3)
            anytls_routing_menu
            continue
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

view_menu() {
    while true; do
        clear_screen
        section_title "查看信息"
        echo -e "${Green}1.${Font} 查看 V2Ray 配置信息"
        echo -e "${Green}2.${Font} 查看 AnyTLS 配置信息"
        echo -e "${Green}3.${Font} 查看 V2Ray 实时访问日志"
        echo -e "${Green}4.${Font} 查看 V2Ray 实时错误日志"
        echo -e "${Green}5.${Font} 查看 AnyTLS 实时日志"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            v2ray_config_output
            ;;
        2)
            surge_config_output
            ;;
        3)
            show_access_log
            ;;
        4)
            show_error_log
            ;;
        5)
            show_singbox_log
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

cert_menu() {
    while true; do
        clear_screen
        section_title "证书"
        echo -e "${Green}1.${Font} 证书 有效期更新"
        echo -e "${Green}2.${Font} 更新 证书crontab计划任务"
        echo -e "${Green}3.${Font} 清空 证书遗留文件"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            stop_process_systemd
            ssl_update_manuel
            start_process_systemd
            ;;
        2)
            acme_cron_update
            ;;
        3)
            delete_tls_key_and_crt
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

panel_traffic_reset() {
    if ! panel_installed; then
        echo -e "${Error} ${RedBG} 面板未安装 ${Font}"
        return 1
    fi
    echo -e "${Red} 将清空全部流量统计（趋势 / 当月 / 累计 / 历史统计 / 路由拓扑），此操作不可恢复 ${Font}"
    read -rp "确认清空? [y/N]: " confirm
    case "${confirm}" in
    [yY][eE][sS] | [yY]) ;;
    *)
        echo -e "${OK} ${GreenBG} 已取消 ${Font}"
        return 0
        ;;
    esac
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${OK} ${GreenBG} 正在安装 sqlite3 ... ${Font}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y -qq sqlite3 >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q sqlite >/dev/null 2>&1
        fi
    fi
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${Error} ${RedBG} sqlite3 不可用，请手动安装后重试 ${Font}"
        return 1
    fi
    systemctl stop panel >/dev/null 2>&1
    # 注意：不清 counters（增量基线），否则下一轮会把累计值当增量写入产生尖峰。
    # 逐表删除并跳过不存在的表（旧版本可能还没有 inbound_hourly / outbound_hourly）。
    local t ok=1
    for t in hourly totals target_traffic outbound_hourly inbound_hourly; do
        if [[ "$(sqlite3 "${panel_db}" "SELECT name FROM sqlite_master WHERE type='table' AND name='${t}';" 2>/dev/null)" == "${t}" ]]; then
            sqlite3 "${panel_db}" "DELETE FROM ${t};" 2>/dev/null || ok=0
        fi
    done
    systemctl start panel >/dev/null 2>&1
    if [[ ${ok} -eq 1 ]]; then
        echo -e "${OK} ${GreenBG} 已清空流量统计，面板已重启（数值从此刻重新累积） ${Font}"
    else
        echo -e "${Error} ${RedBG} 清空失败，请检查 ${panel_db} ${Font}"
    fi
}

other_menu() {
    while true; do
        clear_screen
        section_title "其他"
        echo -e "${Green}1.${Font} 卸载"
        echo -e "${Green}2.${Font} 更新 geoip.dat 和 geosite.dat"
        echo -e "${Green}3.${Font} 更新 sing-box 规则集"
        echo -e "${Green}4.${Font} 升级 脚本"
        echo -e "${Green}5.${Font} 修改 面板密码"
        echo -e "${Green}6.${Font} 更新 IP 归属地数据库"
        echo -e "${Green}7.${Font} 清空流量统计"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            source '/etc/os-release'
            uninstall_all
            ;;
        2)
            update_dat
            ;;
        3)
            singbox_geodata_update
            ;;
        4)
            update_sh
            ;;
        5)
            if panel_installed; then
                panel_auth_set
                panel_session_secret_ensure
                systemctl restart panel >/dev/null 2>&1
            else
                echo -e "${Error} ${RedBG} 面板未安装 ${Font}"
            fi
            ;;
        6)
            panel_geo_update
            ;;
        7)
            panel_traffic_reset
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
        pause_continue
    done
}

judge_mode
list "$1"
