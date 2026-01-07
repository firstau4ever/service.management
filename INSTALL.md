# Инструкция по установке

## Быстрая установка (рекомендуется)

```bash
sudo ./deploy.sh
```

Скрипт выполнит все необходимые шаги автоматически.

## Что делает скрипт установки

1. ✅ Проверяет окружение (Python, systemd)
2. ✅ Устанавливает недостающие пакеты (Python3, pip, venv)
3. ✅ Запрашивает домен для API
4. ✅ Проверяет и выбирает свободный порт
5. ✅ Создает виртуальное окружение Python
6. ✅ Устанавливает зависимости
7. ✅ Генерирует токен безопасности
8. ✅ Настраивает права sudo для www-data
9. ✅ Устанавливает systemd сервис
10. ✅ Показывает список адресов для управления

## Параметры установки

Все параметры можно задать через переменные окружения:

```bash
# Порт (по умолчанию 5000, если занят - автоматически найдет свободный)
export SERVICE_MANAGEMENT_PORT=5001

# Токен (если не задан - будет сгенерирован автоматически)
export SERVICE_MANAGEMENT_TOKEN=your_secret_token

# Запуск установки
sudo ./deploy.sh
```

## После установки

### 1. Настройка веб-сервера

Скрипт покажет инструкции по настройке Nginx или Apache. Добавьте конфигурацию в ваш веб-сервер для проксирования запросов на `/servise/`.

**Пример для Nginx:**
```nginx
location /servise/ {
    proxy_pass http://127.0.0.1:5000;  # Используйте порт, показанный скриптом
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    proxy_buffering off;
}
```

После добавления конфигурации:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 2. Проверка работы

```bash
# Локальная проверка
curl http://127.0.0.1:5000/health

# Через веб-сервер (используйте токен из вывода скрипта)
curl "https://your-domain.com/servise/status/nginx.service?TOKEN=your_token"
```

### 3. Получение конфигурации

Конфигурация сохраняется в `/opt/service-management/.deployment_config`:
```bash
sudo cat /opt/service-management/.deployment_config
```

## Управление сервисом

```bash
# Статус
sudo systemctl status service-management

# Перезапуск
sudo systemctl restart service-management

# Логи
sudo journalctl -u service-management -f

# Остановка
sudo systemctl stop service-management

# Запуск
sudo systemctl start service-management
```

## Удаление проекта

Для полного удаления проекта используйте:

```bash
sudo ./deploy.sh --uninstall
```

Скрипт удалит:
- ✅ Systemd сервис (остановит, отключит автозапуск, удалит файл)
- ✅ Директорию проекта `/opt/service-management`
- ✅ Файл sudoers `/etc/sudoers.d/service-management`
- ✅ Все связанные компоненты

**Примечание:** Конфигурация веб-сервера (Nginx/Apache) не удаляется автоматически. Если нужно, удалите вручную блоки для `/servise/` в конфигурации веб-сервера.

**Альтернативные команды для удаления:**
- `sudo ./deploy.sh --remove`
- `sudo ./deploy.sh -u`
- `sudo ./deploy.sh -r`

## Требования

- Linux с systemd (Ubuntu 18.04+, Debian 10+, CentOS 7+)
- Python 3.7+ (устанавливается автоматически)
- Права root для установки
- Свободный порт (по умолчанию 5000)

Подробные требования: `REQUIREMENTS.md`

