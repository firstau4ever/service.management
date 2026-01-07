# Требования к серверу для работы Service Management API

## Обязательные требования

### 1. Операционная система
- **Linux с systemd** (Ubuntu 18.04+, Debian 10+, CentOS 7+, RHEL 7+)
- Скрипт проверяет наличие `systemctl` и завершится с ошибкой, если система не использует systemd

### 2. Права доступа
- **Root доступ (sudo)** для установки
  - Требуется для:
    - Создания директорий в `/opt/`
    - Установки systemd unit файла
    - Настройки конфигурации веб-сервера
    - Установки Python пакетов системно (если нужно)

### 3. Python
- **Python 3.7 или выше** (проверяется автоматически)
- **python3-pip** - менеджер пакетов Python
- **python3-venv** - для создания виртуального окружения (Ubuntu/Debian)

**✅ Скрипт автоматически устанавливает недостающие пакеты Python!**

Если автоматическая установка не удалась, установите вручную:

#### Установка на Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install python3 python3-pip python3-venv
```

#### Установка на CentOS/RHEL:
```bash
sudo yum install python3 python3-pip
# или для новых версий
sudo dnf install python3 python3-pip
```

### 4. Системные утилиты
- **bash** - оболочка для выполнения скрипта
- **systemctl** - для управления systemd сервисами (обычно входит в systemd)
- **grep, sed, cat, chmod, chown** - стандартные Unix утилиты (обычно присутствуют)

### 5. Утилиты для проверки портов (хотя бы одна)
Скрипт использует их в порядке приоритета:
- **ss** (iproute2) - предпочтительно, современная утилита
- **netstat** (net-tools) - альтернатива
- **lsof** - альтернатива
- **timeout** - fallback метод (обычно входит в coreutils)

#### Установка на Ubuntu/Debian:
```bash
# ss обычно уже установлен
sudo apt-get install iproute2  # для ss
sudo apt-get install net-tools  # для netstat (если нужен)
sudo apt-get install lsof      # для lsof (если нужен)
```

### 6. Пользователь www-data
- Пользователь `www-data` должен существовать в системе
- Обычно создается автоматически при установке веб-сервера
- Если отсутствует, создайте:
  ```bash
  sudo useradd -r -s /bin/false www-data
  ```

### 7. Сетевые требования
- **Свободный порт** в диапазоне 5000-5100 (по умолчанию 5000)
- **Доступ к интернету** для установки Python пакетов через pip (или настроенный локальный репозиторий)
- Если интернет недоступен, можно установить пакеты вручную:
  ```bash
  pip download -r requirements.txt -d ./packages
  pip install --no-index --find-links ./packages -r requirements.txt
  ```

### 8. Права на выполнение systemctl команд
- Приложение запускается от пользователя `www-data`
- По умолчанию `www-data` не имеет прав на выполнение `systemctl`
- **Скрипт развертывания автоматически настраивает sudoers** для выполнения systemctl команд без пароля
- Создается файл `/etc/sudoers.d/service-management` с правилами:
  ```
  www-data ALL=(ALL) NOPASSWD: /bin/systemctl status *, /bin/systemctl start *, /bin/systemctl stop *, /bin/systemctl restart *
  ```
- Приложение использует `sudo -n` для выполнения команд (флаг `-n` предотвращает запрос пароля)
- Если автоматическая настройка не сработала, настройте вручную:
  ```bash
  echo "www-data ALL=(ALL) NOPASSWD: /bin/systemctl status *, /bin/systemctl start *, /bin/systemctl stop *, /bin/systemctl restart *" | sudo tee /etc/sudoers.d/service-management
  sudo chmod 0440 /etc/sudoers.d/service-management
  ```

## Опциональные требования

### Веб-сервер (для работы через домен)
- **Nginx** или **Apache2** для проксирования запросов
- Не обязателен для локальной работы, но необходим для работы через домен

#### Nginx:
```bash
sudo apt-get install nginx  # Ubuntu/Debian
sudo yum install nginx      # CentOS/RHEL
```

#### Apache:
```bash
sudo apt-get install apache2  # Ubuntu/Debian
sudo yum install httpd        # CentOS/RHEL
```

### SSL/TLS сертификат
- Для работы через HTTPS (рекомендуется)
- Можно использовать Let's Encrypt, самоподписанный сертификат или коммерческий

## Проверка требований перед установкой

Выполните следующие команды для проверки:

```bash
# Проверка Python
python3 --version  # Должно быть 3.7+

# Проверка pip
pip3 --version

# Проверка systemd
systemctl --version

# Проверка пользователя www-data
id www-data

# Проверка утилит
which ss netstat lsof timeout

# Проверка прав root
sudo whoami  # Должно вернуть "root"
```

## Минимальные системные требования

- **RAM:** минимум 512 MB (рекомендуется 1 GB+)
- **Диск:** минимум 100 MB свободного места
- **CPU:** любой современный процессор

## Поддерживаемые дистрибутивы

Протестировано и работает на:
- ✅ Ubuntu 18.04, 20.04, 22.04
- ✅ Debian 10, 11, 12
- ✅ CentOS 7, 8
- ✅ RHEL 7, 8, 9
- ✅ Rocky Linux 8, 9
- ✅ AlmaLinux 8, 9

Должно работать на любом Linux дистрибутиве с systemd и Python 3.7+.

## Известные ограничения

1. **Не работает на системах без systemd:**
   - Ubuntu 14.04 и старше (upstart)
   - Debian 7 и старше (sysvinit)
   - CentOS 6 и старше (upstart/sysvinit)

2. **Требуются права на выполнение systemctl:**
   - По умолчанию обычные пользователи не могут выполнять systemctl команды
   - Необходимо настроить права через sudo или polkit

3. **Порт должен быть свободен:**
   - Если порт 5000 занят, скрипт найдет свободный автоматически
   - Можно задать порт вручную через переменную `SERVICE_MANAGEMENT_PORT`

## Рекомендации по безопасности

1. Используйте HTTPS для всех запросов
2. Используйте сильный токен (минимум 32 символа)
3. Ограничьте доступ к порту приложения только с localhost (по умолчанию так и настроено)
4. Регулярно обновляйте зависимости Python
5. Настройте firewall для ограничения доступа к веб-серверу
6. Используйте fail2ban для защиты от брутфорса

