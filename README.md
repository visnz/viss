# 集群服务部署 User Guide
- [ ] LOGO TBD
- [ ] 介绍视频 TBD

## 部署部分
### 0. 架构预览

'|Master|Manager|Worker1|Worker2
-|-|-|-|-
职能|源码/CI/管理所有机器|集群管理/分发任务|接受工作|接受工作
系统管理入口|Docker-machine|<-Master|<-Master|<-Master
集群管理入口||Docker-Swarm|<-Manager|<-Manager
文件系统|独立|NFS<br>(建议使用独立FS)|<-Manager|<-Manager

部署流程预览：
1. 准备相关内容，确定变量
2. 使用Docker-machine部署Master主机，构建gitea+CI+registry+nginx，再使用acme进行SSL认证
3. 部署Manager主机，加入Master管理。
4. 构建文件系统，在Manager上部署NFS文件系统（此一部分可使用其他文件系统），创建集群
5. 部署Worker主机，加入Master管理，加入Manager集群。

### 1. 准备
1. 一个用于构建集群的二级域名（下面用``${ACME_DOAMIN}``替代）
2. 一个云基础设施提供商帐号（AWS、DigitalOcean、Vultr等稳定境外提供商优先）
3. 一个提供域名解析服务帐号（CF、狗爹、Aliyun皆可，需要可提供DNSAPI，参考[这里](https://github.com/Neilpang/acme.sh/wiki/dnsapi)，获取相应token或key）

### 2. 部署Master机器（CI系统）
1. 申请机器
    根据业务需求调整配置，建议在1c2g以上，50G空间及以上。
    系统环境：Ubuntu 18.04（建议）
    装机脚本：（同Manager）
    ```sh
    # Master && Manager script to install
    # Docker-compose and Docker-machine would be installed
    curl -L https://github.com/docker/machine/releases/download/v0.16.1/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine && chmod +x /usr/local/bin/docker-machine
    curl -L https://github.com/docker/compose/releases/download/1.24.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    ```
2. 将``${ACME_DOAMIN}``、``*.${ACME_DOAMIN}``解析到master服务器
3. 初始化环境，需要可ssh登陆（记得改密码）
    ```sh
    # 必填
    export ACME_DOMAIN="${ACME_DOAMIN}" 
    #REQUIRE# # 这里是你自己申请的域名，用于ssl认证与后继访问
    export CONFIG_REPO="https://github.com/visnz/viss.git" 
    #REQUIRE# # 这里指定集群部署的基础配置文件repo，可fork自行修改具体内容
    export DRONE_RPC_SECRET=`openssl rand -hex 16` 
    #REQUIRE# # 这个secret用于drone的server与agent之间的连接，集群部署agent时候需要
    echo "请保存好 DRONE_RPC_SECRET=$DRONE_RPC_SECRET"

    # 选改
    export DOCKER_MACHINE_SSH_KEY=/root/.ssh/master
    # 用于管理所有主机系统的sshkey生成位置

    export DOCKER_MACHINE_SSH_KEY_PUB=$DOCKER_MACHINE_SSH_KEY.pub
    export NGINX_SSL_KEY="/root/.acme.sh/$ACME_DOMAIN/$ACME_DOMAIN.key"
    export NGINX_SSL_CER="/root/.acme.sh/$ACME_DOMAIN/fullchain.cer"
    echo "ACME_DOMAIN=$ACME_DOMAIN" >> ~/.bashrc; 
    echo "CONFIG_REPO=$CONFIG_REPO" >> ~/.bashrc; 
    echo "DRONE_RPC_SECRET=$DRONE_RPC_SECRET" >> ~/.bashrc; 
    echo "DOCKER_MACHINE_SSH_KEY=$DOCKER_MACHINE_SSH_KEY" >> ~/.bashrc; 
    echo "DOCKER_MACHINE_SSH_KEY_PUB=$DOCKER_MACHINE_SSH_KEY_PUB" >> ~/.bashrc; 
    echo "NGINX_SSL_KEY=$NGINX_SSL_KEY" >> ~/.bashrc; 
    echo "NGINX_SSL_CER=$NGINX_SSL_CER" >> ~/.bashrc; 
    ```
4. 使用Docker-machine为自身安装Docker
    当前机器上是没有Docker环境的，不建议直接安装Docker，而应当使用Docker-machine来构建Docker环境。
    一方面是管理统一化，另一方面是使用不同系统的包管理器会有所出入
    ```sh
    # 这部分内容是使用Docker-machine安装Docker环境，并添加自身到Docker-machine的管理之中
    ssh-keygen -f $DOCKER_MACHINE_SSH_KEY # 以后会用这对key管理集群主机，不建议设置passphrase

    cat $DOCKER_MACHINE_SSH_KEY_PUB 
    # [ 重要 ] 将这里生成的/root/.ssh/master.pub 添加到服务商的sshkey管理中-> Master

    ssh-copy-id -i $DOCKER_MACHINE_SSH_KEY_PUB root@127.0.0.1 
    # 添加自身到信任主机列表，不过会提示无效果。
    # 如果是后面新增的机器没有在初始的时候就安装Masterkey，可通过这个命令联机安装
    
    docker-machine create -d generic --generic-ip-address=127.0.0.1 --generic-ssh-user=root --generic-ssh-key $DOCKER_MACHINE_SSH_KEY Master # 创建Master主机，稍等3～5分钟

    # 完成后输入docker可以运行，但不是真实由Docker-machine管理的Docker环境
    eval $(docker-machine env Master) # 运行该行进入自身docker环境
    ```
5. 获取配置文件组
    ```sh
    apt install -y git && git clone $CONFIG_REPO 
    # 进入master主机配置文件夹：
    #  ├─ CI.yaml             # CI系统，包含 nginx gitea drone-server drone-agent registry五部分
    #  ├─ config
    #  │   └─ nginx.conf
    #  │       ├─ mime.types # nginx运行需要
    #  │       └─ nginx.conf # nginx配置，ssl配置了对几个服务端口访问安全
    #  ├─ README.md           
    #  └─ selectall.sh        # 用于选取该目录下所有.yaml文件并执行统一动作，如启动、关停
    ```
    nginx.conf没有轻量读取环境变量的功能，执行以下语句，将``nginx.conf``中的配置替换：
    ```sh
    sed -i "s/\${ACME_DOMAIN}/$ACME_DOMAIN/g" viss/master/config/nginx.conf/nginx.conf
    ```
6. 配置SSL
    ```sh
    # 获取acme脚本
    apt update; apt -y upgrade; apt install -y socat; curl https://get.acme.sh | sh
    
    # 启动验证
    export CF_Key="1234567890123456789012345678901234567" && export CF_Email="123456@gmail.com"
    # 这里是1. 准备中3所申请获得的token，每个服务商会有不同，按需要改变变量名
    ~/.acme.sh/acme.sh --issue --dns dns_cf -d $ACME_DOMAIN  -d *.$ACME_DOMAIN
    # 由于这几个token是敏感变量，在使用完后记得运行清除
    export CF_Key="" && export CF_Email=""
    ```
7. 启动ci
    ```sh
    # master目录
    ./selectall.sh up -d
    # 相当于执行 docker-compose -f CI.yaml up -d
    # 
    # 如果出现WARNING警告，可能需要依照~/.bashrc将警告的环境变量重新export一遍
    ```
8. 可以访问：

    网址|效果
    -|-
    http://${ACME_DOMAIN}|跳转 https://${ACME_DOMAIN}
    https://hub.${ACME_DOMAIN}|gitea
    https://drone.${ACME_DOMAIN}|droneCI
    https://registry.${ACME_DOMAIN}|registry（空白页面）

    关于上面三级域名的修改，需要同时修改``CI.yaml``、``nginx.conf``中的相关三级域名，以及在后面所操作的网址域名都要跟着修改。由于Cluster默认配置中``droneagent.yml``也有默认链接到``https://drone.${ACME_DOMAIN}``，对应的变量也需要修改。

### 3. 部署Manager主机
> 此机器将作为集群的管理节点
1. 申请主机
    根据业务需求调整配置，建议在2c4g以上，30G空间及以上。（如果作为文件系统的服务节点，建议50G以上）
    系统环境：Ubuntu 18.04（建议）
    添加公钥：2.4部分生成的Master公钥
    装机脚本：（同Master）
    ```sh
    # Master && Manager script to install
    # Docker-compose and Docker-machine would be installed
    curl -L https://github.com/docker/machine/releases/download/v0.16.1/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine && chmod +x /usr/local/bin/docker-machine
    curl -L https://github.com/docker/compose/releases/download/1.24.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
    ```
2. 在创建主机、等待的同时，完成以下工作：
    - 添加域名解析``manager.${ACME_DOMAIN}``到Manager主机（使用域名寻址避免docker-machine一些验证机制所产生的问题）
3. 将Manager机器添加到Master管理
    在Master主机上，运行：
    ```sh
    # 如果服务商忘记添加ssh钥匙，可用下列命令将master推送到Manager上：
    #     ssh-copy-id -i $DOCKER_MACHINE_SSH_KEY_PUB root@manager.${ACME_DOMAIN} 

    docker-machine create -d generic --generic-ip-address=manager.$ACME_DOMAIN --generic-ssh-user=root --generic-ssh-key $DOCKER_MACHINE_SSH_KEY Manager
    # 这里将在Manager上安装Docker，并通过指定的密钥验证，将接下来将Manager机器添加到Master管理，以后也将一直在Master管理、部署Manager
    docker-machine ssh Manager 
    # 登陆Manager
    ```
4. 创建集群：
    ```sh
    docker swarm init --advertise-addr $Manager_IP$ 
    # 将得到worker用于加入集群的命令，如：
    # docker swarm join --token ABCDEF-3-1k1123456789asdfghjkl-987654321zxcvbnmqwertyuiop 198.256.256.1:2377
    # 妥善保存
    ```

### 4. 文件系统
> 默认方案选择了在Manager主机上开辟``/nfs/``目录作为共享（只读），供Worker读取配置，仅有Manager具有读取权限以确保访问安全。
> 
> 集群用的文件系统众多，可根据需要进行调整
1. 安装nfs系统：
    ```sh
    modprobe nfs && modprobe nfsd   # 加载内核模块 nfs
    apt install -y nfs-common       # 安装默认驱动

    # 生成配置文件：
    echo "/nfs        *(rw,fsid=0,sync,no_root_squash)">exports.conf
    # 生成docker-compose
    cat << EOF > ./nfsd.yml
    version: '3'
    services:
        nfsd:
            image: erichough/nfs-server
            container_name: nfsserver
            volumes:
                - ./exports.conf:/etc/exports:ro
                - /nfs:/nfs
            ports:
                - "2049:2049"
            privileged: true
            restart: always
    EOF
    ```
2. 创建目录并启动
    ```sh
    mkdir /nfs ; docker-compose -f nfsd.yml up -d
    # 可以通过 docker logs nfsserver 查看状态
    ```
    此时nfsd被使用docker单独执行，与集群执行的服务无关。

### 5. 添加Worker主机
1. 申请主机
    根据业务需求调整配置，建议在2c4g以上，20G空间及以上。
    系统环境：Ubuntu 18.04（建议）
    添加公钥：2.4部分生成的Master公钥
    装机脚本：（Worker专属）
    ```sh
    # install docker-machine, and no needed docker-compose anymore
    curl -L https://github.com/docker/machine/releases/download/v0.16.1/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine && chmod +x /usr/local/bin/docker-machine
    # install driver and mount the public nfs to itself
    apt install -y nfs-common; mkdir /nfs; mount -o nfsvers=4 198.256.256.1:/  /nfs
    # 根据文件系统做具体调整，这里是将Worker节点连接到文件系统之中
    ```
2. 在创建主机、等待的同时，完成以下工作：
    - 添加域名解析``worker1.${ACME_DOMAIN}``到Worker1主机
3. 将Manager机器添加到Master管理
    在Master主机上，运行：
    ```sh
    docker-machine create -d generic --generic-ip-address=worker1.$ACME_DOMAIN --generic-ssh-user=root --generic-ssh-key $DOCKER_MACHINE_SSH_KEY worker1
    # 2. 3. 两部分与Manager操作接近，用于纳入Master管理
    ```
4. 将Worker主机纳入集群：
    ```sh
    # 登陆Worker主机
    docker-machine ssh worker1
    # 3.4中生成的用于加入集群的命令
    docker swarm join --token ABCDEF-3-1k1123456789asdfghjkl-987654321zxcvbnmqwertyuiop 198.256.256.1:2377 
    ```
## 测试部分
### CI部分（Master主机）
1. 初始化
    [ 重要 ] 在gitea页面注册，修改``Gitea 基本 URL： https://hub.${ACME_DOMAIN}``。
    自此之后，drone、registry共用gitea的帐号
2. 测试CI
    提供一个基于hexo的[测试repo](https://github.com/visnz/viss-test.git)：
    ```sh
    # repo结构图
    ├─ Dockerfile           # [ 看这里 ] 描述了从repo生成博客后台文件，并打包的nginx的过程
    ├─ .drone.yml           # [ 看这里 ] 拉去本项目，并执行Dockerfile的程序，推送到registry
    ├─ docker-compose.yml   # [ 看这里 ] 描述了从registry拉取镜像到部署的配置
    ├─ _config.yml          # hexo的配置文件
    ├─ package.json         # hexo需要
    ├─ package-lock.json    # hexo需要
    ├─ source/posts         # 文章文件
    │  └─ about.md
    └─ themes               # 主题包
        └─ landscape-plus
    ```
    1. 在gitea中新建仓库，选择``迁移外部仓库``：``https://github.com/visnz/viss-test.git``
    修改以下文件：
        ```sh
        # Dockerfile
        2 ENV BLOG_NAME=${BLOG_NAME}   # 迁移的repo刚刚自己起的名字
        3 RUN git clone ${REPO}        # repo的用于clone的地址
        10 ENV BLOG_NAME=${BLOG_NAME}

        # docker-compose.yml
        6     image: ${registryAddress}/${registryUsername}/${imageName}
        # registryAddress  是上面提供registry服务的地址，不需要带协议，如registry.${ACME_DOMAIN}
        # registryUsername 用你刚刚注册的gitea的用户名（建议）
        # imageName        这个是推送到registry时候的镜像名，建议与repo同名
        # 如 registry.xx.com/visnz/viss-test
        ```
    2. 修改完可直接push到master。
    3. 在drone服务页面中登陆，激活刚刚迁移过来的项目，在setting中设置变量（secret）：
        ```sh
        # 这里的变量对应 .drone.yml文件
        username = 刚刚注册的gitea的用户名
        password = 刚刚注册的gitea的密码
        repo     = 同上 ${registryAddress}/${registryUsername}/${imageName}
        registry = 同上 ${registryAddress}
        ```
    4. 设置完成后，返回gitea的repo，打开``仓库设置（setting）``中，``管理webhook``中，可以看到drone以及帮我们添加好了webhook，点开该webhook，在下方点击``测试推送``，gitea将会推送最新的一次master的webhook到drone去。
    5. 回切到drone，已经开始运行，并按照Dockerfile打包成docker，推送到指定registry
    6. 在一台具有docker环境的主机上该repo下刚刚修改的docker-compose进行部署：``docker-compose up -d``，访问``16123``端口便可看到使用docker打包的博客
    或者直接在Master上：
    ```sh
    cat << EOF > /tmp/tmpcompose.yml
    version: '3'
    services:
        viss-test:
            container_name: viss-test
            restart: always
            image: registry.${ACME_DOMAIN}/visnz/visn-test
            ports:
                - "16123:80"
    EOF
    docker-compose -f /tmp/tmpcompose.yml up -d
    ```
### 集群部分测试
1. 获取您自己的配置文件repo
    ```sh
    # Manager 主机上：

    git clone https://github.com/visnz/viss.git /nfs
    # ├─ cluster
    # │  ├─ droneagent.yml          # Master上CI的集群节点程序，默认在每节点部署一个
    # │  └─ selectall.sh
    # ├─ master
    # │  ├─ CI.yaml                 # 描述了CI的组件，用于docker-compose
    # │  ├─ config              
    # │  │   └─ nginx.conf
    # │  │       ├─ mime.types
    # │  │       └─ nginx.conf     # 对外接管CI的访问
    # │  ├─ README.md
    # │  └─ selectall.sh            # 选择目录下所有yaml的脚本，用于docker-compose唤醒
    # ├─ nfs
    # │  ├─ nfs-manager-setup.sh    # 用于nfs manager上的安装
    # │  └─ nfs-worker-setup.sh     # 用于nfs worker的挂载
    # └─ README.md
    ```
2. 在Manager上部署无状态服务
    无状态服务将全部配置打包进Docker，没有读写操作，不访问文件系统
    ```sh
    # 1. 无状态服务（global）
    # agent 需要Master上的两个变量：
    #   export ACME_DOMAIN=
    #   export DRONE_RPC_SECRET=
    docker stack deploy -c  cluster/droneagent.yml d
    docker service ps d_drone-agent
    # 测试：drone同时执行的最多操作个数=至今创建所有主机×2,最少为2（Master）

    # 2. 无状态服务（replicas）
    docker stack deploy -c viss-test/docker-compose.yml b
    # 这里docker-compose来自上一个测试阶段的viss-test文件，可从master主机clone下来
    docker service ps b_viss-test
    docker service scale b_viss-test=3
    docker service ps b_viss-test
    # 访问：http://worker.${ACME_DOMAIN}:16123
    ```
4. 在Manager上部署只读状态服务
    只读状态服务需要读取共享的文件系统中的文件
    ```sh
    # 保存一个简单的nginx代理配置
    touch /nfs/tmp.config
    cat "user root;events{}http{include /etc/nginx/mime.types; server {listen 13334;location / {proxy_pass https://google.com/;}}}" > /nfs/tmp.config
    # 保存一个简单的docker-compose代理配置
    cat << EOF > ./tmpproxy.yml
    version: '3'
    services:
      tmpproxy:
        image: nginx
        volumes:
          - /nfs/tmp.config:/etc/nginx/nginx.conf 
        ports:
          - "13334:13334"
    EOF

    docker stack deploy -c tmpproxy.yml p
    docker service ps p_tmpproxy
    docker service scale p_tmpproxy=3 # 滚动到三个副本
    docker service ps p_tmpproxy
    # 可以看到部署在Worker主机上的 p_tmpproxy 也可以读取到创建在本地的 /nfs/tmp.config
    ```
