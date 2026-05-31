# Homepage — Bizzon Homelab

Конфигурация [gethomepage/homepage](https://github.com/gethomepage/homepage) для **`https://homepage.bizzon8n.ru`**.

| Параметр | Значение |
|----------|----------|
| Хост | S2, LXC **1013**, IP **192.168.10.22** |
| Traefik | S1 LXC 1012 → `traefik/homepage.yml` |
| Auth | Authentik forward auth |

## Структура

```
config/
  services.yaml   # карточки сервисов и виджеты (ЦБ, крипто)
  settings.yaml   # тема, фон, язык
  widgets.yaml    # шапка: ресурсы, поиск, время, погода
  custom.css      # прозрачность карточек
  docker.yaml     # auto-discovery отключён
  bookmarks.yaml
docker-compose.yml
traefik/homepage.yml   # эталон для S1 (не деплоится скриптом)
scripts/deploy.sh      # выкладка на LXC 1013
```

## Деплой

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Traefik вручную на S1:

```bash
ssh s1
pct exec 1012 -- cp /path/to/homepage.yml /etc/traefik/dynamic/services/homepage.yml
pct exec 1012 -- docker restart traefik
```

## Группы на дашборде

- **Медиа** — Jellyfin, TrueNAS
- **Облако** — Nextcloud, Joplin
- **Финансы** — курсы ЦБ РФ, криптовалюты (CoinGecko, нужен `User-Agent`)
- **Инфраструктура** — Proxmox S1/S2/S3, Traefik, Authentik
- **Проекты** — building-clima, fragrance-pro, stone-sand
- **Управление** — [nic.ru](https://www.nic.ru/), [VK WorkSpace](https://app.workspace.vk.ru/), [HostVDS](https://hostvds.com/)

## Документация homelab

Подробнее: wiki **`homepage.md`** в репозитории SetServer / knowledge-base.
