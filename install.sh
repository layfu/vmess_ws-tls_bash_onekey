#!/bin/bash

#====================================================
#	System Request:Debian 11+/Ubuntu 20.04+/Centos 7+
#	Author:	wulabing
#	Dscription: V2ray ws+tls onekey Management
#	Version: 1.0
#	email:admin@wulabing.com
#	Official document: www.v2ray.com
#====================================================

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
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"

# 版本
shell_version="1.6.2.0"
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
anytls_port=""
amce_sh_file="/root/.acme.sh/acme.sh"
ssl_update_file="/usr/bin/ssl_update.sh"
nginx_version="1.30.4"
openssl_version="3.5.7"
jemalloc_version="5.3.1"
old_config_status="off"
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

anytls_port_set() {
    read -rp "请输入 AnyTLS 连接端口（default:8443）:" anytls_port
    [[ -z ${anytls_port} ]] && anytls_port="8443"
}

anytls_gen_password() {
    head -c 16 /dev/urandom | md5sum | head -c 16
}

anytls_users_ensure() {
    if [[ ! -f "${anytls_users_file}" ]]; then
        mkdir -p "${singbox_conf_dir}"
        local existing_pass=""
        if [[ -f "${singbox_conf}" ]]; then
            existing_pass="$(grep '\"password\"' "${singbox_conf}" | awk -F '"' '{print $4}' | head -1)"
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
    if [[ "${user_name}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含空格 ${Font}"
        return 1
    fi
    if grep -q "^${user_name} " "${anytls_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${user_name} 已存在 ${Font}"
        return 1
    fi
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

anytls_user_menu() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    while true; do
        echo -e "\t AnyTLS 用户管理"
        echo -e "${Green}1.${Font} 查看用户列表"
        echo -e "${Green}2.${Font} 添加用户"
        echo -e "${Green}3.${Font} 删除用户"
        echo -e "${Green}4.${Font} 修改用户密码"
        echo -e "${Green}5.${Font} 返回上级菜单 \n"
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
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

anytls_conf_add() {
    anytls_users_ensure
    local users_json="" name password first=1
    while read -r name password; do
        [[ -z "${name}" ]] && continue
        if [[ ${first} -eq 1 ]]; then
            first=0
        else
            users_json="${users_json},"
        fi
        users_json="${users_json}{\"name\":\"${name}\",\"password\":\"${password}\"}"
    done <"${anytls_users_file}"

    [[ -z "${anytls_port}" ]] && anytls_port="$(grep '\"listen_port\"' "${singbox_conf}" 2>/dev/null | awk -F ':' '{print $2}' | tr -d ' ,')"
    [[ -z "${anytls_port}" ]] && anytls_port="8443"

    cat >${singbox_conf} <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${anytls_port},
      "users": [
        ${users_json}
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/data/v2ray.crt",
        "key_path": "/data/v2ray.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
    judge "sing-box 配置写入"
}

surge_config_output() {
    if [[ ! -f "${singbox_conf}" ]]; then
        echo -e "${Error} ${RedBG} AnyTLS 未安装，请先安装 ${Font}"
        return 1
    fi
    anytls_users_ensure
    [[ -z "${anytls_port}" ]] && anytls_port="$(grep '\"listen_port\"' "${singbox_conf}" | awk -F ':' '{print $2}' | tr -d ' ,')"
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
    read -rp "请输入你的域名信息(eg:www.wulabing.com):" domain
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
    if [[ "${user_name}" =~ [[:space:]] ]]; then
        echo -e "${Error} ${RedBG} 用户名不能包含空格 ${Font}"
        return 1
    fi
    if grep -q "^${user_name} " "${vmess_users_file}"; then
        echo -e "${Error} ${RedBG} 用户 ${user_name} 已存在 ${Font}"
        return 1
    fi
    echo "${user_name} $(cat /proc/sys/kernel/random/uuid)" >>"${vmess_users_file}"
    v2ray_conf_add
    systemctl restart v2ray
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
    systemctl restart v2ray
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
    systemctl restart v2ray
    judge "VMess 用户 UUID 更换"
    v2ray_config_output
}

vmess_user_menu() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    while true; do
        echo -e "\t VMess 用户管理"
        echo -e "${Green}1.${Font} 查看用户列表"
        echo -e "${Green}2.${Font} 添加用户"
        echo -e "${Green}3.${Font} 删除用户"
        echo -e "${Green}4.${Font} 更换用户 UUID"
        echo -e "${Green}5.${Font} 返回上级菜单 \n"
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
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

routing_load() {
    block_cn=0
    block_ads=0
    block_bt=1
    if [[ -f "${routing_conf_file}" ]]; then
        block_cn="$(grep '^block_cn=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
        block_ads="$(grep '^block_ads=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
        block_bt="$(grep '^block_bt=' "${routing_conf_file}" | head -1 | cut -d= -f2)"
    fi
    [[ -z "${block_cn}" ]] && block_cn=0
    [[ -z "${block_ads}" ]] && block_ads=0
    [[ -z "${block_bt}" ]] && block_bt=1
}

routing_save() {
    mkdir -p /etc/v2ray
    cat >"${routing_conf_file}" <<EOF
block_cn=${block_cn}
block_ads=${block_ads}
block_bt=${block_bt}
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
    systemctl restart v2ray
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
    systemctl restart v2ray
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
    systemctl restart v2ray
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
    systemctl restart v2ray
    judge "屏蔽 IP 删除"
}

block_domain_menu() {
    while true; do
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
    done
}

block_ip_menu() {
    while true; do
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
    done
}

routing_menu() {
    if [[ ! -f ${v2ray_qr_config_file} ]]; then
        echo -e "${Error} ${RedBG} V2Ray 未安装，请先安装 ${Font}"
        return 1
    fi
    while true; do
        routing_load
        local cn_s="关" ads_s="关" bt_s="关"
        [[ "${block_cn}" == "1" ]] && cn_s="开"
        [[ "${block_ads}" == "1" ]] && ads_s="开"
        [[ "${block_bt}" == "1" ]] && bt_s="开"
        echo -e "\t 路由规则（屏蔽）"
        echo -e "${Green}1.${Font} 禁止国内地址  [${cn_s}]"
        echo -e "${Green}2.${Font} 禁止广告地址  [${ads_s}]"
        echo -e "${Green}3.${Font} 禁止 BT 协议  [${bt_s}]"
        echo -e "${Green}4.${Font} 禁止自定义域名"
        echo -e "${Green}5.${Font} 禁止自定义 IP"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" routing_num
        case ${routing_num} in
        1)
            if [[ "${block_cn}" == "1" ]]; then block_cn=0; else block_cn=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart v2ray
            judge "禁止国内地址 切换"
            ;;
        2)
            if [[ "${block_ads}" == "1" ]]; then block_ads=0; else block_ads=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart v2ray
            judge "禁止广告地址 切换"
            ;;
        3)
            if [[ "${block_bt}" == "1" ]]; then block_bt=0; else block_bt=1; fi
            routing_save
            v2ray_conf_add
            systemctl restart v2ray
            judge "禁止 BT 协议 切换"
            ;;
        4)
            block_domain_menu
            ;;
        5)
            block_ip_menu
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

v2ray_conf_add() {
    vmess_users_ensure
    local clients_json="" name uuid first=1
    while read -r name uuid; do
        [[ -z "${name}" ]] && continue
        if [[ ${first} -eq 1 ]]; then first=0; else clients_json="${clients_json},"; fi
        clients_json="${clients_json}{\"id\":\"${uuid}\",\"alterId\":0,\"email\":\"${name}\"}"
    done <"${vmess_users_file}"
    [[ -z "${clients_json}" ]] && clients_json="{\"id\":\"$(cat /proc/sys/kernel/random/uuid)\",\"alterId\":0,\"email\":\"vmess\"}"

    local ws_path="${camouflage}"
    [[ -f "${v2ray_qr_config_file}" ]] && ws_path="$(grep '\"path\"' "${v2ray_qr_config_file}" | awk -F '"' '{print $4}')"
    camouflage="${ws_path}"

    local inbound_port=""
    if [[ -f "${v2ray_conf}" ]]; then
        inbound_port="$(grep '\"port\"' "${v2ray_conf}" | head -1 | awk -F ':' '{print $2}' | tr -d ' ,')"
    fi
    [[ -z "${inbound_port}" ]] && inbound_port=$((RANDOM + 10000))
    PORT="${inbound_port}"

    routing_load
    local routing_rules_json routing_ds sniffing_json
    routing_rules_json="$(routing_rules_gen)"
    routing_ds="$(routing_domain_strategy)"
    sniffing_json="$(routing_sniffing_gen)"

    cat >${v2ray_conf} <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "listen": "127.0.0.1",
      "tag": "vmess-in",
      "protocol": "vmess",
      "settings": {
        "clients": [
          ${clients_json}
        ]
      },
${sniffing_json}
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${camouflage}"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query",
      "1.1.1.1",
      "1.0.0.1",
      "8.8.8.8",
      "8.8.4.4",
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "${routing_ds}",
    "rules": [
      ${routing_rules_json}
    ]
  }
}
EOF
    judge "V2Ray 配置写入"
}

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
    chown -R root:root /var/log/v2ray/
    systemctl restart nginx
    judge "Nginx 启动"
    systemctl restart v2ray
    judge "V2ray 启动"
    if [[ -f ${singbox_systemd_file} ]]; then
        systemctl restart sing-box
        judge "sing-box 启动"
    fi
}

enable_process_systemd() {
    systemctl enable v2ray
    judge "设置 v2ray 开机自启"
    systemctl enable nginx
    judge "设置 Nginx 开机自启"
    if [[ -f ${singbox_systemd_file} ]]; then
        systemctl enable sing-box
        judge "设置 sing-box 开机自启"
    fi
}

stop_process_systemd() {
    systemctl stop nginx
    systemctl stop v2ray
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
    journalctl -u sing-box --output cat -f
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
    if [[ -f ${singbox_bin_dir} || -d ${singbox_conf_dir} || -f ${singbox_systemd_file} ]]; then
        echo -e "${OK} ${Green} 是否卸载 sing-box (AnyTLS) [Y/N]? ${Font}"
        read -r uninstall_singbox
        case $uninstall_singbox in
        [yY][eE][sS] | [yY])
            systemctl disable sing-box >/dev/null 2>&1
            systemctl stop sing-box >/dev/null 2>&1
            rm -f ${singbox_systemd_file}
            rm -f ${singbox_bin_dir}
            rm -rf ${singbox_conf_dir}
            rm -f ${anytls_info_file}
            uninstalled_any=1
            echo -e "${OK} ${Green} 已卸载 sing-box (AnyTLS) ${Font}"
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
    if [ -f $v2ray_bin_dir ] || [ -f $v2ray_bin_dir_old/v2ray ]; then
        if grep -q "ws" $v2ray_qr_config_file; then
            shell_mode="ws"
        fi
    fi
    if [[ -f "${singbox_conf}" ]]; then
        if [[ "${shell_mode}" == "None" ]]; then
            shell_mode="anytls"
        else
            shell_mode="${shell_mode}+anytls"
        fi
    fi
}
install_v2ray_ws_tls() {
    is_root
    check_system
    chrony_install
    dependency_install
    basic_optimization
    domain_check
    old_config_exist_check
    port_alterid_set
    v2ray_install
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
    echo "$ol_version" >$version_cmp
    echo "$shell_version" >>$version_cmp
    if [[ "$shell_version" < "$(sort -rV $version_cmp | head -1)" ]]; then
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
    *)
        menu
        ;;
    esac
}
modify_camouflage_path() {
    [[ -z ${camouflage_path} ]] && camouflage_path=1
    sed -i "/location/c \\\tlocation \/${camouflage_path}\/" ${nginx_conf}          #Modify the camouflage path of the nginx configuration file
    sed -i "/\"path\"/c \\\t  \"path\":\"\/${camouflage_path}\/\"" ${v2ray_conf}    #Modify the camouflage path of the v2ray configuration file
    [ -f ${v2ray_qr_config_file} ] && sed -i "/\"path\"/c \\  \"path\": \"\/${camouflage_path}\/\"," ${v2ray_qr_config_file}
    judge "V2ray camouflage path modified"
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

menu() {
    update_sh
    while true; do
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
            ;;
        2)
            v2ray_config_menu
            ;;
        3)
            anytls_config_menu
            ;;
        4)
            view_menu
            ;;
        5)
            cert_menu
            ;;
        6)
            other_menu
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

install_menu() {
    while true; do
        section_title "安装与升级"
        echo -e "${Green}1.${Font} 安装 V2Ray (Nginx+ws+tls)"
        echo -e "${Green}2.${Font} 升级 V2Ray"
        echo -e "${Green}3.${Font} 安装 AnyTLS (sing-box)"
        echo -e "${Green}4.${Font} 升级 sing-box"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            shell_mode="ws"
            install_v2ray_ws_tls
            ;;
        2)
            v2ray_update
            ;;
        3)
            install_anytls
            ;;
        4)
            singbox_update
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

v2ray_config_menu() {
    while true; do
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
            routing_menu
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

anytls_config_menu() {
    while true; do
        section_title "AnyTLS 配置"
        echo -e "${Green}1.${Font} 管理 AnyTLS 用户"
        echo -e "${Green}2.${Font} 变更 AnyTLS 端口"
        echo -e "${Green}0.${Font} 返回上级菜单 \n"
        read -rp "请输入数字：" sub_num
        case ${sub_num} in
        1)
            anytls_user_menu
            ;;
        2)
            anytls_port_change
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

view_menu() {
    while true; do
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
    done
}

cert_menu() {
    while true; do
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
    done
}

other_menu() {
    while true; do
        section_title "其他"
        echo -e "${Green}1.${Font} 卸载"
        echo -e "${Green}2.${Font} 更新 geoip.dat 和 geosite.dat"
        echo -e "${Green}3.${Font} 升级 脚本"
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
            update_sh
            ;;
        0)
            break
            ;;
        *)
            echo -e "${RedBG}请输入正确的数字${Font}"
            ;;
        esac
    done
}

judge_mode
list "$1"
