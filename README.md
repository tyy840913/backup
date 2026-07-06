<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=200&section=header&text=🚀%20Backup%20Scripts&fontSize=60&fontAlignY=35&animation=twinkling&fontColor=ffffff" />
</p>

<p align="center">
  <b>⚡ 一键脚本合集 · 开箱即用 · 持续更新</b><br>
  <sub>服务管理 · 系统初始化 · 代理网络 · 证书安全 · PVE · 备份监控</sub>
</p>

<p align="center">
  <a href="#-服务管理"><kbd>🖥️ 服务管理</kbd></a> •
  <a href="#-系统初始化"><kbd>📦 系统初始化</kbd></a> •
  <a href="#-代理与网络"><kbd>🌐 代理与网络</kbd></a> •
  <a href="#-证书与安全"><kbd>🔐 证书与安全</kbd></a> •
  <a href="#-备份存储"><kbd>💾 备份存储</kbd></a> •
  <a href="#-pve-专用"><kbd>🛠️ PVE</kbd></a>
</p>

---

## 🖥️ 服务管理

- **main.sh** — 🎯 主菜单（整合全部脚本）
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/main.sh)"
  ```
- **webconf.sh** — 📄 Nginx & Caddy 配置快速生成
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webconf.sh)
  ```
- **LXC一键脚本.sh** — 📦 LXC 容器创建
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/LXC一键脚本.sh)"
  ```
- **vps-node-deploy.sh** — 🚀 VPS 代理节点部署
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/vps-node-deploy.sh)
  ```

## 📦 系统初始化

- **init.sh** — 🕐 时区·中文·换源·SSH·清理
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/init.sh)"
  ```
- **Docker.sh** — 🐳 Docker + Compose v2 安装
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/Docker.sh)"
  ```
- **docker-compose.sh** — 🚀 一键启动容器（远程/本地 YAML）
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.sh)"
  ```
- **mirror.sh** — 📡 更换 Linux 镜像源
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mirror.sh)"
  ```
- **system_cleaner.sh** — 🧹 日志·缓存·旧内核清理
  ```bash
  curl -o /root/system_cleaner.sh -sL https://cdn.wosken.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/system_cleaner.sh && chmod +x /root/system_cleaner.sh && /root/system_cleaner.sh --cron
  ```

## 🌐 代理与网络

- **mihomo_install.sh** — 🏗️ mihomo Docker 代理部署
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mihomo_install.sh)"
  ```
- **mihomo.sh** — ⚙️ mihomo 裸核代理
  ```bash
  bash -c "$(curl -fsSL https://cdn.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh)"
  ```
- **network.sh** — 🔄 路由器网络联通检查恢复
  ```bash
  curl -LsO https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/network.sh && chmod +x network.sh
  ```
- **ping_ip.sh** — 📡 扫描局域网设备 IP / MAC
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/ping_ip.sh)"
  ```

## 🔐 证书与安全

- **acme-ssl.sh** — 🛡️ ACME SSL 证书申请
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/acme-ssl.sh)
  ```
- **webroot.sh** — 🌿 Webroot 方式证书申请
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webroot.sh)
  ```
- **port.sh** — 🧱 系统防火墙（iptables）管理（集成于主菜单）

## 💾 备份存储

- **auto_backup.sh** — 📀 Docker 容器数据自动备份
  ```bash
  bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/auto_backup.sh)"
  ```

## 🛠️ PVE 专用

- **qm.sh** — 💿 虚拟磁盘转换（IMG / ISO）
  ```bash
  curl -LsO https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/qm.sh && chmod +x qm.sh && ./qm.sh
  ```

---

## 📖 其他资源

| 资源 | 说明 | 链接 |
|------|------|------|
| 🧩 **ACL4SSR** | Clash 规则集 | `https://github.com/ACL4SSR/ACL4SSR/tree/master` |

<br>

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=120&section=footer&text=🔧%20Made%20with%20%E2%9D%A4%EF%B8%8F&fontSize=30&fontAlignY=55&fontColor=ffffff" />
</p>

<p align="center">
  <sub>点击代码块右上角 <kbd>📋</kbd> 一键复制命令 · 建议 root 权限运行</sub>
</p>