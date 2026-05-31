# background.jpg

Фон Homepage: **`/opt/homepage/images/background.jpg`** на LXC 1013 (2048×1023).

В git не включён (см. `.gitignore`). При первой установке скопируйте файл на сервер:

```bash
scp -P 42222 background.jpg root@77.51.218.207:/tmp/
ssh -p 42222 root@77.51.218.207 'pct push 1013 /tmp/background.jpg /opt/homepage/images/background.jpg'
```
