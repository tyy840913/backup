<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=200&section=header&text=🚀%20Backup%20Scripts&fontSize=60&fontAlignY=35&animation=twinkling&fontColor=ffffff" />
</p>

<p align="center">
  <b>⚡ 一键脚本合集 · 开箱即用 · 持续更新</b><br>
  <sub>系统初始化 · 代理网络 · 证书安全 · PVE · 备份监控</sub>
</p>

<p align="center">
  <a href="#-系统初始化"><kbd>📦 系统初始化</kbd></a> •
  <a href="#-代理与网络"><kbd>🌐 代理与网络</kbd></a> •
  <a href="#-证书与安全"><kbd>🔐 证书与安全</kbd></a> •
  <a href="#-服务管理"><kbd>🖥️ 服务管理</kbd></a> •
  <a href="#-备份存储"><kbd>💾 备份存储</kbd></a> •
  <a href="#-pve-专用"><kbd>🛠️ PVE</kbd></a>
</p>

---

<details open>
<summary><b>📦 系统初始化与工具</b> <code>init / mirror / docker / cleanup</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **init.sh** | 🕐 时区·中文·换源·SSH·清理 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/init.sh)"` |
| 2 | **Docker.sh** | 🐳 Docker + Compose v2 安装 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/Docker.sh)"` |
| 3 | **docker-compose.sh** | 🚀 一键启动容器（远程/本地 YAML） | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.sh)"` |
| 4 | **mirror.sh** | 📡 更换 Linux 镜像源 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mirror.sh)"` |
| 5 | **system_cleaner.sh** | 🧹 日志·缓存·旧内核清理 | `curl -o /root/system_cleaner.sh -sL https://cdn.wosken.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/system_cleaner.sh && chmod +x /root/system_cleaner.sh && /root/system_cleaner.sh --cron` |

</details>

<details open>
<summary><b>🌐 代理与网络</b> <code>mihomo / network / scanner</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **mihomo_install.sh** | 🏗️ mihomo Docker 代理部署 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/mihomo_install.sh)"` |
| 2 | **mihomo.sh** | ⚙️ mihomo 裸核代理 | `bash -c "$(curl -fsSL https://cdn.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo/mihomo.sh)"` |
| 3 | **network.sh** | 🔄 路由器网络联通检查恢复 | `curl -LsO https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/network.sh && chmod +x network.sh` |
| 4 | **ping_ip.sh** | 📡 扫描局域网设备 IP / MAC | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/ping_ip.sh)"` |

</details>

<details open>
<summary><b>🔐 证书与安全</b> <code>SSL / firewall</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **acme-ssl.sh** | 🛡️ ACME SSL 证书申请 | `bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/acme-ssl.sh)` |
| 2 | **webroot.sh** | 🌿 Webroot 方式证书申请 | `bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webroot.sh)` |
| 3 | **port.sh** | 🧱 系统防火墙（iptables）管理 | 集成于主菜单 |

</details>

<details open>
<summary><b>🖥️ 服务管理</b> <code>menu / nginx / lxc / vps</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **main.sh** | 🎯 主菜单（整合全部脚本） | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/main.sh)"` |
| 2 | **webconf.sh** | 📄 Nginx & Caddy 配置快速生成 | `bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webconf.sh)` |
| 3 | **LXC一键脚本.sh** | 📦 LXC 容器创建 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/LXC一键脚本.sh)"` |
| 4 | **vps-node-deploy.sh** | 🚀 VPS 代理节点部署 | `bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/vps-node-deploy.sh)` |

</details>

<details open>
<summary><b>💾 备份存储</b> <code>backup / git-cf</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **auto_backup.sh** | 📀 Docker 容器数据自动备份 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/auto_backup.sh)"` |
| 2 | **Git-CF.sh** | 🌍 Git & Cloudflare 工具安装 | `curl -o /root/Git-CF.sh -sL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/Git-CF.sh && chmod +x /root/Git-CF.sh && bash /root/Git-CF.sh` |

</details>

<details open>
<summary><b>🛠️ PVE 专用</b> <code>disk / mirror</code></summary>
<br>

| # | 脚本 | 说明 | 一键运行 |
|---|------|------|----------|
| 1 | **qm.sh** | 💿 虚拟磁盘转换（IMG / ISO） | `curl -LsO https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/qm.sh && chmod +x qm.sh && ./qm.sh` |
| 2 | **pve-init.sh** | 🔄 PVE 镜像源更换 | `bash -c "$(curl -fsSL https://cdn.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/pve-init.sh)"` |

</details>

<br>

<details>
<summary><b>📖 其他资源</b></summary>
<br>

| 资源 | 说明 | 链接 |
|------|------|------|
| 🧩 **ACL4SSR** | Clash 规则集 | `https://github.com/ACL4SSR/ACL4SSR/tree/master` |
| ⚡ **Git-CF 快捷命令** | 安装后直接执行 `Git-CF` | 见上方安装脚本 |

</details>

<br>

---

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&height=120&section=footer&text=🔧%20Made%20with%20%E2%9D%A4%EF%B8%8F&fontSize=30&fontAlignY=55&fontColor=ffffff" />
</p>

<p align="center">
  <sub>📌 点击代码块右上角 <kbd>📋</kbd> 复制命令 · 建议 root 权限运行</sub>
</p>
