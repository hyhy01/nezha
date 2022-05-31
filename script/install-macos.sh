#!/bin/bash

#========================================================
#   System Required: MacOS 12 /
#     Arch 未测试
#   Description: 哪吒监控安装脚本
#   Github: https://github.com/naiba/nezha
#========================================================

NZ_BASE_PATH="$HOME/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_SERVICE="/Library/LaunchDaemons/nezha-agent.plist"
NZ_VERSION="v0.10.6"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""

pre_check() {
    command -v brew >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "$red 未找到 brew 命令，请安装homebrew！"
        exit 1
    fi

    # check root 这里主要因为brew无法使用root权限运行
    [[ $EUID -eq 0 ]] && echo -e "${red}错误: ${plain} 不能使用root用户运行此脚本！\n" && exit 1

    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
    elif [[ $(uname -m | grep 'arm64\|aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
    elif [[ $(uname -m | grep 's390x') != "" ]]; then
        os_arch="s390x"
    elif [[ $(uname -m | grep 'riscv64') != "" ]]; then
        os_arch="riscv64"
    fi

    ## China_IP
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 10 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            echo "根据ipapi.co提供的信息，当前IP可能在中国"
            read -e -r -p "是否选用中国镜像完成安装? [Y/n] " input
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;

            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi

    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/naiba/nezha/master"
        GITHUB_URL="github.com"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" "
        Docker_IMG="ghcr.io\/naiba\/nezha-dashboard"
    else
        GITHUB_RAW_URL="jihulab.com/nezha/nezha/-/raw/master"
        GITHUB_URL="dn-dao-github-mirror.daocloud.io"
        Get_Docker_URL="get.daocloud.io/docker"
        Get_Docker_Argu=" -s docker --mirror Aliyun"
        Docker_IMG="registry.cn-shanghai.aliyuncs.com\/naibahq\/nezha-dashboard"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> 更新脚本"
    mkdir ./tmp
    curl -sL https://${GITHUB_RAW_URL}/script/install-macos.sh -o ./tmp/nezha.sh
    new_version=$(cat ./tmp/nezha.sh | grep "NZ_VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/install-macos.sh"
        return 1
    fi
    echo -e "当前最新版本为: ${new_version}"
    mv -f ./tmp/nezha.sh "$HOME/nezha.sh" && chmod a+x "$HOME/nezha.sh"

    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec "$HOME/nezha.sh"
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 ) ||
        (install_soft curl wget git unzip)
}

install_soft() {
    # Arch官方库不包含selinux等组件
    (command -v yum >/dev/null 2>&1 && yum makecache && yum install $* selinux-policy -y) ||
        (command -v apt >/dev/null 2>&1 && apt update && apt install $* selinux-utils -y) ||
        (command -v pacman >/dev/null 2>&1 && pacman -Syu $*) ||
        (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install $* selinux-utils -y)||
        (command -v brew >/dev/null 2>&1 && brew install $*)
}


install_agent() {
    install_base

    echo -e "> 安装监控Agent"

    echo -e "正在获取监控Agent版本号"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/naiba/nezha/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://fastly.jsdelivr.net/gh/naiba/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
    fi
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://gcore.jsdelivr.net/gh/naiba/nezha/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/naiba\/nezha@/v/g')
    fi

    if [ ! -n "$version" ]; then
        echo -e "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/naiba/nezha/releases/latest"
        return 0
    else
        echo -e "当前最新版本为: ${version}"
    fi

    # 哪吒监控文件夹
    mkdir -p "$NZ_AGENT_PATH"
    echo "$NZ_AGENT_PATH"
    chmod -R 777  "$NZ_AGENT_PATH"

    echo -e "正在下载监控端"
    echo "https://${GITHUB_URL}/naiba/nezha/releases/download/${version}/nezha-agent_darwin_${os_arch}.zip"
    wget -t 2 -T 10 -O nezha-agent_darwin_${os_arch}.zip https://${GITHUB_URL}/naiba/nezha/releases/download/${version}/nezha-agent_darwin_${os_arch}.zip >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
        return 0
    fi

    unzip -qo nezha-agent_darwin_${os_arch}.zip &&
    mv nezha-agent "$NZ_AGENT_PATH" &&
    rm -rf nezha-agent_darwin_${os_arch}.zip README.md

    if [ $# -ge 3 ]; then
        modify_agent_config "$@"
    else
        modify_agent_config 0
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

modify_agent_config() {
    echo -e "> 修改Agent配置"

    if [ $# -lt 3 ]; then
        echo "请先在管理面板上添加Agent，记录下密钥" &&
            read -ep "请输入一个解析到面板所在IP的域名（不可套CDN）: " nz_grpc_host &&
            read -ep "请输入面板RPC端口: (5555)" nz_grpc_port &&
            read -ep "请输入Agent 密钥: " nz_client_secret
        if [[ -z "${nz_grpc_host}" || -z "${nz_client_secret}" ]]; then
            echo -e "${red}所有选项都不能为空${plain}"
            before_show_menu
            return 1
        fi
        if [[ -z "${nz_grpc_port}" ]]; then
            nz_grpc_port=5555
        fi
    else
        nz_grpc_host=$1
        nz_grpc_port=$2
        nz_client_secret=$3
    fi

    service_file="
    <?xml version=\"1.0\"encoding=\"utf-8\"?>
    <!DOCTYPE plist PUBLIC\"-//Apple//DTD PLIST 1.0//EN\"
    \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
    <plist version=\"1.0\">
        <dict>
            <key>KeepAlive</key>
            <true/>
            <key>RunAtLoad</key>
            <true/>
            <key>Label</key>
            <string>nezha-agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>${NZ_AGENT_PATH}/nezha-agent</string>
                <string>-s=${nz_grpc_host}:${nz_grpc_port}</string>
                <string>-p=${nz_client_secret}</string>
                <string>-d</string>
            </array>
            <key>StandardOutPath</key>
            <string>${NZ_AGENT_PATH}/nezha-agent.log</string>
            <key>StandardErrorPath</key>
            <string>${NZ_AGENT_PATH}/nezha-agent.log</string>
        </dict>
    </plist>
    "
    #暂不支持额外参数
#    shift 3
#    if [ $# -gt 0 ]; then
#        args=" $*"
#        sed -i "/ExecStart/ s/$/${args}/" ${NZ_AGENT_SERVICE}
#    fi
    echo "系统可能要求你输入系统密码!"
    echo "$service_file" |sudo tee ${NZ_AGENT_SERVICE} >/dev/null 2>&1

    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"

    sudo launchctl unload /Library/LaunchDaemons/nezha-agent.plist >/dev/null 2>&1
    sudo launchctl load /Library/LaunchDaemons/nezha-agent.plist
#    if [[ $? != 0 ]]; then #无法通过$?判断是否启动成功
#        echo -e "$red 服务启动失败"
#        exit 1
#    fi


    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}


show_agent_log() {
    echo -e "> 获取Agent日志"

    tail -n 500 "$NZ_AGENT_PATH/nezha-agent.log"

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_agent() {
    echo -e "> 卸载Agent"

    sudo launchctl unload /Library/LaunchDaemons/nezha-agent.plist
    sudo rm -rf $NZ_AGENT_SERVICE >/dev/null 2>&1

    sudo rm -rf "$NZ_AGENT_PATH" >/dev/null 2>&1
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_agent() {
    echo -e "> 重启Agent"

    sudo launchctl unload /Library/LaunchDaemons/nezha-agent.plist
    sudo launchctl load /Library/LaunchDaemons/nezha-agent.plist

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}
status_agent() {
    echo -e "> Agent状态"

    sudo launchctl list | grep nezha-agent

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${NZ_BASE_PATH} > /dev/null 2>&1)" ]; then
        sudo rm -rf "${NZ_BASE_PATH}"
    fi
}

show_usage() {
    echo "哪吒监控 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./nezha.sh install_agent              - 安装监控Agent"
    echo "./nezha.sh modify_agent_config        - 修改Agent配置"
    echo "./nezha.sh show_agent_log             - 查看Agent日志"
    echo "./nezha.sh uninstall_agent            - 卸载Agent"
    echo "./nezha.sh restart_agent              - 重启Agent"
    echo "./nezha.sh status_agent               - Agent允许状态"
    echo "./nezha.sh update_script              - 更新脚本"
    echo "--------------------------------------------------------"
}

show_menu() {
    echo -e "
    ${green}哪吒监控管理脚本${plain} ${red}${NZ_VERSION}${plain}
    --- https://github.com/naiba/nezha ---
    ${green}1.${plain}  安装监控Agent
    ${green}2.${plain}  修改Agent配置
    ${green}3.${plain} 查看Agent日志
    ${green}4.${plain} 卸载Agent
    ${green}5.${plain} 重启Agent
    ${green}6.${plain} Agent运行状态
    ————————————————-
    ${green}7.${plain} 更新脚本
    ————————————————-
    ${green}0.${plain}  退出脚本
    "
    echo && read -ep "请输入选择 [0-7]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        install_agent
        ;;
    2)
        modify_agent_config
        ;;
    3)
        show_agent_log
        ;;
    4)
        uninstall_agent
        ;;
    5)
        restart_agent
        ;;
    6)
        status_agent
        ;;
    7)
        update_script
        ;;
    *)
        echo -e "${red}请输入正确的数字 [0-7]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
    "install_agent")
        shift
        if [ $# -ge 3 ]; then
            install_agent "$@"
        else
            install_agent 0
        fi
        ;;
    "modify_agent_config")
        modify_agent_config 0
        ;;
    "show_agent_log")
        show_agent_log 0
        ;;
    "uninstall_agent")
        uninstall_agent 0
        ;;
    "restart_agent")
        restart_agent 0
        ;;
    "status_agent")
        status_agent 0
        ;;
    "update_script")
        update_script 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
