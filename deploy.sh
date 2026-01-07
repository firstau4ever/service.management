#!/bin/bash

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Конфигурация
PROJECT_DIR="/opt/service-management"
SERVICE_NAME="service-management"
WEB_SERVER=""  # Будет определен автоматически
DEFAULT_PORT=5000
APP_PORT=""
# Домен не запрашивается - пользователь сам настраивает веб-сервер

# Функция удаления проекта
uninstall_project() {
    # Временно отключаем set -e для функции удаления
    set +e
    
    echo -e "${YELLOW}=== Удаление Service Management API ===${NC}\n"
    
    # Проверка что скрипт запущен от root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Ошибка: Скрипт должен быть запущен от root (используйте sudo)${NC}"
        exit 1
    fi
    
    REMOVED_ITEMS=0
    
    # Остановка и удаление systemd сервиса
    if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
        echo -e "${YELLOW}[1/5] Остановка systemd сервиса...${NC}"
        systemctl stop $SERVICE_NAME 2>/dev/null
        echo -e "${GREEN}Сервис остановлен${NC}"
        REMOVED_ITEMS=$((REMOVED_ITEMS + 1))
    else
        echo -e "${YELLOW}[1/5] Сервис не запущен${NC}"
    fi
    
    if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
        echo -e "${YELLOW}[2/5] Отключение автозапуска сервиса...${NC}"
        systemctl disable $SERVICE_NAME 2>/dev/null
        echo -e "${GREEN}Автозапуск отключен${NC}"
        REMOVED_ITEMS=$((REMOVED_ITEMS + 1))
    else
        echo -e "${YELLOW}[2/5] Сервис не был включен${NC}"
    fi
    
    if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo -e "${YELLOW}[3/5] Удаление systemd unit файла...${NC}"
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        systemctl daemon-reload 2>/dev/null
        echo -e "${GREEN}Systemd unit файл удален${NC}"
        REMOVED_ITEMS=$((REMOVED_ITEMS + 1))
    else
        echo -e "${YELLOW}[3/5] Systemd unit файл не найден${NC}"
    fi
    
    # Удаление файла sudoers
    if [ -f "/etc/sudoers.d/$SERVICE_NAME" ]; then
        echo -e "${YELLOW}[4/5] Удаление файла sudoers...${NC}"
        rm -f /etc/sudoers.d/$SERVICE_NAME
        echo -e "${GREEN}Файл sudoers удален${NC}"
        REMOVED_ITEMS=$((REMOVED_ITEMS + 1))
    else
        echo -e "${YELLOW}[4/5] Файл sudoers не найден${NC}"
    fi
    
    # Удаление директории проекта
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${YELLOW}[5/5] Удаление директории проекта...${NC}"
        rm -rf "$PROJECT_DIR"
        echo -e "${GREEN}Директория проекта удалена${NC}"
        REMOVED_ITEMS=$((REMOVED_ITEMS + 1))
    else
        echo -e "${YELLOW}[5/5] Директория проекта не найдена${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    if [ $REMOVED_ITEMS -gt 0 ]; then
        echo -e "${GREEN}  Удаление завершено! Удалено компонентов: $REMOVED_ITEMS${NC}"
    else
        echo -e "${YELLOW}  Проект не был установлен или уже удален${NC}"
    fi
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Примечание:${NC} Конфигурация веб-сервера (Nginx/Apache) не была удалена."
    echo -e "Если нужно, удалите вручную блоки для /servise/ в конфигурации веб-сервера."
    echo ""
    
    # Включаем обратно set -e
    set -e
    exit 0
}

# Проверка параметров командной строки
if [ "$1" = "--uninstall" ] || [ "$1" = "--remove" ] || [ "$1" = "-u" ] || [ "$1" = "-r" ] || [ "$1" = "uninstall" ] || [ "$1" = "remove" ]; then
    uninstall_project
fi

# Показ справки если запрошена
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then
    echo -e "${GREEN}=== Service Management API - Deployment Script ===${NC}\n"
    echo -e "${YELLOW}Использование:${NC}"
    echo -e "  ${GREEN}sudo ./deploy.sh${NC}              - Установка проекта"
    echo -e "  ${GREEN}sudo ./deploy.sh --uninstall${NC}  - Удаление проекта"
    echo -e "  ${GREEN}sudo ./deploy.sh --help${NC}       - Показать эту справку"
    echo ""
    echo -e "${YELLOW}Параметры установки через переменные окружения:${NC}"
    echo -e "  ${GREEN}SERVICE_MANAGEMENT_TOKEN${NC} - Токен безопасности"
    echo -e "  ${GREEN}SERVICE_MANAGEMENT_PORT${NC}   - Порт приложения"
    echo ""
    echo -e "${YELLOW}Примеры:${NC}"
    echo -e "  export SERVICE_MANAGEMENT_TOKEN=your_token"
    echo ""
    echo -e "${YELLOW}Списки сервисов:${NC}"
    echo -e "  Списки настраиваются интерактивно при установке"
    echo -e "  Файлы: /opt/service-management/whitelist.txt и blacklist.txt"
    echo -e "  Можно редактировать вручную после установки (перезагрузка не требуется)"
    echo -e "  export SERVICE_MANAGEMENT_PORT=5001"
    echo -e "  sudo ./deploy.sh"
    echo ""
    exit 0
fi

echo -e "${GREEN}=== Service Management API - Deployment Script ===${NC}\n"

# Функция для определения менеджера пакетов
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

# Функция для установки пакетов
install_packages() {
    local packages=("$@")
    local pkg_manager=$(detect_package_manager)
    
    if [ "$pkg_manager" = "unknown" ]; then
        return 1
    fi
    
    case $pkg_manager in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}" 2>/dev/null
            ;;
        yum)
            yum install -y -q "${packages[@]}" 2>/dev/null
            ;;
        dnf)
            dnf install -y -q "${packages[@]}" 2>/dev/null
            ;;
    esac
}

# Функция для проверки команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        return 1
    fi
    return 0
}

# Функция для проверки занятости порта
check_port() {
    local port=$1
    # Проверяем через netstat, ss или lsof
    if command -v ss &> /dev/null; then
        ss -tuln | grep -q ":$port " && return 1
    elif command -v netstat &> /dev/null; then
        netstat -tuln | grep -q ":$port " && return 1
    elif command -v lsof &> /dev/null; then
        lsof -i :$port &> /dev/null && return 1
    else
        # Если нет инструментов, пробуем подключиться через timeout
        timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null && return 1
    fi
    return 0
}

# Функция для поиска свободного порта
find_free_port() {
    local start_port=$1
    local port=$start_port
    local max_port=$((start_port + 100))
    
    while [ $port -le $max_port ]; do
        if check_port $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
    
    return 1
}

# Проверка окружения
echo -e "${YELLOW}[1/7] Проверка окружения...${NC}"

# Проверка что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Скрипт должен быть запущен от root (используйте sudo)${NC}"
    exit 1
fi

# Проверка и установка Python
if ! check_command python3; then
    echo -e "${YELLOW}Python3 не найден. Пытаюсь установить...${NC}"
    pkg_manager=$(detect_package_manager)
    case $pkg_manager in
        apt)
            install_packages python3 python3-pip python3-venv
            ;;
        yum|dnf)
            install_packages python3 python3-pip
            # Для CentOS/RHEL может потребоваться дополнительный репозиторий
            if ! check_command python3; then
                echo -e "${RED}Python3 не установлен. Установите вручную:${NC}"
                echo -e "  ${YELLOW}Для CentOS/RHEL: yum install python3 python3-pip${NC}"
                echo -e "  ${YELLOW}Для Ubuntu/Debian: apt-get install python3 python3-pip python3-venv${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Не удалось определить менеджер пакетов. Установите Python3 вручную.${NC}"
            exit 1
            ;;
    esac
    
    if ! check_command python3; then
        echo -e "${RED}Не удалось установить Python3 автоматически. Установите вручную.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Python3 установлен${NC}"
fi

# Проверка python3-pip
if ! check_command pip3 && ! python3 -m pip --version &> /dev/null; then
    echo -e "${YELLOW}pip3 не найден. Пытаюсь установить...${NC}"
    pkg_manager=$(detect_package_manager)
    case $pkg_manager in
        apt)
            install_packages python3-pip
            ;;
        yum|dnf)
            install_packages python3-pip
            ;;
    esac
fi

# Проверка python3-venv (для Ubuntu/Debian)
if [ "$(detect_package_manager)" = "apt" ]; then
    if ! python3 -m venv --help &> /dev/null 2>&1; then
        echo -e "${YELLOW}python3-venv не найден. Пытаюсь установить...${NC}"
        install_packages python3-venv
        if ! python3 -m venv --help &> /dev/null 2>&1; then
            echo -e "${RED}Не удалось установить python3-venv. Установите вручную: apt-get install python3-venv${NC}"
            exit 1
        fi
        echo -e "${GREEN}python3-venv установлен${NC}"
    fi
fi

# Проверка версии Python (минимум 3.7)
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 7 ]); then
    echo -e "${RED}Требуется Python 3.7 или выше. Текущая версия: $PYTHON_VERSION${NC}"
    exit 1
fi

echo -e "${GREEN}Python версия: $PYTHON_VERSION${NC}"

# Определение веб-сервера
if systemctl is-active --quiet nginx; then
    WEB_SERVER="nginx"
    echo -e "${GREEN}Обнаружен веб-сервер: Nginx${NC}"
elif systemctl is-active --quiet apache2; then
    WEB_SERVER="apache2"
    echo -e "${GREEN}Обнаружен веб-сервер: Apache${NC}"
else
    echo -e "${YELLOW}Веб-сервер не обнаружен. Продолжаем без настройки веб-сервера.${NC}"
fi

# Проверка systemctl
if ! check_command systemctl; then
    echo -e "${RED}systemctl не найден. Это не systemd система?${NC}"
    exit 1
fi

echo -e "${GREEN}Окружение проверено успешно${NC}\n"

# Проверка и выбор порта
echo -e "${YELLOW}[1.5/7] Проверка доступности порта...${NC}"
if [ -n "$SERVICE_MANAGEMENT_PORT" ]; then
    APP_PORT=$SERVICE_MANAGEMENT_PORT
    echo -e "${GREEN}Порт задан через переменную окружения: $APP_PORT${NC}"
else
    if check_port $DEFAULT_PORT; then
        APP_PORT=$DEFAULT_PORT
        echo -e "${GREEN}Порт $DEFAULT_PORT свободен${NC}"
    else
        echo -e "${YELLOW}Порт $DEFAULT_PORT занят. Ищу свободный порт...${NC}"
        FREE_PORT=$(find_free_port $DEFAULT_PORT)
        if [ -n "$FREE_PORT" ]; then
            APP_PORT=$FREE_PORT
            echo -e "${GREEN}Найден свободный порт: $APP_PORT${NC}"
            echo -e "${YELLOW}Вы можете задать другой порт через переменную SERVICE_MANAGEMENT_PORT${NC}"
        else
            echo -e "${RED}Не удалось найти свободный порт в диапазоне $DEFAULT_PORT-$((DEFAULT_PORT + 100))${NC}"
            echo -e "${YELLOW}Введите порт вручную (или нажмите Enter для выхода):${NC}"
            read PORT_INPUT
            if [ -z "$PORT_INPUT" ]; then
                echo -e "${RED}Установка прервана${NC}"
                exit 1
            fi
            APP_PORT=$PORT_INPUT
            if ! check_port $APP_PORT; then
                echo -e "${RED}Порт $APP_PORT также занят. Установка прервана${NC}"
                exit 1
            fi
        fi
    fi
fi
echo ""

# Пользователь сам настроит веб-сервер с нужным доменом

# Создание директории проекта
echo -e "${YELLOW}[2/7] Создание директории проекта...${NC}"
mkdir -p $PROJECT_DIR
echo -e "${GREEN}Директория создана: $PROJECT_DIR${NC}\n"

# Копирование файлов проекта
echo -e "${YELLOW}[3/7] Копирование файлов проекта...${NC}"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cp -r $SCRIPT_DIR/* $PROJECT_DIR/ 2>/dev/null || true
chown -R www-data:www-data $PROJECT_DIR
chmod +x $PROJECT_DIR/app.py
echo -e "${GREEN}Файлы скопированы${NC}\n"

# Создание виртуального окружения Python
echo -e "${YELLOW}[4/7] Создание виртуального окружения Python...${NC}"
cd $PROJECT_DIR
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
echo -e "${GREEN}Виртуальное окружение создано и зависимости установлены${NC}\n"

# Настройка токена
echo -e "${YELLOW}[5/7] Настройка токена безопасности...${NC}"
if [ -z "$SERVICE_MANAGEMENT_TOKEN" ]; then
    echo -e "${YELLOW}Введите токен безопасности (или нажмите Enter для генерации случайного):${NC}"
    read -s TOKEN_INPUT
    if [ -z "$TOKEN_INPUT" ]; then
        TOKEN=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
        echo -e "${GREEN}Сгенерирован случайный токен${NC}"
    else
        TOKEN=$TOKEN_INPUT
    fi
else
    TOKEN=$SERVICE_MANAGEMENT_TOKEN
fi

# Обновление systemd service файла с портом (токен заменим после копирования)
sed -i "s|--bind 127.0.0.1:5000|--bind 127.0.0.1:$APP_PORT|g" $PROJECT_DIR/service-management.service
echo -e "${GREEN}Порт настроен${NC}"
echo -e "${YELLOW}ВАЖНО: Сохраните этот токен в безопасном месте!${NC}"
echo -e "${YELLOW}TOKEN: $TOKEN${NC}"
echo -e "${YELLOW}PORT: $APP_PORT${NC}\n"

# Настройка белого и черного списков сервисов
echo -e "${YELLOW}[5.1/7] Настройка списков сервисов (опционально)...${NC}"
WHITELIST_FILE="$PROJECT_DIR/whitelist.txt"
BLACKLIST_FILE="$PROJECT_DIR/blacklist.txt"

# Создание файла белого списка
echo -e "${YELLOW}Белый список: разрешены только указанные сервисы${NC}"
echo -e "${YELLOW}Введите имена сервисов через запятую или пробел (например: nginx.service apache2.service)${NC}"
echo -e "${YELLOW}Оставьте пустым если не нужен белый список:${NC}"
read WHITELIST_INPUT

if [ -n "$WHITELIST_INPUT" ]; then
    # Разбиваем ввод на строки (запятая, пробел или перевод строки)
    echo "$WHITELIST_INPUT" | tr ',' '\n' | tr ' ' '\n' | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$WHITELIST_FILE"
    chmod 644 "$WHITELIST_FILE"
    chown www-data:www-data "$WHITELIST_FILE"
    echo -e "${GREEN}Белый список сохранен в $WHITELIST_FILE${NC}"
else
    # Создаем пустой файл если список не задан
    touch "$WHITELIST_FILE"
    chmod 644 "$WHITELIST_FILE"
    chown www-data:www-data "$WHITELIST_FILE"
    echo -e "${GREEN}Белый список не задан (файл создан пустым)${NC}"
fi

# Создание файла черного списка
echo ""
echo -e "${YELLOW}Черный список: запрещены указанные сервисы${NC}"
echo -e "${YELLOW}Введите имена сервисов через запятую или пробел (например: ssh.service systemd.service)${NC}"
echo -e "${YELLOW}Оставьте пустым если не нужен черный список:${NC}"
read BLACKLIST_INPUT

if [ -n "$BLACKLIST_INPUT" ]; then
    # Разбиваем ввод на строки (запятая, пробел или перевод строки)
    echo "$BLACKLIST_INPUT" | tr ',' '\n' | tr ' ' '\n' | grep -v '^$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$BLACKLIST_FILE"
    chmod 644 "$BLACKLIST_FILE"
    chown www-data:www-data "$BLACKLIST_FILE"
    echo -e "${GREEN}Черный список сохранен в $BLACKLIST_FILE${NC}"
else
    # Создаем пустой файл если список не задан
    touch "$BLACKLIST_FILE"
    chmod 644 "$BLACKLIST_FILE"
    chown www-data:www-data "$BLACKLIST_FILE"
    echo -e "${GREEN}Черный список не задан (файл создан пустым)${NC}"
fi
echo ""
echo -e "${YELLOW}Примечание: Файлы списков можно редактировать вручную после установки:${NC}"
echo -e "${YELLOW}  $WHITELIST_FILE${NC}"
echo -e "${YELLOW}  $BLACKLIST_FILE${NC}"
echo -e "${YELLOW}Изменения применяются сразу, перезагрузка сервиса не требуется.${NC}"
echo ""

# Настройка sudoers для www-data
echo -e "${YELLOW}[5.5/7] Настройка прав sudo для www-data...${NC}"
SUDOERS_FILE="/etc/sudoers.d/service-management"
if [ -f "$SUDOERS_FILE" ]; then
    echo -e "${YELLOW}Файл sudoers уже существует, обновляю...${NC}"
else
    echo -e "${GREEN}Создание файла sudoers...${NC}"
fi

# Создаем правило sudoers для www-data
cat > /tmp/service-management-sudoers << EOF
# Правила sudo для Service Management API
# Позволяет пользователю www-data выполнять systemctl команды без пароля
www-data ALL=(ALL) NOPASSWD: /bin/systemctl status *, /bin/systemctl start *, /bin/systemctl stop *, /bin/systemctl restart *
EOF

# Проверяем синтаксис перед применением
if visudo -c -f /tmp/service-management-sudoers 2>/dev/null; then
    cp /tmp/service-management-sudoers $SUDOERS_FILE
    chmod 0440 $SUDOERS_FILE
    rm /tmp/service-management-sudoers
    echo -e "${GREEN}Права sudo настроены успешно${NC}"
else
    echo -e "${RED}Ошибка в синтаксисе sudoers файла${NC}"
    rm /tmp/service-management-sudoers
    exit 1
fi
echo ""

# Установка systemd сервиса
echo -e "${YELLOW}[6/7] Установка systemd сервиса...${NC}"
cp $PROJECT_DIR/service-management.service /etc/systemd/system/$SERVICE_NAME.service

# Заменяем токен в скопированном файле
# Используем разделитель | вместо / чтобы избежать проблем с токеном
# Экранируем специальные символы для sed
ESCAPED_TOKEN=$(printf '%s\n' "$TOKEN" | sed 's/[[\.*^$()+?{|]/\\&/g')
sed -i "s|SERVICE_MANAGEMENT_TOKEN=CHANGE_THIS_TOKEN|SERVICE_MANAGEMENT_TOKEN=$ESCAPED_TOKEN|g" /etc/systemd/system/$SERVICE_NAME.service

# Проверяем что замена прошла успешно (проверяем что CHANGE_THIS_TOKEN больше нет)
if grep -q "CHANGE_THIS_TOKEN" /etc/systemd/system/$SERVICE_NAME.service; then
    echo -e "${RED}Ошибка: Токен не был заменен в systemd service файле!${NC}"
    echo -e "${YELLOW}Попытка замены вручную...${NC}"
    # Пробуем еще раз без экранирования (для hex токенов это должно работать)
    sed -i "s|SERVICE_MANAGEMENT_TOKEN=CHANGE_THIS_TOKEN|SERVICE_MANAGEMENT_TOKEN=$TOKEN|g" /etc/systemd/system/$SERVICE_NAME.service
    if grep -q "CHANGE_THIS_TOKEN" /etc/systemd/system/$SERVICE_NAME.service; then
        echo -e "${RED}Критическая ошибка: Не удалось установить токен!${NC}"
        exit 1
    else
        echo -e "${GREEN}Токен установлен после повторной попытки${NC}"
    fi
else
    echo -e "${GREEN}Токен установлен${NC}"
fi

# Заменяем белый и черный списки
if [ -n "$WHITELIST" ]; then
    ESCAPED_WHITELIST=$(printf '%s\n' "$WHITELIST" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "s|SERVICE_MANAGEMENT_WHITELIST=|SERVICE_MANAGEMENT_WHITELIST=$ESCAPED_WHITELIST|g" /etc/systemd/system/$SERVICE_NAME.service
else
    sed -i "s|SERVICE_MANAGEMENT_WHITELIST=|SERVICE_MANAGEMENT_WHITELIST=|g" /etc/systemd/system/$SERVICE_NAME.service
fi

if [ -n "$BLACKLIST" ]; then
    ESCAPED_BLACKLIST=$(printf '%s\n' "$BLACKLIST" | sed 's/[[\.*^$()+?{|]/\\&/g')
    sed -i "s|SERVICE_MANAGEMENT_BLACKLIST=|SERVICE_MANAGEMENT_BLACKLIST=$ESCAPED_BLACKLIST|g" /etc/systemd/system/$SERVICE_NAME.service
else
    sed -i "s|SERVICE_MANAGEMENT_BLACKLIST=|SERVICE_MANAGEMENT_BLACKLIST=|g" /etc/systemd/system/$SERVICE_NAME.service
fi

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Проверка статуса
sleep 2
if systemctl is-active --quiet $SERVICE_NAME; then
    echo -e "${GREEN}Сервис успешно запущен${NC}"
else
    echo -e "${RED}Ошибка при запуске сервиса. Проверьте логи: journalctl -u $SERVICE_NAME${NC}"
    exit 1
fi
echo ""

# Настройка веб-сервера
echo -e "${YELLOW}[7/7] Настройка веб-сервера...${NC}"

if [ "$WEB_SERVER" = "nginx" ]; then
    # Поиск конфигурационных файлов Nginx
    NGINX_CONFIGS_FOUND=0
    NGINX_CONFIGS_LIST=""
    
    # Проверяем sites-available
    if [ -d "/etc/nginx/sites-available" ]; then
        for config in /etc/nginx/sites-available/*; do
            if [ -f "$config" ] && [ -L "/etc/nginx/sites-enabled/$(basename $config)" ] 2>/dev/null; then
                NGINX_CONFIGS_FOUND=$((NGINX_CONFIGS_FOUND + 1))
                NGINX_CONFIGS_LIST="$NGINX_CONFIGS_LIST\n  - $config (активен)"
            elif [ -f "$config" ]; then
                NGINX_CONFIGS_FOUND=$((NGINX_CONFIGS_FOUND + 1))
                NGINX_CONFIGS_LIST="$NGINX_CONFIGS_LIST\n  - $config"
            fi
        done
    fi
    
    # Проверяем conf.d
    if [ -d "/etc/nginx/conf.d" ]; then
        for config in /etc/nginx/conf.d/*.conf; do
            if [ -f "$config" ]; then
                NGINX_CONFIGS_FOUND=$((NGINX_CONFIGS_FOUND + 1))
                NGINX_CONFIGS_LIST="$NGINX_CONFIGS_LIST\n  - $config"
            fi
        done
    fi
    
    # Проверяем основной конфиг
    if [ -f "/etc/nginx/nginx.conf" ]; then
        NGINX_CONFIGS_FOUND=$((NGINX_CONFIGS_FOUND + 1))
        NGINX_CONFIGS_LIST="$NGINX_CONFIGS_LIST\n  - /etc/nginx/nginx.conf"
    fi
    
    # Пытаемся найти конфигурацию с /servise/
    NGINX_CONFIG_WITH_SERVISE=""
    if [ -d "/etc/nginx/sites-available" ]; then
        for config in /etc/nginx/sites-available/*; do
            if [ -f "$config" ] && grep -q "location /servise/" "$config" 2>/dev/null; then
                NGINX_CONFIG_WITH_SERVISE="$config"
                break
            fi
        done
    fi
    
    if [ -n "$NGINX_CONFIG_WITH_SERVISE" ]; then
        echo -e "${YELLOW}Конфигурация для /servise/ уже существует в $NGINX_CONFIG_WITH_SERVISE${NC}"
        # Обновляем порт в существующей конфигурации если нужно
        if grep -q "proxy_pass http://127.0.0.1:" "$NGINX_CONFIG_WITH_SERVISE" 2>/dev/null; then
            sed -i "s|proxy_pass http://127.0.0.1:[0-9]*;|proxy_pass http://127.0.0.1:$APP_PORT;|g" "$NGINX_CONFIG_WITH_SERVISE"
            echo -e "${GREEN}Порт обновлен в конфигурации Nginx${NC}"
        fi
    else
        echo -e "${YELLOW}Настройка Nginx:${NC}"
        if [ "$NGINX_CONFIGS_FOUND" -gt 0 ]; then
            echo -e "${YELLOW}Найдено конфигурационных файлов: $NGINX_CONFIGS_FOUND${NC}"
            echo -e "${YELLOW}Доступные конфигурации:$NGINX_CONFIGS_LIST${NC}"
            echo ""
            echo -e "${YELLOW}Добавьте следующий блок в server блок нужного домена (выберите подходящий файл из списка выше):${NC}"
        else
            echo -e "${YELLOW}Добавьте следующий блок в server блок вашего домена в конфигурационном файле Nginx:${NC}"
        fi
        echo ""
        echo "location /servise/ {"
        echo "    proxy_pass http://127.0.0.1:$APP_PORT;"
        echo "    proxy_set_header Host \$host;"
        echo "    proxy_set_header X-Real-IP \$remote_addr;"
        echo "    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
        echo "    proxy_set_header X-Forwarded-Proto \$scheme;"
        echo "    proxy_connect_timeout 60s;"
        echo "    proxy_send_timeout 60s;"
        echo "    proxy_read_timeout 60s;"
        echo "    proxy_buffering off;"
        echo "}"
        echo ""
        if [ "$NGINX_CONFIGS_FOUND" -gt 0 ]; then
            echo -e "${YELLOW}После добавления выполните: nginx -t && systemctl reload nginx${NC}"
        else
            echo -e "${YELLOW}Пример конфигурации: $PROJECT_DIR/nginx.conf.example${NC}"
            echo -e "${YELLOW}После добавления выполните: nginx -t && systemctl reload nginx${NC}"
        fi
    fi
    
elif [ "$WEB_SERVER" = "apache2" ]; then
    # Поиск конфигурационных файлов Apache
    APACHE_CONFIGS_FOUND=0
    APACHE_CONFIGS_LIST=""
    
    # Проверяем sites-available
    if [ -d "/etc/apache2/sites-available" ]; then
        for config in /etc/apache2/sites-available/*.conf; do
            if [ -f "$config" ]; then
                # Проверяем активен ли сайт
                SITE_NAME=$(basename "$config" .conf)
                if [ -L "/etc/apache2/sites-enabled/$SITE_NAME.conf" ] 2>/dev/null || [ -L "/etc/apache2/sites-enabled/$(basename $config)" ] 2>/dev/null; then
                    APACHE_CONFIGS_FOUND=$((APACHE_CONFIGS_FOUND + 1))
                    APACHE_CONFIGS_LIST="$APACHE_CONFIGS_LIST\n  - $config (активен)"
                else
                    APACHE_CONFIGS_FOUND=$((APACHE_CONFIGS_FOUND + 1))
                    APACHE_CONFIGS_LIST="$APACHE_CONFIGS_LIST\n  - $config"
                fi
            fi
        done
    fi
    
    # Проверяем conf-available (для дополнительных конфигураций)
    if [ -d "/etc/apache2/conf-available" ]; then
        for config in /etc/apache2/conf-available/*.conf; do
            if [ -f "$config" ]; then
                APACHE_CONFIGS_FOUND=$((APACHE_CONFIGS_FOUND + 1))
                APACHE_CONFIGS_LIST="$APACHE_CONFIGS_LIST\n  - $config"
            fi
        done
    fi
    
    # Пытаемся найти конфигурацию с /servise/
    APACHE_CONFIG_WITH_SERVISE=""
    if [ -d "/etc/apache2/sites-available" ]; then
        for config in /etc/apache2/sites-available/*.conf; do
            if [ -f "$config" ] && grep -q "Location /servise/" "$config" 2>/dev/null; then
                APACHE_CONFIG_WITH_SERVISE="$config"
                break
            fi
        done
    fi
    
    if [ -n "$APACHE_CONFIG_WITH_SERVISE" ]; then
        echo -e "${YELLOW}Конфигурация для /servise/ уже существует в $APACHE_CONFIG_WITH_SERVISE${NC}"
        # Обновляем порт в существующей конфигурации если нужно
        if grep -q "ProxyPass http://127.0.0.1:" "$APACHE_CONFIG_WITH_SERVISE" 2>/dev/null; then
            sed -i "s|ProxyPass http://127.0.0.1:[0-9]*/servise/|ProxyPass http://127.0.0.1:$APP_PORT/servise/|g" "$APACHE_CONFIG_WITH_SERVISE"
            sed -i "s|ProxyPassReverse http://127.0.0.1:[0-9]*/servise/|ProxyPassReverse http://127.0.0.1:$APP_PORT/servise/|g" "$APACHE_CONFIG_WITH_SERVISE"
            echo -e "${GREEN}Порт обновлен в конфигурации Apache${NC}"
        fi
    else
        echo -e "${YELLOW}Настройка Apache:${NC}"
        if [ "$APACHE_CONFIGS_FOUND" -gt 0 ]; then
            echo -e "${YELLOW}Найдено конфигурационных файлов: $APACHE_CONFIGS_FOUND${NC}"
            echo -e "${YELLOW}Доступные конфигурации:$APACHE_CONFIGS_LIST${NC}"
            echo ""
            echo -e "${YELLOW}Добавьте следующий блок в VirtualHost нужного домена (выберите подходящий файл из списка выше):${NC}"
        else
            echo -e "${YELLOW}Добавьте следующий блок в VirtualHost вашего домена в конфигурационном файле Apache:${NC}"
        fi
        echo ""
        echo "<Location /servise/>"
        echo "    ProxyPass http://127.0.0.1:$APP_PORT/servise/"
        echo "    ProxyPassReverse http://127.0.0.1:$APP_PORT/servise/"
        echo "    ProxyPreserveHost On"
        echo "    RequestHeader set X-Forwarded-Proto \"https\""
        echo "    ProxyTimeout 60"
        echo "</Location>"
        echo ""
        echo -e "${YELLOW}Включите модули (если еще не включены):${NC}"
        echo -e "${YELLOW}  sudo a2enmod proxy proxy_http headers${NC}"
        if [ "$APACHE_CONFIGS_FOUND" -gt 0 ]; then
            echo -e "${YELLOW}После добавления выполните: apache2ctl configtest && systemctl reload apache2${NC}"
        else
            echo -e "${YELLOW}Пример конфигурации: $PROJECT_DIR/apache.conf.example${NC}"
            echo -e "${YELLOW}После добавления выполните: apache2ctl configtest && systemctl reload apache2${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Веб-сервер не обнаружен. Настройте проксирование вручную.${NC}"
    echo -e "${YELLOW}Примеры конфигураций:${NC}"
    echo -e "  - Nginx: $PROJECT_DIR/nginx.conf.example"
    echo -e "  - Apache: $PROJECT_DIR/apache.conf.example"
fi

echo ""
echo -e "${GREEN}=== Развертывание завершено! ===${NC}\n"

# Сохранение конфигурации в файл для справки
CONFIG_FILE="$PROJECT_DIR/.deployment_config"
cat > $CONFIG_FILE << EOF
PORT=$APP_PORT
TOKEN=$TOKEN
EOF
chmod 600 $CONFIG_FILE
chown www-data:www-data $CONFIG_FILE

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Конфигурация развертывания${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "  Порт приложения: ${YELLOW}$APP_PORT${NC}"
echo -e "  Токен:           ${YELLOW}$TOKEN${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Адреса для управления сервисами (локально)${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Получение статуса сервиса:${NC}"
echo -e "  ${GREEN}curl \"http://127.0.0.1:$APP_PORT/servise/status/nginx.service?TOKEN=$TOKEN\"${NC}"
echo ""
echo -e "${YELLOW}Запуск сервиса:${NC}"
echo -e "  ${GREEN}curl \"http://127.0.0.1:$APP_PORT/servise/start/nginx.service?TOKEN=$TOKEN\"${NC}"
echo ""
echo -e "${YELLOW}Остановка сервиса:${NC}"
echo -e "  ${GREEN}curl \"http://127.0.0.1:$APP_PORT/servise/stop/nginx.service?TOKEN=$TOKEN\"${NC}"
echo ""
echo -e "${YELLOW}Перезагрузка сервиса:${NC}"
echo -e "  ${GREEN}curl \"http://127.0.0.1:$APP_PORT/servise/restart/nginx.service?TOKEN=$TOKEN\"${NC}"
echo ""
echo -e "${YELLOW}Примечание:${NC} После настройки веб-сервера используйте адреса вида:"
echo -e "  ${GREEN}https://your-domain.com/servise/status/nginx.service?TOKEN=$TOKEN${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Проверка работы API${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}curl http://127.0.0.1:$APP_PORT/health${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Управление сервисом${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}systemctl status $SERVICE_NAME${NC}"
echo -e "  ${YELLOW}systemctl restart $SERVICE_NAME${NC}"
echo -e "  ${YELLOW}systemctl stop $SERVICE_NAME${NC}"
echo -e "  ${YELLOW}systemctl start $SERVICE_NAME${NC}"
echo -e "  ${YELLOW}journalctl -u $SERVICE_NAME -f${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}ВАЖНО: Сохраните токен в безопасном месте!${NC}"
echo -e "${YELLOW}Конфигурация также сохранена в: $CONFIG_FILE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"

