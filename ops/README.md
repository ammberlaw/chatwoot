# ops —— 生产机上那些不在镜像里的配置

`app/`、`config/` 里的东西跟着镜像走，部署一遍就上去了。这个目录放的是**另一类**：
跑在容器外面、靠手工 `vi` 改的那几个文件。它们决定站点能不能访问、CDN 能不能回源、
Meta 审核页在不在，但一直只存在于服务器的 `/etc` 和 `/var/www` 里——谁也不知道上次
改了什么、为什么改，重装机器就得凭记忆重敲。

这里的副本是 2026-10-04 从生产机按字节拉下来的快照，`md5` 与生产逐一核对一致。

| 仓库里 | 生产机上 |
|---|---|
| `nginx/sites-available/wintouch-crm` | `/etc/nginx/sites-available/wintouch-crm` |
| `nginx/snippets/wintouch-proxy.conf` | `/etc/nginx/snippets/wintouch-proxy.conf` |
| `nginx/snippets/wintouch-static-cache.conf` | `/etc/nginx/snippets/wintouch-static-cache.conf` |
| `nginx/conf.d/wintouch-cache.conf` | `/etc/nginx/conf.d/wintouch-cache.conf` |
| `legal/privacy.html` | `/var/www/wintouch-legal/privacy.html` |

## 怎么用

```sh
./ops/sync-nginx.sh           # 对账：逐个文件比对本地与生产，只读，不改任何东西
./ops/sync-nginx.sh --push    # 推上去：先备份 → 覆盖 → nginx -t → reload（任一步失败即回滚）
```

对账是日常动作：先 `--push` 之前跑一次，确认差异只有你这次要改的那几行。
`--push` 会在服务器上留一份带时间戳的备份（`/etc/nginx/.wintouch-bak-<时间>`），
`nginx -t` 不过就原地回滚，不会把站点改挂。

## 注意

- **证书那几行由 certbot 维护**，`wintouch-crm` 里带 `# managed by Certbot` 注释的
  `listen 443` / `ssl_certificate` 都是它自己写进去的。续证书后生产这个文件会变，
  对账会报差异——那种差异要把生产的拉回仓库，不是把仓库的推上去。
- **`cdn.wintouchspace.com` 的证书不在这里**，它在腾讯云 CDN 控制台上，单独一张
  TrustAsia DV（2026-10-28 到期），得手动续签换绑，nginx 这边动不着。
- `.env` 不收进仓库（里面有 token）。
