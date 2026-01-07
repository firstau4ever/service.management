# Инструкция по установке и настройке

## Быстрая установка

```bash
sudo ./deploy.sh
```

Скрипт автоматически:
1. Проверит окружение (Python, веб-сервер)
2. Установит зависимости
3. Настроит systemd сервис
4. Предоставит инструкции по настройке веб-сервера

## Ручная установка

### 1. Установка зависимостей

```bash
sudo apt-get update
sudo apt-get install python3 python3-pip python3-venv
```

### 2. Копирование проекта

```bash
sudo mkdir -p /opt/service-management
sudo cp -r . /opt/service-management/
sudo chown -R www-data:www-data /opt/service-management
```

### 3. Создание виртуального окружения

```bash
cd /opt/service-management
sudo -u www-data python3 -m venv venv
sudo -u www-data venv/bin/pip install -r requirements.txt
```

### 4. Настройка домена

Скрипт `deploy.sh` запросит домен интерактивно при установке. Вы также можете задать его через переменную окружения:
```bash
export SERVICE_MANAGEMENT_DOMAIN=your-domain.com
```

### 5. Настройка порта (опционально)

По умолчанию используется порт 5000. Скрипт автоматически проверит занятость порта и найдет свободный, если нужно.

Вы можете задать порт вручную:
```bash
export SERVICE_MANAGEMENT_PORT=5001
```

### 6. Настройка токена

Сгенерируйте безопасный токен:
```bash
openssl rand -hex 32
```

Или используйте Python:
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 7. Настройка systemd сервиса

Отредактируйте `/opt/service-management/service-management.service` и замените:
- `CHANGE_THIS_TOKEN` на ваш токен
- `127.0.0.1:5000` на нужный порт (если используете нестандартный порт)

Затем:
```bash
sudo cp service-management.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable service-management
sudo systemctl start service-management
```

### 8. Настройка Nginx

Добавьте в конфигурацию вашего сайта (обычно `/etc/nginx/sites-available/default` или файл для вашего домена):

```nginx
location /servise/ {
    proxy_pass http://127.0.0.1:5000;
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

Проверьте конфигурацию и перезагрузите:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 9. Настройка Apache

Включите необходимые модули:
```bash
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
```

Добавьте в конфигурацию вашего VirtualHost:

```apache
<Location /servise/>
    ProxyPass http://127.0.0.1:5000/servise/
    ProxyPassReverse http://127.0.0.1:5000/servise/
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyTimeout 60
</Location>
```

Проверьте и перезагрузите:
```bash
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## Проверка работы

После установки скрипт покажет полный список адресов для управления с установленными параметрами.

### Локальная проверка
```bash
curl http://127.0.0.1:5000/health
```
(Замените 5000 на фактический порт, если он отличается)

### Проверка через веб-сервер
```bash
curl "https://your-domain.com/servise/status/nginx.service?TOKEN=your_token"
```

### Получение конфигурации
Конфигурация сохраняется в файл `/opt/service-management/.deployment_config`:
```bash
cat /opt/service-management/.deployment_config
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

## Безопасность

1. **Используйте сильный токен** - минимум 32 символа
2. **Ограничьте доступ** - используйте firewall для ограничения доступа к порту 5000 только с localhost
3. **HTTPS обязателен** - убедитесь что используется HTTPS для всех запросов
4. **Регулярно обновляйте зависимости** - `pip install --upgrade -r requirements.txt`

## Устранение проблем

### Сервис не запускается
```bash
sudo journalctl -u service-management -n 50
```

### Ошибки проксирования
- Проверьте что сервис слушает на `127.0.0.1:5000`: `sudo netstat -tlnp | grep 5000`
- Проверьте логи веб-сервера: `sudo tail -f /var/log/nginx/error.log` или `/var/log/apache2/error.log`

### Ошибки авторизации
- Убедитесь что токен правильно установлен в systemd service файле
- Проверьте переменную окружения: `sudo systemctl show service-management | grep TOKEN`

