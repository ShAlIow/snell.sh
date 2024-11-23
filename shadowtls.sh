#!/bin/bash
# =========================================
# 作者: jinqians
# 日期: 2024年11月
# 网站：jinqians.com
# 描述: 这个脚本用于安装和管理 ShadowTLS V3
# =========================================

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 安装目录和配置文件
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/shadowtls"
CONFIG_FILE="${CONFIG_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/shadowtls.service"

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本${RESET}"
        exit 1
    fi
}

# 安装必要的工具
install_requirements() {
    apt update
    apt install -y wget curl jq
}

# 获取最新版本
get_latest_version() {
    latest_version=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | jq -r .tag_name)
    if [ -z "$latest_version" ]; then
        echo -e "${RED}获取最新版本失败${RESET}"
        exit 1
    fi
    echo "$latest_version"
}

# 检查 Snell 是否已安装
check_snell() {
    if ! command -v snell-server &> /dev/null; then
        echo -e "${RED}未检测到 Snell V4，请先安装 Snell${RESET}"
        return 1
    fi
    return 0
}

# 获取 Snell 配置
get_snell_config() {
    if [ ! -f "/etc/snell/snell-server.conf" ]; then
        echo -e "${RED}未找到 Snell 配置文件${RESET}"
        return 1
    fi
    
    # 读取 Snell 配置
    local snell_port=$(grep -oP 'listen = \K[0-9]+' /etc/snell/snell-server.conf || echo "")
    if [ -z "$snell_port" ]; then
        echo -e "${RED}无法读取 Snell 端口配置${RESET}"
        return 1
    fi
    
    echo "$snell_port"
    return 0
}

# 安装 ShadowTLS
install_shadowtls() {
    echo -e "${CYAN}正在安装 ShadowTLS...${RESET}"
    
    # 检查 Snell 是否已安装
    if ! check_snell; then
        echo -e "${YELLOW}请先安装 Snell V4 再安装 ShadowTLS${RESET}"
        return 1
    fi
    
    # 获取 Snell 端口
    local snell_port=$(get_snell_config)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 获取系统架构
    arch=$(uname -m)
    case $arch in
        x86_64)
            arch="x86_64-unknown-linux-musl"
            ;;
        aarch64)
            arch="aarch64-unknown-linux-musl"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: $arch${RESET}"
            exit 1
            ;;
    esac
    
    # 获取最新版本
    version=$(get_latest_version)
    
    # 下载并安装
    download_url="https://github.com/ihciah/shadow-tls/releases/download/${version}/shadow-tls-${arch}"
    wget "$download_url" -O "$INSTALL_DIR/shadow-tls"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 ShadowTLS 失败${RESET}"
        exit 1
    fi
    
    chmod +x "$INSTALL_DIR/shadow-tls"
    
    # 生成随机密码
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    
    # 获取用户输入
    read -rp "请输入 ShadowTLS 监听端口 (1-65535): " listen_port
    read -rp "请输入 TLS 伪装域名 (例如: www.microsoft.com): " tls_domain
    
    # 创建配置文件
    cat > "$CONFIG_FILE" << EOF
{
    "listen": "0.0.0.0:${listen_port}",
    "server": "127.0.0.1:${snell_port}",
    "tls": {
        "server_name": "${tls_domain}"
    },
    "password": "${password}"
}
EOF
    
    # 创建系统服务
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ShadowTLS Service
After=network.target snell.service
Requires=snell.service

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=$INSTALL_DIR/shadow-tls --config $CONFIG_FILE server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    # 启动服务
    systemctl daemon-reload
    systemctl enable shadowtls
    systemctl start shadowtls
    
    # 清晰地显示配置信息
    echo -e "\n${GREEN}=== ShadowTLS 安装成功 ===${RESET}"
    echo -e "\n${YELLOW}=== 服务器配置 ===${RESET}"
    echo -e "监听端口：${listen_port}"
    echo -e "后端 Snell 端口：${snell_port}"
    
    echo -e "\n${YELLOW}=== Surge/Stash 配置参数 ===${RESET}"
    echo -e "shadow-tls-password=${password}"
    echo -e "shadow-tls-sni=${tls_domain}"
    echo -e "shadow-tls-version=3"
    
    echo -e "\n${YELLOW}=== 完整配置示例 ===${RESET}"
    echo -e "Snell = snell, [服务器IP], ${listen_port}, psk=[Snell密码], version=4, shadow-tls-password=${password}, shadow-tls-sni=${tls_domain}, shadow-tls-version=3"
    
    echo -e "\n${GREEN}配置已保存至：${CONFIG_FILE}${RESET}"
    echo -e "${GREEN}服务已启动并设置为开机自启${RESET}"
}

# 卸载 ShadowTLS
uninstall_shadowtls() {
    echo -e "${YELLOW}正在卸载 ShadowTLS...${RESET}"
    
    systemctl stop shadowtls
    systemctl disable shadowtls
    
    rm -f "$SERVICE_FILE"
    rm -f "$INSTALL_DIR/shadow-tls"
    rm -rf "$CONFIG_DIR"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}ShadowTLS 已成功卸载${RESET}"
}

# 查看配置
view_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${CYAN}ShadowTLS 配置信息：${RESET}"
        cat "$CONFIG_FILE"
        echo -e "\n${CYAN}服务状态：${RESET}"
        systemctl status shadowtls
    else
        echo -e "${RED}配置文件不存在${RESET}"
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${CYAN}ShadowTLS 管理菜单${RESET}"
        echo -e "${YELLOW}1. 安装 ShadowTLS${RESET}"
        echo -e "${YELLOW}2. 卸载 ShadowTLS${RESET}"
        echo -e "${YELLOW}3. 查看配置${RESET}"
        echo -e "${YELLOW}4. 返回上级菜单${RESET}"
        echo -e "${YELLOW}0. 退出${RESET}"
        
        read -rp "请选择操作 [0-4]: " choice
        
        case "$choice" in
            1)
                install_shadowtls
                ;;
            2)
                uninstall_shadowtls
                ;;
            3)
                view_config
                ;;
            4)
                return 0
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${RESET}"
                ;;
        esac
    done
}

# 检查root权限
check_root

# 如果直接运行此脚本，则显示主菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi