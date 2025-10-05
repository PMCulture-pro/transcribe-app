# 📦 Инструкция по публикации на GitHub

Пошаговое руководство как опубликовать Transcribe App на GitHub для распространения.

---

## 🎯 Цель

После выполнения этих шагов пользователи смогут установить приложение одной командой:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PMCulture-pro/transcribe-app/main/install.sh)
```

---

## 📋 Шаг 1: Создать репозиторий на GitHub

### 1.1 Перейти на GitHub
Откройте https://github.com и войдите в аккаунт

### 1.2 Создать новый репозиторий
1. Нажмите **"New repository"** (зеленая кнопка)
2. Заполните:
   - **Repository name:** `transcribe-app`
   - **Description:** `🎙️ Локальная транскрибация аудио и видео на macOS с использованием AI`
   - **Public** (чтобы пользователи могли скачать)
   - ✅ **Add a README file** (снять галочку - у нас уже есть)
   - **License:** MIT License
3. Нажмите **"Create repository"**

---

## 📋 Шаг 2: Подготовить локальные файлы

### 2.1 Перейти в папку проекта

```bash
cd /Users/dmsmirnov/projects/ai_whisper
```

### 2.2 Обновить README.md

**Важно!** Замените `PMCulture-pro` на ваш GitHub username во всех файлах:

```bash
# Замените PMCulture-pro на ваш username (например, dmitrysmirnov)
USERNAME="YOUR_GITHUB_USERNAME"

# Автоматически заменить во всех файлах
sed -i '' "s/PMCulture-pro/$USERNAME/g" README.md
sed -i '' "s/PMCulture-pro/$USERNAME/g" README_SHORT.md
sed -i '' "s/PMCulture-pro/$USERNAME/g" install.sh
```

### 2.3 Создать .gitignore

```bash
cat > .gitignore << 'EOF'
# Временные файлы
*.tmp
*.log
.DS_Store

# Аудио/видео файлы (не загружать в репозиторий)
audio/
samples/
text/

# Модели (слишком большие для GitHub)
models/
*.bin

# Кэш
__pycache__/
.cache/
EOF
```

### 2.4 Создать LICENSE (MIT)

```bash
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2025 [Your Name]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

---

## 📋 Шаг 3: Загрузить на GitHub

### 3.1 Инициализировать Git

```bash
cd /Users/dmsmirnov/projects/ai_whisper

# Инициализировать репозиторий
git init

# Добавить файлы
git add install.sh
git add uninstall.sh
git add transcribe.sh
git add README.md
git add README_SHORT.md
git add UNINSTALL.md
git add DISTRIBUTION.md
git add LICENSE
git add .gitignore

# Создать первый коммит
git commit -m "Initial commit: Transcribe App v1.0.0"
```

### 3.2 Подключить к GitHub

**Замените PMCulture-pro на ваш GitHub username:**

```bash
# Добавить remote (замените PMCulture-pro!)
git remote add origin https://github.com/PMCulture-pro/transcribe-app.git

# Переименовать ветку в main (если нужно)
git branch -M main

# Загрузить на GitHub
git push -u origin main
```

**Если появится запрос авторизации:**
- Используйте Personal Access Token вместо пароля
- Создать токен: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token
- Выберите scope: `repo` (полный доступ к репозиториям)

---

## 📋 Шаг 4: Создать Release

### 4.1 Перейти в раздел Releases

1. Откройте ваш репозиторий на GitHub
2. Справа найдите **"Releases"** → нажмите **"Create a new release"**

### 4.2 Заполнить информацию о релизе

**Tag version:** `v1.0.0`

**Release title:** `🎙️ Transcribe App v1.0.0 - Первый релиз`

**Description:**
```markdown
## 🎉 Первый стабильный релиз!

Локальная транскрибация аудио и видео на macOS с использованием AI.

### ✨ Возможности
- 🚀 Быстрая работа на Apple Silicon (M1/M2/M3/M4)
- 🔒 Полностью локально - данные не покидают ваш Mac
- 🎯 Простота - правый клик → "Транскрибировать"
- 🎬 Поддержка видео и аудио форматов
- 🇷🇺 Отличное распознавание русского языка

### 📦 Установка

**Быстрая установка:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PMCulture-pro/transcribe-app/main/install.sh)
```

**Или скачайте файлы ниже:**
- `install.sh` - Установщик
- `uninstall.sh` - Деинсталлятор

### 📖 Документация
- [README.md](https://github.com/PMCulture-pro/transcribe-app/blob/main/README.md) - Полная документация
- [README_SHORT.md](https://github.com/PMCulture-pro/transcribe-app/blob/main/README_SHORT.md) - Быстрый старт
- [UNINSTALL.md](https://github.com/PMCulture-pro/transcribe-app/blob/main/UNINSTALL.md) - Удаление

### 📊 Системные требования
- macOS 11.0+ (Big Sur или новее)
- ~3.5 GB свободного места
- Интернет для установки

### 🎯 Производительность
- M4 Pro: 30 мин видео → 4.5 мин транскрибации (~7x realtime)
- M1 Pro: 30 мин видео → 7.5 мин транскрибации (~4x realtime)

### 🙏 Благодарности
Спасибо OpenAI (Whisper), Georgi Gerganov (whisper.cpp) и FFmpeg Team!

---

**⭐ Если понравилось - поставьте звезду!**
```

### 4.3 Прикрепить файлы

В разделе **"Attach binaries"** прикрепите:
- `install.sh`
- `uninstall.sh`

### 4.4 Опубликовать

1. ✅ Установите галочку **"Set as the latest release"**
2. Нажмите **"Publish release"**

---

## 📋 Шаг 5: Улучшить README репозитория

### 5.1 Добавить badges (значки)

Отредактируйте `README.md`, добавив в начало:

```markdown
# 🎙️ Transcribe App

[![GitHub release](https://img.shields.io/github/v/release/PMCulture-pro/transcribe-app)](https://github.com/PMCulture-pro/transcribe-app/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-11.0+-blue.svg)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Optimized-green.svg)](https://www.apple.com/mac/)

**Локальная транскрибация аудио и видео файлов на macOS с использованием AI**
```

### 5.2 Добавить GIF демонстрацию (опционально)

Если есть скринкаст использования:

1. Запишите короткое видео (QuickTime Player → Новая запись экрана)
2. Конвертируйте в GIF: https://ezgif.com/video-to-gif
3. Загрузите GIF в репозиторий: `demo.gif`
4. В README.md замените `![Демонстрация использования](demo.gif)` на реальный путь

---

## 📋 Шаг 6: Настроить GitHub Pages (опционально)

Создайте простой сайт для проекта:

### 6.1 Включить GitHub Pages

1. Репозиторий → **Settings** → **Pages**
2. Source: **Deploy from a branch**
3. Branch: **main** → folder: **/ (root)**
4. Нажмите **Save**

### 6.2 Создать index.html (простой лендинг)

```bash
cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Transcribe App - Локальная транскрибация на macOS</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
            color: #333;
        }
        h1 { color: #2c3e50; }
        .install-box {
            background: #f5f5f5;
            padding: 20px;
            border-radius: 10px;
            margin: 30px 0;
        }
        code {
            background: #333;
            color: #fff;
            padding: 15px;
            display: block;
            border-radius: 5px;
            overflow-x: auto;
        }
        .button {
            display: inline-block;
            background: #007bff;
            color: white;
            padding: 12px 24px;
            text-decoration: none;
            border-radius: 5px;
            margin: 10px 5px;
        }
        .button:hover { background: #0056b3; }
    </style>
</head>
<body>
    <h1>🎙️ Transcribe App</h1>
    <p>Локальная транскрибация аудио и видео файлов на macOS с использованием AI</p>
    
    <div class="install-box">
        <h2>Быстрая установка</h2>
        <p>Откройте Терминал и выполните:</p>
        <code>bash &lt;(curl -fsSL https://raw.githubusercontent.com/PMCulture-pro/transcribe-app/main/install.sh)</code>
    </div>
    
    <h2>Возможности</h2>
    <ul>
        <li>🚀 Быстрая работа на Apple Silicon</li>
        <li>🔒 Полностью локально</li>
        <li>🎯 Простота использования</li>
        <li>🆓 Бесплатно</li>
    </ul>
    
    <a href="https://github.com/PMCulture-pro/transcribe-app" class="button">GitHub</a>
    <a href="https://github.com/PMCulture-pro/transcribe-app/releases" class="button">Скачать</a>
</body>
</html>
EOF

git add index.html
git commit -m "Add GitHub Pages landing"
git push
```

Сайт будет доступен по адресу: `https://PMCulture-pro.github.io/transcribe-app/`

---

## 📋 Шаг 7: Продвижение

### 7.1 Поделиться в соцсетях

- Reddit: /r/macapps, /r/MacOS
- Twitter/X: с тегами #macOS #AppleSilicon #AI #OpenSource
- Telegram: тематические каналы о macOS
- VK: сообщества о Mac

### 7.2 Пример поста

```
🎙️ Представляю Transcribe App - бесплатную локальную транскрибацию аудио/видео на macOS!

✨ Возможности:
• Работает на Apple Silicon (M1/M2/M3/M4)
• Все локально - данные не покидают ваш Mac
• Правый клик → "Транскрибировать" → готово!
• Поддержка русского языка

30 минут видео → 5 минут транскрибации на M4 Pro 🚀

GitHub: https://github.com/PMCulture-pro/transcribe-app
Лицензия: MIT (открытый исходный код)

#macOS #AppleSilicon #AI #OpenSource
```

---

## 🎯 Итоговая структура репозитория

```
transcribe-app/
├── .gitignore
├── LICENSE
├── README.md              (полная документация)
├── README_SHORT.md        (быстрый старт)
├── DISTRIBUTION.md        (варианты распространения)
├── UNINSTALL.md           (инструкция по удалению)
├── GITHUB_SETUP.md        (эта инструкция)
├── install.sh             (установщик)
├── uninstall.sh           (деинсталлятор)
├── transcribe.sh          (скрипт транскрибации)
├── index.html             (опционально - GitHub Pages)
└── demo.gif               (опционально - демонстрация)
```

---

## ✅ Checklist перед публикацией

- [ ] Заменили `PMCulture-pro` на реальный GitHub username
- [ ] Создали репозиторий на GitHub
- [ ] Загрузили все файлы через git push
- [ ] Создали Release v1.0.0
- [ ] Прикрепили install.sh и uninstall.sh к релизу
- [ ] Протестировали установку с нуля на другом Mac (если возможно)
- [ ] Проверили что ссылка для быстрой установки работает
- [ ] Добавили badges в README
- [ ] Опционально: настроили GitHub Pages
- [ ] Опционально: добавили demo.gif

---

## 🎉 Готово!

Теперь пользователи могут установить ваше приложение одной командой:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/PMCulture-pro/transcribe-app/main/install.sh)
```

---

## 📞 Поддержка пользователей

### Включите GitHub Issues

Репозиторий → **Settings** → **General** → **Features** → ✅ **Issues**

### Создайте Issue Templates

`.github/ISSUE_TEMPLATE/bug_report.md`:
```markdown
---
name: Bug Report
about: Сообщить о проблеме
---

## Описание проблемы
[Опишите что произошло]

## Шаги для воспроизведения
1. ...
2. ...

## Ожидаемое поведение
[Что должно было произойти]

## Система
- macOS версия:
- Процессор (M1/M2/Intel):
- Версия Transcribe App:

## Дополнительная информация
[Логи, скриншоты, etc.]
```

---

**Успехов с публикацией! 🚀**

