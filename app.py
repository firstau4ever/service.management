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
SERVICE_NAME_PATTERN = re.compile(r'^[a-zA-Z0-9._-]+\.service$')

# Белый и черный списки сервисов
# Белый список: если задан, разрешены только сервисы из этого списка
# Черный список: если задан, запрещены сервисы из этого списка
# Формат: список через запятую, например: "nginx.service,apache2.service"
WHITELIST_STR = os.environ.get('SERVICE_MANAGEMENT_WHITELIST', '').strip()
BLACKLIST_STR = os.environ.get('SERVICE_MANAGEMENT_BLACKLIST', '').strip()

# Парсинг списков
SERVICE_WHITELIST = [s.strip() for s in WHITELIST_STR.split(',')] if WHITELIST_STR else []
SERVICE_BLACKLIST = [s.strip() for s in BLACKLIST_STR.split(',')] if BLACKLIST_STR else []


def validate_service_name(service_name):
    """
    Валидация имени сервиса для защиты от инъекций.
    Разрешает только безопасные символы и требует расширение .service
    """
    if not service_name:
        return False
    return bool(SERVICE_NAME_PATTERN.match(service_name))


def validate_token(token):
    """Проверка токена авторизации"""
    return token == AUTH_TOKEN


def is_service_allowed(service_name):
    """
    Проверка разрешен ли сервис для управления по белого/черного спискам.
    
    Логика:
    - Если задан белый список: разрешены только сервисы из белого списка
    - Если задан черный список: запрещены сервисы из черного списка
    - Если заданы оба: сначала проверяется белый список, потом черный
    - Если ни один не задан: все разрешено
    
    Args:
        service_name: имя сервиса для проверки
    
    Returns:
        bool: True если сервис разрешен, False если запрещен
    """
    # Если задан белый список, проверяем его первым
    if SERVICE_WHITELIST:
        if service_name not in SERVICE_WHITELIST:
            return False
    
    # Если задан черный список, проверяем его
    if SERVICE_BLACKLIST:
        if service_name in SERVICE_BLACKLIST:
            return False
    
    # Если ни один список не задан или сервис прошел все проверки
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
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('status', service_name)
    
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
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('start', service_name)
    
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
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('stop', service_name)
    
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
    
    if not is_service_allowed(service_name):
        return jsonify({'error': 'Service is not allowed (whitelist/blacklist restriction)'}), 403
    
    success, output, error = execute_systemctl_command('restart', service_name)
    
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

