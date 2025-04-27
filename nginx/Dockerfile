# 用户和组
ARG USER=www-data
ARG GROUP=www-data
ARG TZ="Asia/Shanghai"

#################
### 构建NGINX ###
################
FROM alpine:3.20 AS nginx
ARG USER
ARG GROUP
# nginx 源码
ARG NGINX_SOURCE_URL=https://nginx.org/download/nginx-1.26.2.tar.gz
# ngx_cache_purge 模块
ARG NGX_CACHE_PURGE_URL=https://github.com/mina998/ngx_cache_purge.git
# 
RUN cd / && apk update \
    # 清理缓存并重新尝试安装
    && rm -rf /var/cache/apk/*  && apk cache clean \
    # 安装依赖
    && apk add --no-cache --virtual .build-deps build-base pcre-dev zlib-dev openssl-dev perl linux-headers git brotli-dev brotli-static \ 
    # 下载并解压 nginx 源码
    && wget -O nginx-1.26.2.tar.gz ${NGINX_SOURCE_URL} \
    # 下载并解压 Cache Purge 模块
    && git clone --depth 1 ${NGX_CACHE_PURGE_URL} ngx_cache_purge \ 
    # 解压 nginx 源码
    && tar -zxvf nginx-1.26.2.tar.gz && cd nginx-1.26.2 \
    # 配置 nginx
    && ./configure \
    --prefix=/usr/local/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/local/nginx/modules \
    --error-log-path=/usr/local/nginx/logs/nginx.error.log \
    --http-log-path=/usr/local/nginx/logs/nginx.access.log \
    --pid-path=/var/run/nginx.pid \
    --user=${USER} \
    --group=${GROUP} \
    --with-compat \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --add-module=/ngx_cache_purge \ 
    --with-cc-opt='-Os -fstack-clash-protection -Wformat -Werror=format-security -fno-plt -g' \
    --with-ld-opt='-Wl,--as-needed,-O1,--sort-common -Wl,-z,pack-relative-relocs' \
    && make -j$(nproc) \
    && make install \
    # 清理构建文件
    && rm -rf /build/* \
    && apk del .build-deps \
    && rm -rf /nginx-1.26.2 /ngx_cache_purge



################
### 构建PHP ###
################
FROM php:8.3.17-fpm-alpine3.20 AS php83
ARG USER
ARG GROUP
ARG PHP_EXTENSIONS="pdo_mysql mysqli gd curl opcache exif imagick intl zip soap"
ARG ALPINE_MIRROR="dl-cdn.alpinelinux.org"
# 系统配置和扩展安装
RUN set -ex \
    && sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories \
    && apk --no-cache update \
    && apk add --no-cache tzdata curl \
    && curl -sSLf -o /usr/local/bin/install-php-extensions https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions ${PHP_EXTENSIONS} \
    && curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp \
    && apk del tzdata \
    && rm -rf /var/cache/apk/* /tmp/* /usr/share/man


    
################
### 最终镜像 ###
################
FROM alpine:3.20
ARG USER
ARG GROUP
ARG TZ
# 创建必要目录并安装运行时依赖
RUN cd / \ 
    # 设置 SSL 目录
    && SSL=/usr/local/nginx/ssl \
    # 安装运行时依赖
    && apk add --no-cache pcre zlib openssl brotli tzdata sqlite-libs readline gnu-libiconv libxml2 sqlite-libs libcurl oniguruma argon2-libs libsodium icu-libs icu-data-full libintl \
    # 创建用户和组
    && getent group ${GROUP} || addgroup -S ${GROUP} \
    && getent passwd ${USER} || adduser -S -D -H -s /sbin/nologin -G ${GROUP} ${USER} \
    # 创建 SSL 目录
    && mkdir -p ${SSL} \
    # 创建一个自签名证书
    && openssl req -x509 -nodes -days 36500 -newkey rsa:2048 \
        -keyout ${SSL}/nginx.key \ 
        -out ${SSL}/nginx.crt \ 
        -subj "/C=CN/ST=Beijing/L=Beijing/O=Example/OU=IT/CN=example.com" \
    # 创建启动脚本
    && echo '#!/bin/sh' > /docker-entrypoint.sh \
    && echo 'set -e' >> /docker-entrypoint.sh \
    && echo 'php-fpm -D' >> /docker-entrypoint.sh \ 
    && echo 'exec nginx -g "daemon off;"' >> /docker-entrypoint.sh \
    && chmod +x /docker-entrypoint.sh \ 
    # 设置时区
    && cp /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone \
    # 清理
    && rm -rf /var/cache/apk/* /tmp/* /usr/share/man \
    && apk del tzdata

# 从nginx构建阶段复制编译好的文件
COPY --from=nginx /usr/local/nginx /usr/local/nginx
COPY --from=nginx /usr/sbin/nginx /usr/sbin/nginx
# 从php83构建阶段复制编译好的文件
COPY --from=php83 /usr/local /usr/local
# 复制PHP扩展所需的共享库文件
COPY --from=php83 /usr/lib /usr/lib
COPY --from=php83 /lib /lib

WORKDIR /wwwroot
EXPOSE 80 443
STOPSIGNAL SIGQUIT
CMD ["/docker-entrypoint.sh"]
