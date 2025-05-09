#!/bin/bash
# 用户
NGINX_USER=www-data
# 组
NGINX_GROUP=www-data
# 获取当前脚本的软链接路径
SYMLINK_PATH=$(readlink -f "$0")
# DNMP目录
DNMP_DIR=$(dirname "$SYMLINK_PATH")
# 路径转换
DNMP_DIR=$(realpath "$DNMP_DIR")
# 加载公共变量
source $DNMP_DIR/common.sh
# 加载.env
source $DNMP_DIR/.env
# SSL目录
SSL_DIR=$SSL_CERTBOT_DIR/live
# 虚拟主机配置文件
VHOST_CONF_FILE=$DNMP_DIR/nginx/vhost.conf
# 输入的域名
INPUT_DOMAIN_NAME=""
# 需要操作的站点虚拟主机名
SITE_HOSTNAME=""
# 验证域名
function input_domain {
    # 接收输入域名
    while true; do
        # 域名
        local domain_names
        # 域名是否存在
        local domain_exists=0
        # 请输入域名
        echo -ne "$SB请输入域名(eg:demo.com):$ED "
        # 接收输入域名
        read -r INPUT_DOMAIN_NAME
        # 将域名转换为小写
        INPUT_DOMAIN_NAME=$(echo $INPUT_DOMAIN_NAME | tr 'A-Z' 'a-z')
        # 验证域名是否符合规范
        INPUT_DOMAIN_NAME=$(echo $INPUT_DOMAIN_NAME | awk '/^[a-z0-9][-a-z0-9]{0,62}(\.[a-z0-9][-a-z0-9]{0,62})+$/{print $0}')
        # 验证域名是否符合规范
        if [ -z "$INPUT_DOMAIN_NAME" ]; then
            echoRC "域名有误,请重新输入!!!"
            continue
        else
            # 从配置文件中提取所有的域名并检查是否存在
            domain_names=$(find "$VHOSTS_CONF_DIR" -type f -name "*.conf" -exec grep -oP 'server_name\s+\K[^\s;]+' {} \; | tr '\n' ' ')
            # 遍历域名
            for item in $domain_names; do
                # 检查域名是否存在
                if [ "$INPUT_DOMAIN_NAME" = "$item" ]; then
                    echoCC '域名已存在.'
                    # 域名已存在
                    domain_exists=1
                    break
                fi
            done
            # 如果域名已存在,则继续输入
            if [ $domain_exists -eq 1 ]; then
                continue
            fi
        fi
        break
    done
}
# 检测数据库是否存在
function check_db_exists {
    # 如果数据库名不存在,则返回1
    if [ -z "$1" ]; then
        return 2
    fi
    # 判断数据库是否存在 0 存在 1 不存在
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "SHOW DATABASES LIKE '$1';" | grep -q "$1"
    return $?
}
# 随机字符串
function random_str {
    local length=10
    if [ -n "$1" ]; then
        length=$1
    fi
    # 生成随机字符串 数字 字母 大小写
   echo $(head -c $length /dev/urandom | base64 | tr -d '/' | tr -d '=' | tr -d '+')
}
# Install WordPress
function install_wp {
    # 接收用户输入
    echo -ne "$BC请输入站点管理员账号(默认:admin):$ED "
    read -a wp_user; [ -z "$wp_user" ] && wp_user=admin 
    echo -ne "$BC请输入站点管理员密码(默认:admin):$ED "
    read -a wp_pass; [ -z "$wp_pass" ] && wp_pass=admin
    echo -ne "$BC请输入站点管理员邮箱(默认:admin@$INPUT_DOMAIN_NAME):$ED "
    read -a wp_mail; [ -z "$wp_mail" ] && wp_mail="admin@$INPUT_DOMAIN_NAME"
    # 数据库前缀
    local db_prefix=$(random_str 3)_
    # 转小写
    db_prefix=$(echo $db_prefix | tr 'A-Z' 'a-z')
    # 生成数据库密码
    local database_password=$(random_str 12)
    # Docker 容器内部 站点文档根目录
    local site_doc_root=/wwwroot/$INPUT_DOMAIN_NAME
    # 创建数据库
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "CREATE DATABASE \`$DATABASE_NAME\`;"
    # 创建数据库用户
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "CREATE USER \`$DATABASE_NAME\`@'%' IDENTIFIED BY '$database_password';"
    # 授权数据库
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "GRANT ALL PRIVILEGES ON \`$DATABASE_NAME\`.* TO \`$DATABASE_NAME\`@'%';"
    # 下载WP程序 wp core download --locale=zh_CN --allow-root
    docker exec nginx wp core download --path=$site_doc_root --allow-root
    # 创建数据库配置文件
    docker exec nginx wp config create --dbname=$DATABASE_NAME --dbuser=$DATABASE_NAME --dbpass=$database_password --dbprefix=$db_prefix --dbhost=mysql:3306 --path=$site_doc_root --allow-root --quiet
    # 安装WordPress程序
    docker exec nginx wp core install --url="https://$INPUT_DOMAIN_NAME" --title="My Blog" --admin_user=$wp_user --admin_password=$wp_pass --admin_email=$wp_mail --skip-email --path=$site_doc_root --allow-root
    # WP配置文件中添加新常量
    local wp_const="\ndefine('WP_POST_REVISIONS', false);"
    # 插入到文件
    sed -i "/\$table_prefix/a\\$wp_const" $SITE_DOC_ROOT/wp-config.php
}
# 创建站点
function create_site {
    # 请输入域名
    input_domain
    # 站点文档根
    SITE_DOC_ROOT=$VHOSTS_ROOT/$INPUT_DOMAIN_NAME
    # 数据库名
    DATABASE_NAME="sql_$(echo "$INPUT_DOMAIN_NAME" | tr '.' '_' | tr '-' '_')"
    # 判断站点目录是否存在
    if [ -d "$SITE_DOC_ROOT" ]; then
        echoRC "站点目录已存在."
        return $?
    fi
    # 检测数据库是否存在
    check_db_exists $DATABASE_NAME
    if [ $? -eq 0 ]; then
        echoRC "数据库已存在."
        return $?
    elif [ $? -eq 2 ]; then
        echoRC "数据库名不能为空."
        return $?
    fi
    # 自动创建站点目录
    mkdir -p "$SITE_DOC_ROOT"
    # 自动创建站点配置文件
    cp -rf $VHOST_CONF_FILE $VHOSTS_CONF_DIR/$INPUT_DOMAIN_NAME.conf
    # 替换域名
    sed -i "s/default_replace_8888/$INPUT_DOMAIN_NAME/" $VHOSTS_CONF_DIR/$INPUT_DOMAIN_NAME.conf
    # 安装WordPress
    echo -ne "$BC是否安装WordPrss(y/N):$ED "
    read -a iswp
    # 如果输入为空,则默认不安装
    if [ -z "$iswp" ]; then
        iswp=n
    fi
    # 如果输入为y或Y,则安装WordPress
    if [ "$iswp" = "y" -o "$iswp" = "Y" ]; then
        install_wp
    else
        echo 'This a Temp Site.' > $SITE_DOC_ROOT/index.php
    fi
    iswp=$(echo $iswp | tr 'a-z' 'A-Z')
    # 修改文件权限 - 使用容器内的路径
    docker exec nginx chown -R $NGINX_USER:$NGINX_GROUP /wwwroot/$INPUT_DOMAIN_NAME
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
    # 输出成功
    echo -e "${CC}站点创建成功${ED}: ${SB}WordPress [${iswp}]${ED}"
    # 站点链接
    echoGC "站点链接: https://$INPUT_DOMAIN_NAME"
    # 输出站点目录
    echoGC "站点目录: $SITE_DOC_ROOT"
}
# 获取站点虚拟主机名
function site_hostname_get {
    # 声明局部数组
    local -a sites
    # 声明局部变量
    local site_name
    # 使用通配符直接读取到数组
    sites=("$VHOSTS_CONF_DIR"/*)
    # 如果目录为空，则退出
    if [ ${#sites[@]} -eq 0 ]; then
        echoCC "没有找到任何站点"
        return 1
    fi
    # 去除路径前缀，只保留站点名
    for i in "${!sites[@]}"; do
        sites[$i]=$(basename "${sites[$i]}")
    done
    # 显示站点列表
    local i=1
    for site in "${sites[@]}"; do
        site_name=$(basename "${site%.*}")
        echo -e "${CC}${i}${ED}.${LG}${site_name}${ED}"
        ((i++))
    done
    # 读取用户输入并验证
    while true; do
        echo -ne "${SB}请输入站点序号(${ED}1-${#sites[@]}${SB}): ${ED}"
        read -a site_index
        # 验证输入是否为数字
        if ! [[ "$site_index" =~ ^[0-9]+$ ]]; then
            echoRC "请输入有效的数字"
            continue
        fi
        # 验证范围
        if [ "$site_index" -lt 1 ] || [ "$site_index" -gt ${#sites[@]} ]; then
            echoRC "请输入 1-${#sites[@]} 之间的数字"
            continue
        fi
        break
    done
    # 获取选择的站点名（数组索引从0开始，所以要减1）
    site_name="${sites[$((site_index-1))]}"
    # 判断是否以 .conf 结尾
    if [[ "$site_name" =~ \.conf$ ]]; then
        SITE_HOSTNAME="${site_name%.*}"
    else
        SITE_HOSTNAME="$site_name"
    fi
    echo -e "${PC}SITE:${ED} ${SITE_HOSTNAME}"
    return 0
}
# 查询是否存在站点
function site_exists {
    # 统计指定目录下有多少个 .conf 文件
    local conf_count=$(find "$VHOSTS_CONF_DIR" -type f -name "*.conf" | wc -l)
    # 如果目录下没有 .conf 文件,则退出
    if [ $conf_count -eq 0 ]; then
        echoCC "没有找到任何站点"
        return 1
    fi
    return 0
}
# 追加域名
function site_append_domain {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 获取站点虚拟主机名
    site_hostname_get
    # 请输入域名
    input_domain
    # 虚拟主机配置文件
    local site_conf_file=$VHOSTS_CONF_DIR/$SITE_HOSTNAME.conf
    # 在配置文件中追加域名 先找到 server_name 然后追加域名
    sed -i '/server_name/ s/;/ '"$INPUT_DOMAIN_NAME"';/' $site_conf_file
    # 获取站点绑定的域名列表
    local domain_list=$(sed -n 's/.*server_name\s\+\(.*\);/\1/p' $site_conf_file)
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
    # 输出成功
    echo -e "${GC}域名追加成功:${ED} ${CC}$domain_list${ED}"
}
# 安装SSL证书
function site_install_ssl {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 判断 acme.sh 是否安装
    if ! command -v certbot &> /dev/null; then
        # 安装 acme.sh
        apt install certbot -y
    fi
    # 获取站点虚拟主机名
    site_hostname_get
    # 虚拟主机配置文件
    local site_conf_file=$VHOSTS_CONF_DIR/$SITE_HOSTNAME.conf
    # 获取站点绑定的域名列表
    local domain_list=$(sed -n 's/.*server_name\s\+\(.*\);/\1/p' $site_conf_file)
    # 转成数组
    domain_list_array=($domain_list)
    echo -e "${SB}需要申请证书域名:${ED} ${domain_list}"
    # 询问用户是否域名解析成功
    echo -ne "${CC}确认域名解析成功?${ED}[${SB}y/n${ED}${CC}]:${ED} "
    read -a num2
    case $num2 in 
        y) ;;
        n) return ;;
        *) echoRC '输入有误.' && return ;;
    esac
    # 转成指定格式字符串  eg: -d demo.com -d www.demo.com
    local domain_list_str=""
    for domain in "${domain_list_array[@]}"; do
        domain_list_str="$domain_list_str -d $domain"
    done
    # 开始申请证书
    echo -e "${SB}开始申请证书${ED}"
    certbot certonly --webroot -w $VHOSTS_ROOT/$SITE_HOSTNAME --email $CERTBOT_EMAIL --agree-tos --no-eff-email $domain_list_str
    if [ $? -eq 0 ]; then
        # 修改配置文件 去掉 #ssl_certificate 和 #ssl_certificate_key 前面的# 启用ssl
        sed -i 's/#ssl_/ssl_/' $site_conf_file
        sed -i 's/#add_header Strict-Transport-Security/add_header Strict-Transport-Security/' $site_conf_file
        sed -i 's/#error_page 497/error_page 497/' $site_conf_file
        sed -i 's/#listen 443 ssl/listen 443 ssl/' $site_conf_file
        # 输出成功
        echoCC "证书启用成功"
    else
        echoRC "证书申请失败"
    fi
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
}
# 删除站点
function site_delete {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 获取站点虚拟主机名
    site_hostname_get
    # 询问是否删除
    echo -ne "${SB}完全删除站点(包含备份)?[${ED}y/n${SB}]:${ED} "
    read -a num2
    case $num2 in 
        y) ;;
        n) return ;;
        *) echoRC '输入有误.' && return ;;
    esac
    # 数据库名
    local database_name="sql_$(echo "$SITE_HOSTNAME" | tr '.' '_' | tr '-' '_')"
    # 删除站点目录
    local site_dir="$VHOSTS_ROOT/$SITE_HOSTNAME"
    # 防止误删
    if [ "${site_dir%/}" != "${VHOSTS_ROOT%/}" ]; then
        # 删除站点目录
        rm -rf "$site_dir"
    fi
    # 检查数据库是否存在
    check_db_exists $database_name
    if [ $? -eq 0 ]; then
        # 删除站点数据库
        docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "DROP DATABASE \`$database_name\`;"
        # 删除站点数据库用户
        docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "DROP USER \`$database_name\`@'%';"
    elif [ $? -eq 1 ]; then
        echoYC "数据库不存在. 跳过删除."
    else
        echoRC "数据库名为空."
    fi
    # 删除站点配置文件
    rm -rf $VHOSTS_CONF_DIR/$SITE_HOSTNAME.conf
    # 删除备份
    rm -rf $BACKUP_STORAGE_DIR/$SITE_HOSTNAME.*
    # 判断证书是否存在
    if [ -d "$SSL_DIR/$SITE_HOSTNAME" ]; then
        # certbot 删除SSL证书
        certbot delete --cert-name $SITE_HOSTNAME -n
    fi
    # 删除站点日志文件
    rm -rf $LOGS_ROOT/nginx/$SITE_HOSTNAME.*
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
    # 输出成功
    echoCC "站点删除成功"
}
# 备份站点
function site_backup {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 创建备份目录
    mkdir -p $BACKUP_STORAGE_DIR
    # 获取站点虚拟主机名
    site_hostname_get
    # 站点目录根目录
    local site_root_path=$VHOSTS_ROOT/$SITE_HOSTNAME
    # 打包文件路径
    local save_backup_file="$BACKUP_STORAGE_DIR/${SITE_HOSTNAME}.$(date +"%Y%m%d_%H%M%S").tar.zst"
    # 定义数据库文件导出路径
    local save_database_file="$site_root_path/db.sql"
    # 数据库名
    local database_name="sql_$(echo "$SITE_HOSTNAME" | tr '.' '_' | tr '-' '_')"
    # 检查数据库是否存在
    check_db_exists $database_name
    if [ $? -eq 1 ]; then
        echoCC "数据库不存在."
        return $?
    elif [ $? -eq 2 ]; then
        echoCC "数据库名不能为空."
        return $?
    fi
    # 导出数据库
    docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysqldump -uroot $database_name > "$save_database_file"
    # 是否导出数据库
    if [ $? -eq 0 ]; then
        echoCC "数据库导出成功"
    else
        echoRC "数据库导出失败"
        return $?
    fi
    # 创建压缩备份
    tar -I zstd -cf "$save_backup_file" -C "$site_root_path" .
    # 检查备份是否成功
    if [ $? -eq 0 ]; then
        echoSB "备份文件列表, 总容量: $(du -sh $BACKUP_STORAGE_DIR)"
        # 查看备份
        ls -ghGA $BACKUP_STORAGE_DIR | awk 'BEGIN{OFS="\t"} NR > 1 {print $3, $7}'
    else
        echoRC "备份失败."
    fi
    # 删除数据库文件
    rm -rf $save_database_file
    return $?
}
# 恢复站点
function site_restore {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 获取站点虚拟主机名
    site_hostname_get
    # 站点目录根目录
    local site_root_path="$VHOSTS_ROOT/$SITE_HOSTNAME"
    # 定义临时文件夹
    local temp_dir=$BACKUP_STORAGE_DIR/temp
    # 数据库名
    local database_name="sql_$(echo "$SITE_HOSTNAME" | tr '.' '_' | tr '-' '_')"
    # 查看备份
    echoSB "备份文件列表, 总容量: $(du -sh $BACKUP_STORAGE_DIR)"
    # 查看备份 ls -lrthgG
    ls -ghGA $BACKUP_STORAGE_DIR | awk 'BEGIN{OFS="\t"} NR > 1 {print $3, $7}'
    # 接收用户输入
    echo -ne "$BC请输入要还原的文件名: $ED"
    read -a site_backup_file
    # 检查输入是否为空
    if [ -z "$site_backup_file" ]; then
        echoCC "输入不能为空"
        return $?
    fi
    # 检测文件格式
    if [[ ! $site_backup_file =~ .*\.tar\.zst$ ]]; then
        echoCC "[$site_backup_file]非指定的压缩格式."
        return $?
    fi
    # 检查文件是否存在
    local site_backup_file_path=$BACKUP_STORAGE_DIR/$site_backup_file
    if [ ! -f "$site_backup_file_path" ]; then
        echoCC "[$site_backup_file_path] 指定文件不存在."
        return $?
    fi
    # 判断临时文件夹是否存在
    if [ ! -d "$temp_dir" ]; then
        mkdir -p "$temp_dir"
    else
        rm -rf "$temp_dir" && mkdir -p "$temp_dir"
    fi
    # 解压文件
    tar -I zstd -xf "$site_backup_file_path" -C "$temp_dir"
    if [ $? -eq 0 ]; then
        # 恢复数据库
        echo -e "${SB}恢复数据库${ED}"
        local database_backup_file="$temp_dir/db.sql"
        # 删除整个数据库
        docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "DROP DATABASE IF EXISTS \`$database_name\`;"
        # 重新创建空数据库
        docker exec -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -e "CREATE DATABASE \`$database_name\`;"
        # 使用pv显示进度
        pv $database_backup_file | docker exec -i -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot $database_name
        if [ $? -eq 0 ]; then
            # 删除数据库文件
            rm -rf $database_backup_file
            # 删除站点目录
            rm -rf $site_root_path
            # 移动文件
            mv $temp_dir $site_root_path
            # 修改文件权限
            docker exec nginx chown -R www-data:www-data /wwwroot/$SITE_HOSTNAME
            # 输出成功
            echoCC "站点恢复成功"
        else
            echoRC "数据库恢复失败"
        fi
    else
        echoRC "站点恢复失败"
    fi
    # 删除临时文件夹
    rm -rf $temp_dir
}
# 修复站点文件权限
function fix_site_file_permissions {
    # 判断是否存在站点
    if ! site_exists; then
        return 1
    fi
    # 获取站点虚拟主机名
    site_hostname_get
    # 修改文件权限
    docker exec nginx chown -R www-data:www-data /wwwroot/$SITE_HOSTNAME
    if [ $? -eq 0 ]; then
        # 输出成功
        echoCC "站点文件权限修复成功"
    else
        echoRC "站点文件权限修复失败"
    fi
    # 重新加载nginx配置
    docker exec nginx nginx -s reload
}
# 安装phpMyAdmin
function install_phpmyadmin {
    # 判断phpMyAdmin是否已安装
    local phpmyadmin_dir=$VHOSTS_ROOT/phpMyAdmin
    local secret_key=$(head /dev/urandom | tr -dc 'A-Z' | head -c 32)
    if [ -d "$phpmyadmin_dir" ]; then
        echoCC "phpMyAdmin已安装."
        return $?
    fi
    # 安装phpMyAdmin
    wget -O $VHOSTS_ROOT/phpmyadmin.zip https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-english.zip 
    unzip -o $VHOSTS_ROOT/phpmyadmin.zip -d $VHOSTS_ROOT > /dev/null 2>&1
    rm -rf $VHOSTS_ROOT/phpmyadmin.zip
    mv $VHOSTS_ROOT/phpMyAdmin-5.2.1-english $phpmyadmin_dir
    mv $phpmyadmin_dir/config.sample.inc.php $phpmyadmin_dir/config.inc.php
    # 替换localhost为mysql
    sed -i "s/localhost/mysql/g" $phpmyadmin_dir/config.inc.php
    # 替换blowfish_secret
    sed -i "s/\(\$cfg\['blowfish_secret'\] = \)'';/\1'$secret_key';/" "$phpmyadmin_dir/config.inc.php"
    sed -i "s/\(\$cfg\['blowfish_secret'\] = \)'';/\1'$secret_key';/" "$phpmyadmin_dir/libraries/config.default.php"
    # 修改文件权限
    docker exec nginx chown -R www-data:www-data /wwwroot/phpMyAdmin
    # 通过SQL文件创建数据库
    pv $phpmyadmin_dir/sql/create_tables.sql | docker exec -i -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot
    # 输出成功
    echoCC "phpMyAdmin安装成功."
    local local_ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
    # 输出phpMyAdmin链接
    echoGC "phpMyAdmin链接: https://$local_ip:8081"
}
# 站点命令
function site_cmd {
    # 循环
    while true; do
        # 显示菜单
        echo -e "${SB}1${ED}.${LG}创建站点${ED}"
        echo -e "${SB}2${ED}.${LG}追加域名${ED}"
        # echo -e "${SB}3${ED}.${LG}安装SSL证书${ED}"
        echo -e "${SB}4${ED}.${LG}删除站点${ED}"
        echo -e "${SB}5${ED}.${LG}备份站点${ED}"
        echo -e "${SB}6${ED}.${LG}恢复站点${ED}"
        echo -e "${SB}7${ED}.${LG}修复站点文件权限${ED}"
        echo -e "${SB}8${ED}.${LG}安装phpMyAdmin${ED}"
        echo -e "${SB}e${ED}.${LG}退出${ED}"
        echo -ne "${BC}请选择: ${ED}"
        read -a num2
        case $num2 in 
            1) create_site ;;
            2) site_append_domain ;;
            # 3) site_install_ssl ;;
            4) site_delete ;;
            5) site_backup ;;
            6) site_restore ;;
            7) fix_site_file_permissions ;;
            8) install_phpmyadmin ;;
            e) break ;;
            *) echoCC '输入有误.'
        esac
        continue
    done
}
site_cmd