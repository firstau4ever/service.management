#!/usr/bin/env python3
"""
Service Management API
Веб-интерфейс для управления systemd сервисами
"""

import os
import re
import subprocess
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

# Токен для авторизации (должен быть установлен через переменную окружения)
AUTH_TOKEN = os.environ.get('SERVICE_MANAGEMENT_TOKEN', 'change_me_in_production')

# Валидация имени сервиса: только буквы, цифры, дефисы, точки и подчеркивания
# Поддерживает как с .service, так и без него
SERVICE_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9._-]+(\.service)?$')

# Пути к файлам со списками сервисов
WHITELIST_FILE = '/opt/service-management/whitelist.txt'
BLACKLIST_FILE = '/opt/service-management/blacklist.txt'


def normalize_service_name(service_name):
    """
    Нормализация имени сервиса - добавляет .service если его нет.
    Это позволяет использовать как nginx, так и nginx.service
    
    Args:
        service_name: имя сервиса (может быть с .service или без)
    
    Returns:
        str: нормализованное имя сервиса (всегда с .service)
    """
    if not service_name:
        return None
    # Убираем пробелы
    service_name = service_name.strip()
    # Если уже заканчивается на .service, возвращаем как есть
    if service_name.endswith('.service'):
        return service_name
    # Иначе добавляем .service
    return f"{service_name}.service"


def validate_service_name(service_name):
    """
    Валидация имени сервиса для защиты от инъекций.
    Разрешает только безопасные символы. Поддерживает как с .service, так и без него.
    """
    if not service_name:
        return False
    return bool(SERVICE_NAME_PATTERN.match(service_name))


def validate_token(token):
    """Проверка токена авторизации"""
    return token == AUTH_TOKEN


def read_service_list(file_path):
    """
    Чтение списка сервисов из файла.
    Каждая строка - один сервис, пустые строки и строки начинающиеся с # игнорируются.
    Имена сервисов нормализуются (добавляется .service если его нет).
    
    Args:
        file_path: путь к файлу со списком
    
    Returns:
        list: список нормализованных имен сервисов (всегда с .service)
    """
    services = []
    if os.path.exists(file_path):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    # Пропускаем пустые строки и комментарии
                    if line and not line.startswith('#'):
                        # Нормализуем имя сервиса (добавляем .service если его нет)
                        normalized = normalize_service_name(line)
                        if normalized:
                            services.append(normalized)
        except Exception:
            # В случае ошибки чтения файла возвращаем пустой список
            pass
    return services


def is_service_allowed(service_name):
    """
    Проверка разрешен ли сервис для управления по белого/черного спискам.
    
    Логика:
    - Если белый список существует и не пуст: разрешены только сервисы из белого списка
    - Если белый список не задан или пуст: разрешены все, кроме тех что в черном списке
    - Черный список: запрещены сервисы из черного списка
    - Файлы читаются при каждом запросе (динамически), перезагрузка не требуется
    - Имена сервисов нормализуются (добавляется .service если его нет) для сравнения
    
    Args:
        service_name: имя сервиса для проверки (может быть с .service или без)
    
    Returns:
        bool: True если сервис разрешен, False если запрещен
    """
    # Нормализуем имя сервиса из запроса
    normalized_service = normalize_service_name(service_name)
    if not normalized_service:
        return False
    
    # Читаем списки из файлов при каждом запросе (динамически)
    # Имена в списках уже нормализованы при чтении
    whitelist = read_service_list(WHITELIST_FILE)
    blacklist = read_service_list(BLACKLIST_FILE)
    
    # Если белый список задан и не пуст - проверяем его первым
    if whitelist:
        if normalized_service not in whitelist:
            return False
    
    # Проверяем черный список
    if blacklist:
        if normalized_service in blacklist:
            return False
    
    # Если белый список не задан или пуст, и сервис не в черном списке - разрешен
    return True


def execute_systemctl_command(action, service_name):
    """
    Безопасное выполнение команды systemctl.
    
    Args:
        action: действие (status, start, stop, restart)
        service_name: имя сервиса (уже валидировано)
    
    Returns:
        tuple: (success: bool, output: str, error: str)
    """
    if action not in ['status', 'start', 'stop', 'restart']:
        return False, None, "Invalid action"
    
    try:
        # Используем sudo для выполнения systemctl команд
        # Это предотвращает shell injection и обеспечивает безопасность
        # Используем полный путь к sudo для надежности
        sudo_path = '/usr/bin/sudo'
        if not os.path.exists(sudo_path):
            sudo_path = 'sudo'  # Fallback если sudo не в стандартном месте
        cmd = [sudo_path, '-n', 'systemctl', action, service_name]
        
        # Для status используем --no-pager чтобы получить весь вывод
        if action == 'status':
            cmd.extend(['--no-pager', '--lines=0'])
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            check=False
        )
        
        return result.returncode == 0, result.stdout, result.stderr
        
    except subprocess.TimeoutExpired:
        return False, None, "Command timeout"
    except Exception as e:
        return False, None, str(e)


@app.route('/servise/status/<service_name>', methods=['GET'])
def get_status(service_name):
    """Получение статуса сервиса"""
    token = request.args.get('TOKEN')
    
    if not validate_token(token):
        return jsonify({'error': 'Unauthorized: Invalid or missing TOKEN'}), 401
    
    if not validate_service_name(service_name):
        return jsonify({'error': 'Invalid service name'}), 400
    
    # Нормализуем имя сервиса для использования в systemctl
    normalized_service = normalize_service_name(service_name)
    if not normalized_service:
        return jsonify({'error': 'Invalid service name'}), 400
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('status', normalized_service)
    
    if success:
        return jsonify({
            'service': service_name,
            'status': 'running',
            'output': output
        }), 200
    else:
        return jsonify({
            'service': service_name,
            'status': 'error',
            'error': error or output
        }), 200


@app.route('/servise/start/<service_name>', methods=['GET'])
def start_service(service_name):
    """Запуск сервиса"""
    token = request.args.get('TOKEN')
    
    if not validate_token(token):
        return jsonify({'error': 'Unauthorized: Invalid or missing TOKEN'}), 401
    
    if not validate_service_name(service_name):
        return jsonify({'error': 'Invalid service name'}), 400
    
    # Нормализуем имя сервиса для использования в systemctl
    normalized_service = normalize_service_name(service_name)
    if not normalized_service:
        return jsonify({'error': 'Invalid service name'}), 400
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('start', normalized_service)
    
    if success:
        return jsonify({
            'service': service_name,
            'action': 'start',
            'status': 'success',
            'message': f'Service {service_name} started successfully'
        }), 200
    else:
        return jsonify({
            'service': service_name,
            'action': 'start',
            'status': 'error',
            'error': error or output
        }), 500


@app.route('/servise/stop/<service_name>', methods=['GET'])
def stop_service(service_name):
    """Остановка сервиса"""
    token = request.args.get('TOKEN')
    
    if not validate_token(token):
        return jsonify({'error': 'Unauthorized: Invalid or missing TOKEN'}), 401
    
    if not validate_service_name(service_name):
        return jsonify({'error': 'Invalid service name'}), 400
    
    # Нормализуем имя сервиса для использования в systemctl
    normalized_service = normalize_service_name(service_name)
    if not normalized_service:
        return jsonify({'error': 'Invalid service name'}), 400
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('stop', normalized_service)
    
    if success:
        return jsonify({
            'service': service_name,
            'action': 'stop',
            'status': 'success',
            'message': f'Service {service_name} stopped successfully'
        }), 200
    else:
        return jsonify({
            'service': service_name,
            'action': 'stop',
            'status': 'error',
            'error': error or output
        }), 500


@app.route('/servise/restart/<service_name>', methods=['GET'])
def restart_service(service_name):
    """Перезагрузка сервиса"""
    token = request.args.get('TOKEN')
    
    if not validate_token(token):
        return jsonify({'error': 'Unauthorized: Invalid or missing TOKEN'}), 401
    
    if not validate_service_name(service_name):
        return jsonify({'error': 'Invalid service name'}), 400
    
    # Нормализуем имя сервиса для использования в systemctl
    normalized_service = normalize_service_name(service_name)
    if not normalized_service:
        return jsonify({'error': 'Invalid service name'}), 400
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('restart', normalized_service)
    
    if success:
        return jsonify({
            'service': service_name,
            'action': 'restart',
            'status': 'success',
            'message': f'Service {service_name} restarted successfully'
        }), 200
    else:
        return jsonify({
            'service': service_name,
            'action': 'restart',
            'status': 'error',
            'error': error or output
        }), 500


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'ok'}), 200


if __name__ == '__main__':
    # Для разработки
    app.run(host='127.0.0.1', port=5000, debug=False)
else:
    # Для production с gunicorn
    pass

