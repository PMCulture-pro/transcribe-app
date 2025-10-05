# 📦 Варианты распространения Transcribe App

## ✅ Создан установщик `install.sh`

Установщик автоматически:
- Скачивает и устанавливает все зависимости
- Настраивает Quick Action в контекстном меню
- Показывает прогресс и информацию о размере загрузки

---

## 🌐 Варианты распространения (от простого к сложному)

### 1. **GitHub Releases** ⭐ РЕКОМЕНДУЕТСЯ
**Лучший вариант для начала**

#### Что нужно:
```bash
# Создать репозиторий на GitHub
# Загрузить файлы:
- install.sh
- README.md (инструкция на русском)
- LICENSE (например, MIT)
```

#### Структура релиза:
```
Release v1.0.0
├── transcribe-installer.sh (переименованный install.sh)
├── README.md
└── checksums.txt (для проверки целостности)
```

#### Как пользователь установит:
```bash
# Вариант 1: Через терминал
curl -fsSL https://raw.githubusercontent.com/USER/transcribe-app/main/install.sh | bash

# Вариант 2: Скачать и запустить
# 1. Перейти на https://github.com/USER/transcribe-app/releases
# 2. Скачать transcribe-installer.sh
# 3. Открыть Терминал
# 4. Запустить: bash ~/Downloads/transcribe-installer.sh
```

**✅ Плюсы:**
- Бесплатно
- Автоматические обновления (можно добавить)
- Простая установка одной командой
- Статистика скачиваний
- Issue tracker для поддержки

**❌ Минусы:**
- Пользователь должен открыть терминал
- Нужен аккаунт GitHub (для разработчика)

**Пример README для пользователей:**
```markdown
# 🎙️ Transcribe App

Локальная транскрибация аудио и видео на macOS с Apple Silicon

## Быстрая установка

bash <(curl -fsSL https://your-url/install.sh)

## Или скачать и запустить
1. [Скачать установщик](https://github.com/.../releases/latest)
2. Открыть Терминал
3. Запустить: `bash ~/Downloads/transcribe-installer.sh`
```

---

### 2. **DMG образ с установщиком**
**Самый "mac-like" вариант**

#### Структура DMG:
```
TranscribeInstaller.dmg (~10 MB)
├── Transcribe Installer.app (двойной клик для установки)
├── README.txt (инструкция)
└── .background (красивый фон с инструкцией)
```

#### Как создать DMG:
```bash
# Создать папку для DMG
mkdir -p dmg-build/TranscribeInstaller
cd dmg-build/TranscribeInstaller

# Создать Automator приложение (или обернуть install.sh в .app)
# ... (см. следующий шаг)

# Создать DMG
hdiutil create -volname "Transcribe Installer" \
  -srcfolder TranscribeInstaller \
  -ov -format UDZO \
  TranscribeInstaller.dmg
```

#### Как обернуть install.sh в .app:
```bash
# Используем Platypus или вручную:
mkdir -p "Transcribe Installer.app/Contents/MacOS"
mkdir -p "Transcribe Installer.app/Contents/Resources"

# Копируем скрипт
cp install.sh "Transcribe Installer.app/Contents/MacOS/install"
chmod +x "Transcribe Installer.app/Contents/MacOS/install"

# Создаем Info.plist
cat > "Transcribe Installer.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>install</string>
    <key>CFBundleName</key>
    <string>Transcribe Installer</string>
    <key>CFBundleIdentifier</key>
    <string>com.transcribe.installer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF
```

**Где распространять DMG:**
- GitHub Releases
- Собственный сайт
- Google Drive / Dropbox (публичная ссылка)

**✅ Плюсы:**
- Привычно для Mac пользователей
- Двойной клик - и установка началась
- Можно добавить красивый фон
- Не нужен терминал

**❌ Минусы:**
- Нужно подписать приложение (или пользователь увидит предупреждение)
- Чуть сложнее создать

---

### 3. **Homebrew Formula** 
**Для продвинутых пользователей**

#### Создать формулу:
```ruby
# transcribe.rb
class Transcribe < Formula
  desc "Локальная транскрибация аудио/видео с Whisper"
  homepage "https://github.com/USER/transcribe-app"
  url "https://github.com/USER/transcribe-app/archive/v1.0.0.tar.gz"
  sha256 "..."

  depends_on "whisper-cpp"
  depends_on "ffmpeg"

  def install
    bin.install "transcribe.sh"
    (var/"transcribe/models").mkpath
    
    # Скачать модель при установке
    system "curl", "-L", "-o", 
      "#{var}/transcribe/models/ggml-large-v3.bin",
      "https://huggingface.co/..."
  end
end
```

#### Установка пользователем:
```bash
brew tap USER/transcribe
brew install transcribe
```

**✅ Плюсы:**
- Интеграция с Homebrew
- Автообновления через `brew upgrade`
- Знакомо для разработчиков

**❌ Минусы:**
- Только для пользователей Homebrew
- Нужно поддерживать формулу

---

### 4. **Готовое .app приложение (GUI)**
**Профессиональный вариант**

Создать полноценное macOS приложение с GUI:
- Окно выбора файлов
- Прогресс-бар
- Настройки
- Автообновления (через Sparkle)

**Инструменты:**
- **Swift/SwiftUI** - нативное приложение
- **Platypus** - обернуть скрипт в GUI
- **Tauri** - веб-технологии + Rust backend

**Распространение:**
- Подписанный DMG
- Mac App Store (требует $99/год)
- Собственный сайт

**✅ Плюсы:**
- Максимально удобно
- Профессиональный вид
- Автообновления

**❌ Минусы:**
- Нужна подпись разработчика ($99/год)
- Больше работы по разработке

---

### 5. **Веб-сайт с landing page**
**Для широкой аудитории**

Создать простой сайт:
```
https://transcribe-app.com
├── index.html (описание, скриншоты)
├── download.html (кнопка скачать)
└── install.sh или DMG
```

Можно хостить бесплатно:
- GitHub Pages
- Netlify
- Vercel

**✅ Плюсы:**
- Профессионально выглядит
- SEO оптимизация
- Инструкции и FAQ

**❌ Минусы:**
- Нужно поддерживать сайт

---

## 🎯 Рекомендации по выбору

### Для начала (MVP):
```
1. GitHub Releases + install.sh
2. README с инструкцией
3. Одна команда установки
```

**Почему:**
- Быстро запустить
- Бесплатно
- Легко обновлять
- Статистика скачиваний

### Через месяц (если есть пользователи):
```
1. DMG образ с красивым установщиком
2. Простой сайт на GitHub Pages
3. Подписать приложение (если есть $99)
```

### В перспективе:
```
1. Полноценное GUI приложение
2. Mac App Store (если много пользователей)
3. Homebrew Formula
```

---

## 📊 Сравнительная таблица

| Метод | Простота создания | Удобство для пользователя | Стоимость | Обновления |
|-------|-------------------|---------------------------|-----------|------------|
| **GitHub + install.sh** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | 💰 Бесплатно | ✅ Легко |
| **DMG образ** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 💰 Бесплатно | ✅ Легко |
| **Homebrew** | ⭐⭐⭐ | ⭐⭐⭐⭐ | 💰 Бесплатно | ✅ Авто |
| **Подписанный .app** | ⭐⭐ | ⭐⭐⭐⭐⭐ | 💰 $99/год | ✅ Авто |
| **Mac App Store** | ⭐ | ⭐⭐⭐⭐⭐ | 💰 $99/год + 30% | ✅ Авто |

---

## 🚀 Быстрый старт: GitHub Releases

### Шаг 1: Создать репозиторий
```bash
cd /Users/dmsmirnov/projects/ai_whisper
git init
git add install.sh transcribe.sh README.md
git commit -m "Initial commit"
git remote add origin https://github.com/USER/transcribe-app.git
git push -u origin main
```

### Шаг 2: Создать релиз
1. Перейти на GitHub → Releases → Create a new release
2. Tag: `v1.0.0`
3. Title: `Transcribe App v1.0.0`
4. Description: 
   ```
   ## Установка
   
   bash <(curl -fsSL https://raw.githubusercontent.com/USER/transcribe-app/main/install.sh)
   
   ## Что нового
   - Первый релиз
   - Поддержка русского языка
   - Интеграция в Finder
   ```
5. Прикрепить `install.sh`
6. Опубликовать

### Шаг 3: Поделиться
```
Ссылка для установки:
https://github.com/USER/transcribe-app

Установка одной командой:
bash <(curl -fsSL https://raw.githubusercontent.com/USER/transcribe-app/main/install.sh)
```

---

## 📝 Важные моменты

### Безопасность
- Пользователи будут видеть предупреждение macOS о неподписанном приложении
- Решение: подписать приложение (нужен Apple Developer ID, $99/год)
- Обходной путь: в инструкции указать "Системные настройки → Безопасность → Разрешить"

### Обновления
- В `install.sh` можно добавить проверку версии
- При запуске проверять GitHub API на новую версию
- Уведомлять пользователя об обновлении

### Поддержка
- GitHub Issues для вопросов и багов
- Wiki для FAQ
- Discussions для общих вопросов

---

## 💡 Следующие шаги

1. **Сейчас**: Протестировать `install.sh` на чистой системе
2. **Завтра**: Создать GitHub репозиторий и первый релиз
3. **Через неделю**: Добавить красивый README с GIF-демонстрацией
4. **Через месяц**: Создать DMG образ, если будут пользователи

---

Готов помочь с любым из этих вариантов! 🚀

