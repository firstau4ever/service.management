#!/bin/bash

# Скрипт для загрузки проекта на GitHub
# Использование: ./PUSH_TO_GITHUB.sh YOUR_GITHUB_USERNAME

set -e

GITHUB_USERNAME=$1

if [ -z "$GITHUB_USERNAME" ]; then
    echo "Использование: ./PUSH_TO_GITHUB.sh YOUR_GITHUB_USERNAME"
    echo ""
    echo "Пример:"
    echo "  ./PUSH_TO_GITHUB.sh myusername"
    exit 1
fi

echo "=== Загрузка проекта на GitHub ==="
echo ""
echo "GitHub username: $GITHUB_USERNAME"
echo ""

# Проверка что git настроен
if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
    echo "⚠ Git не настроен. Настройте перед продолжением:"
    echo "  git config --global user.name \"Ваше Имя\""
    echo "  git config --global user.email \"your.email@example.com\""
    echo ""
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Проверка что репозиторий инициализирован
if [ ! -d ".git" ]; then
    echo "Инициализация Git репозитория..."
    git init
    git add .
    git commit -m "Initial commit: Service Management API"
fi

# Проверка существования remote
if git remote get-url origin &>/dev/null; then
    echo "Remote 'origin' уже настроен:"
    git remote get-url origin
    read -p "Изменить на новый? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git remote set-url origin "https://github.com/$GITHUB_USERNAME/service-management.git"
    fi
else
    echo "Добавление remote 'origin'..."
    git remote add origin "https://github.com/$GITHUB_USERNAME/service-management.git"
fi

# Переименование ветки в main
git branch -M main 2>/dev/null || true

echo ""
echo "=== Готово к загрузке ==="
echo ""
echo "Убедитесь что репозиторий создан на GitHub:"
echo "  https://github.com/$GITHUB_USERNAME/service-management"
echo ""
read -p "Загрузить проект на GitHub? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Загрузка проекта..."
    git push -u origin main
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Проект успешно загружен на GitHub!"
        echo "   https://github.com/$GITHUB_USERNAME/service-management"
    else
        echo ""
        echo "❌ Ошибка при загрузке. Возможные причины:"
        echo "   1. Репозиторий не создан на GitHub"
        echo "   2. Неправильный username"
        echo "   3. Проблемы с авторизацией (используйте Personal Access Token)"
        echo ""
        echo "См. GITHUB.md для подробных инструкций"
    fi
else
    echo ""
    echo "Загрузка отменена. Выполните вручную:"
    echo "  git push -u origin main"
fi

