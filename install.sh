#! /bin/bash
# 获取当前脚本的软链接路径
SYMLINK_PATH=$(readlink -f "$0")
# DNMP目录
DNMP_DIR=$(dirname "$SYMLINK_PATH")
# 路径转换
DNMP_DIR=$(realpath "$DNMP_DIR")
# 加载公共变量
source $DNMP_DIR/common.sh
# 加载ENV
source $DNMP_DIR/.env

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echoRR "Please run this script with root privileges."
    exit 1
fi

# 更新源
echoSB "Update Source."
apt update
# 安装依赖包
echoSB "Install Necessary Packages."
apt install -y curl gnupg lsb-release unzip gawk zstd pv bc tzdata


# 创建软链接
rm -rf /usr/local/bin/vhost.sh
chmod +x $DNMP_DIR/vhost.sh
ln -s $DNMP_DIR/vhost.sh /usr/local/bin/vhost.sh
