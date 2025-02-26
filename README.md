# 项目名称

## 简介

本项目提供了一个简单的 Bash 脚本，用于执行更新国内软件源。通过以下命令，您可以轻松地下载并执行更新脚本。

## 使用方法

新安装alpine系统优先使用这条命令安装基础工具

```bash
sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && apk add curl bash
```

要执行主脚本，请在终端中运行以下命令：

```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/main.sh)"
```

要执行软件源更新脚本，请在终端中运行以下命令：

```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/update.sh)"
```

要执行卸载工具脚本，请在终端中运行以下命令：

```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/uninstall.sh)"
```

要执行时区修改及SSH安装，请在终端中运行以下命令：

```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/time.sh)"
```

要执行docker安装脚本，请在终端中运行以下命令：

```bash
bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.sh)"
```

