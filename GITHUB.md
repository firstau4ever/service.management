# Инструкция по загрузке проекта на GitHub

## Шаг 1: Создание репозитория на GitHub

1. Войдите в свой аккаунт GitHub: https://github.com
2. Нажмите кнопку **"New"** или **"+"** в правом верхнем углу → **"New repository"**
3. Заполните форму:
   - **Repository name:** `service-management` (или другое имя)
   - **Description:** `Service Management API для управления systemd сервисами через HTTP API`
   - **Visibility:** Выберите Public или Private
   - **НЕ добавляйте** README, .gitignore или лицензию (они уже есть в проекте)
4. Нажмите **"Create repository"**

## Шаг 2: Подключение локального репозитория к GitHub

После создания репозитория GitHub покажет инструкции. Выполните команды:

```bash
cd /home/user/service.management

# Добавьте удаленный репозиторий (замените USERNAME на ваш GitHub username)
git remote add origin https://github.com/USERNAME/service-management.git

# Или если используете SSH:
# git remote add origin git@github.com:USERNAME/service-management.git

# Проверьте подключение
git remote -v
```

## Шаг 3: Настройка Git (если еще не настроено)

```bash
# Установите ваше имя и email для Git
git config --global user.name "Ваше Имя"
git config --global user.email "your.email@example.com"
```

## Шаг 4: Загрузка проекта на GitHub

```bash
# Переименуйте основную ветку в main (если нужно)
git branch -M main

# Загрузите проект на GitHub
git push -u origin main
```

Если GitHub запросит авторизацию:
- Для HTTPS: используйте Personal Access Token (см. ниже)
- Для SSH: убедитесь что SSH ключ добавлен в GitHub

## Создание Personal Access Token (для HTTPS)

Если используете HTTPS и GitHub запрашивает пароль:

1. Перейдите в GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Нажмите **"Generate new token"**
3. Выберите права: `repo` (полный доступ к репозиториям)
4. Скопируйте токен
5. Используйте токен вместо пароля при `git push`

## Проверка загрузки

После успешной загрузки:
1. Обновите страницу репозитория на GitHub
2. Убедитесь что все файлы загружены
3. Проверьте что README.md отображается корректно

## Дальнейшая работа с репозиторием

### Добавление изменений:

```bash
git add .
git commit -m "Описание изменений"
git push
```

### Клонирование на другой машине:

```bash
git clone https://github.com/USERNAME/service-management.git
cd service-management
```

### Обновление с GitHub:

```bash
git pull
```

## Полезные команды Git

```bash
# Проверить статус
git status

# Посмотреть историю коммитов
git log --oneline

# Отменить изменения в файле
git checkout -- filename

# Посмотреть различия
git diff
```

## Troubleshooting

### Если возникла ошибка при push:

1. **"Permission denied"** - проверьте правильность username/repository name
2. **"Authentication failed"** - используйте Personal Access Token вместо пароля
3. **"Repository not found"** - убедитесь что репозиторий создан и имя правильное

### Если нужно изменить remote URL:

```bash
git remote set-url origin https://github.com/USERNAME/service-management.git
```

