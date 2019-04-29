# 需要输出的环境变量
```sh
export ACME_DOMAIN=${ACME_DOMAIN}
export NGINX_SSL_KEY="/root/.acme.sh/$ACME_DOMAIN/$ACME_DOMAIN.key"
export NGINX_SSL_CER="/root/.acme.sh/$ACME_DOMAIN/fullchain.cer"
```

nginx.conf没有轻量读取环境变量的功能，执行以下语句进行替换：
```sh
sed -i "s/\${ACME_DOMAIN}/$ACME_DOMAIN/g" /root/viss/aliyun-services/config/nginx.conf/nginx.conf
```