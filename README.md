# alpine系统更换源命令 "清华源" ，安装 bash curl 工具
```bash
sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && apk update && apk add bash curl
```

# PVE虚拟磁盘转换，可以转换IMG ISO文件
```bash
curl -LsO https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/qm.sh && chmod +x qm.sh && ./qm.sh
```

# 一键运行docker-compose
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.sh)"
```

# ping获取本地局域网设备ip及MAC信息
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/ping_ip.sh)"
```

## 快速启动

# 📋 点击右侧复制按钮直接复制

# 主脚本
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/main.sh)"
```

# 系统SSH及时区设置
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/init.sh)"
```

# 系统配置
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/init.sh)"
```

# 自动备份
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/auto_backup.sh)"
```

# Docker安装
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/Docker.sh)"
```

# 更换linux系统镜像源
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mirror.sh)"
```

# 更换PVE系统镜像源 （未测试）
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/pve-init.sh)"
```
