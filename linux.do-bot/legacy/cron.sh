#!/bin/bash
#设置为中文
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
# 获取当前工作目录
WORKDIR=$(dirname $(readlink -f $0))

# 进入工作目录
cd $WORKDIR

# 停止 Docker Compose
docker-compose down --remove-orphans --volumes

# 重新启动 Docker Compose
docker-compose up -d >> ./cron.log 2>&1

# 等待60分钟
sleep 20m
docker-compose logs >> ./cron.log 2>&1

# 停止 Docker Compose
docker-compose down --remove-orphans --volumes >> ./cron.log 2>&1