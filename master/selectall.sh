#!/bin/bash
# 可以使用 ./selectall.sh test 执行测试
echo " -- 本脚本用于docker-compose多配置文件批量选择 -- "
echo " --    可执行 ./selectall.sh help 获取帮助     -- "
if [ $1 != "help" ] && [ $1 != "test" ]; then
    if [ $UID -ne 0 ]; then
        echo "当前用户不包含root权限"
        exit 1
    fi
fi

cmd="docker-compose "
## 这里读取所有yml或yaml结尾且不以WIP开头的文件
for i in `ls |grep "^[^WIP]"| grep "[yml|yaml]$"` 
do
    cmd=$cmd" -f "
    cmd=$cmd$i" "
done


if [ $1 == "test" ];then
    echo -e "将执行：\e[1;41m"$cmd $2"\e[0m "
elif [ $1 == "help" ];then
    echo ""
    echo " ./selectall.sh 可以扫描当前目录下yaml或yml文件 "
    echo " ./selectall.sh test 测试所扫描的结果 "
    echo " ./selectall.sh up -d 相当于'docker-compose -f xxx.yaml up -d' "
else
    for i in "$*"; do
        cmd=$cmd" "$i
    done
    echo -e "将执行：\e[1;41m"$cmd"\e[0m [y/N]"
    read sure
    if [ $sure == "y" ];then
        echo -e "\e[1;31m执行："$cmd"\e[0m"
        $cmd
    fi
fi
