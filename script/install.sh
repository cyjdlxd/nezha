#!/bin/bash

#======================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+
#   Description: 哪吒面板安装脚本
#   Github: https://github.com/naiba/nezha
#======================================================

NZ_BASE_PATH="/opt/nezha"
NZ_DASHBOARD_PATH="${NZ_BASE_PATH}/dashboard"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="/etc/systemd/system/nezha-agent.service"
NZ_VERSION="v1.0.0"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

os_version=""
os_arch=""

pre_check() {
    command -v systemctl >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi

    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

    # check os
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
    fi

    # os version
    if [[ -f /etc/os-release ]]; then
        os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
    fi
    if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
        os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
    fi

    if [[ x"${release}" == x"centos" ]]; then
        if [[ ${os_version} -le 6 ]]; then
            echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
        fi
    elif [[ x"${release}" == x"ubuntu" ]]; then
        if [[ ${os_version} -lt 16 ]]; then
            echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
        fi
    elif [[ x"${release}" == x"debian" ]]; then
        if [[ ${os_version} -lt 8 ]]; then
            echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
        fi
    fi

    ## os_arch
    if [ $(uname -m | grep '64') != "" ]; then
        os_arch="amd64"
    else
        os_arch="386"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1) ||
        (install_soft curl wget git)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum install $* -y) ||
        (command -v apt >/dev/null 2>&1 && apt install $* -y) ||
        (command -v apt-get >/dev/null 2>&1 && apt-get install $* -y)
}

install_dashboard() {
    install_base

    echo -e "> 安装面板"

    # 哪吒面板文件夹
    mkdir -p $NZ_DASHBOARD_PATH
    chmod 777 -R $NZ_DASHBOARD_PATH

    command -v docker >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "正在安装 Docker"
        bash <(curl -sL https://get.docker.com) >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 get.docker.com${plain}"
            return 0
        fi
        systemctl enable docker.service
        systemctl start docker.service
        echo -e "${green}Docker${plain} 安装成功"
    fi

    command -v docker-compose >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "正在安装 Docker Compose"
        curl -L "https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose >/dev/null 2>&1 &&
            chmod +x /usr/local/bin/docker-compose
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 github.com${plain}"
            return 0
        fi
        echo -e "${green}Docker Compose${plain} 安装成功"
    fi

    echo -e "正在下载 Docker 脚本"
    cd $NZ_DASHBOARD_PATH
    curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/docker-compose.yaml -o docker-compose.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 raw.githubusercontent.com${plain}"
        return 0
    fi

    modify_dashboard_config 0

    echo "默认管理面板地址：域名:8008"

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_agent() {
    install_base

    echo -e "> 安装监控Agent"

    # 哪吒面板文件夹
    mkdir -p $NZ_AGENT_PATH
    chmod 777 -R $NZ_AGENT_PATH

    echo -e "正在下载监控端"
    cd $NZ_DASHBOARD_PATH
    curl -L https://github.com/naiba/nezha/releases/latest/download/nezha-agent_linux_${os_arch}.tar.gz -o nezha-agent_linux_${os_arch}.tar.gz >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 github.com${plain}"
        return 0
    fi
    tar xf nezha-agent_linux_${os_arch}.tar.gz &&
        mv nezha-agent $NZ_AGENT_PATH &&
        rm -rf nezha-agent*

    modify_agent_config 0

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_agent_config() {
    echo -e "> 修改Agent配置"

    cd $NZ_DASHBOARD_PATH
    curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/nezha-agent.service -o $NZ_AGENT_SERVICE >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}文件下载失败，请检查本机能否连接 raw.githubusercontent.com${plain}"
        return 0
    fi

    echo "请先在管理面板上添加服务器，获取到ID和密钥" &&
        read -p "请输入一个解析到面板所在IP的域名（不可套CDN）: " nezha_server_addr &&
        read -p "请输入Agent ID: " nezha_client_id &&
        read -p "请输入Agent 密钥: " nezha_client_secret
    if [[ -z "${nezha_server_addr}" || -z "${nezha_client_id}" || -z "${nezha_client_secret}" ]]; then
        echo -e "${red}所有选项都不能为空${plain}"
        before_show_menu
        return 1
    fi

    sed -i "s/nezha_server_addr/${nezha_server_addr}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nezha_client_id/${nezha_client_id}/" ${NZ_AGENT_SERVICE}
    sed -i "s/nezha_client_secret/${nezha_client_secret}/" ${NZ_AGENT_SERVICE}

    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"

    systemctl daemon-reload
    systemctl enable nezha-agent
    systemctl restart nezha-agent

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_dashboard_config() {
    echo -e "> 修改面板配置"

    mkdir -p $NZ_DASHBOARD_PATH/data

    curl -L https://raw.githubusercontent.com/naiba/nezha/master/script/config.yaml -o ${NZ_DASHBOARD_PATH}/data/config.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 raw.githubusercontent.com${plain}"
        return 0
    fi

    echo "关于管理员 GitHub ID：复制自己GitHub头像图片地址，/[ID].png 多个用英文逗号隔开 id1,id2,id3" &&
        read -p "请输入 ID 列表: " nz_admin_ids &&
        echo "关于 GitHub Oauth2 应用：在 https://github.com/settings/developers 创建，无需审核 Callback 填 http(s)://域名或IP/oauth2/callback" &&
        read -p "请输入 GitHub Oauth2 应用的 Client ID: " nz_github_oauth_client_id &&
        read -p "请输入 GitHub Oauth2 应用的 Client Secret: " nz_github_oauth_client_secret &&
        read -p "请输入站点标题: " nz_site_title
    if [[ -z "${nz_admin_ids}" || -z "${nz_github_oauth_client_id}" || -z "${nz_github_oauth_client_secret}" || -z "${nz_site_title}" ]]; then
        echo -e "${red}所有选项都不能为空${plain}"
        before_show_menu
        return 1
    fi

    sed -i "s/nz_admin_ids/${nz_admin_ids}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_github_oauth_client_id/${nz_github_oauth_client_id}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_github_oauth_client_secret/${nz_github_oauth_client_secret}/" ${NZ_DASHBOARD_PATH}/data/config.yaml
    sed -i "s/nz_site_title/${nz_site_title}/" ${NZ_DASHBOARD_PATH}/data/config.yaml

    echo -e "面板配置 ${green}修改成功，请稍等重启生效${plain}"

    restart_dashboard

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_dashboard() {
    cd $NZ_DASHBOARD_PATH
    docker-compose down
    docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒面板 重启成功${plain}"
    else
        echo -e "${red}重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_dashboard() {
    cd $NZ_DASHBOARD_PATH && docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒面板 启动成功${plain}"
    else
        echo -e "${red}启动失败，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_dashboard() {
    cd $NZ_DASHBOARD_PATH && docker-compose down
    if [[ $? == 0 ]]; then
        echo -e "${green}哪吒面板 停止成功${plain}"
    else
        echo -e "${red}停止失败，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_dashboard_log() {
    cd $NZ_DASHBOARD_PATH && docker-compose logs -f

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_usage() {
    echo "哪吒面板 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "./nbdomain.sh                          - 显示管理菜单"
    echo "./nbdomain.sh install_dashboard        - 安装面板端"
    echo "./nbdomain.sh modify_dashboard_config  - 修改面板配置"
    echo "./nbdomain.sh start_dashboard          - 启动面板"
    echo "./nbdomain.sh stop_dashboard           - 停止面板"
    echo "./nbdomain.sh restart_dashboard        - 重启面板"
    echo "./nbdomain.sh show_dashboard_log       - 查看面板日志"
    echo "------------------------------------------"
    echo "./nbdomain.sh install_agent            - 安装监控Agent"
    echo "./nbdomain.sh modify_agent_config      - 修改Agent配置"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
    ${green}哪吒面板管理脚本${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/naiba/nezha ---
    ${green}0.${plain} 退出脚本
    ————————————————
    ${green}1.${plain} 安装面板端
    ${green}2.${plain} 修改面板配置
    ${green}3.${plain} 启动面板
    ${green}4.${plain} 停止面板
    ${green}5.${plain} 重启面板
    ${green}6.${plain} 查看面板日志
    ————————————————
    ${green}7.${plain} 安装监控Agent
    ${green}8.${plain} 修改Agent配置
    "
    echo && read -p "请输入选择 [0-8]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        install_dashboard
        ;;
    2)
        modify_dashboard_config
        ;;
    3)
        start_dashboard
        ;;
    4)
        stop_dashboard
        ;;
    5)
        restart_dashboard
        ;;
    6)
        show_dashboard_log
        ;;
    7)
        install_agent
        ;;
    8)
        modify_agent_config
        ;;
    *)
        echo -e "${red}请输入正确的数字 [0-7]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
    "install_dashboard")
        install_dashboard 0
        ;;
    "modify_dashboard_config")
        modify_dashboard_config 0
        ;;
    "start_dashboard")
        start_dashboard 0
        ;;
    "stop_dashboard")
        stop_dashboard 0
        ;;
    "restart_dashboard")
        restart_dashboard 0
        ;;
    "show_dashboard_log")
        show_dashboard_log 0
        ;;
    "install_agent")
        install_agent 0
        ;;
    "modify_agent_config")
        modify_agent_config 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
