# alpine系统更换源命令 "清华源" ，安装 bash curl 工具
```bash
sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && apk update && apk add bash curl
```

## 快速启动

# 📋 点击右侧复制按钮直接复制

# 主脚本
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/main.sh)"
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

# 更换系统镜像源
```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mirror.sh)"
```
