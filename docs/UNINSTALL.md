# Удаление Transcribe App

## Быстрое удаление

### Способ 1: Автоматический (рекомендуется)

После установки в системе доступен скрипт удаления:

```bash
bash "$HOME/Library/Application Support/Transcribe/bin/uninstall.sh"
```

**Что делает скрипт:**
- Показывает что будет удалено и сколько места освободится
- Запрашивает подтверждение
- Удаляет Transcribe App и AI модель (~3 GB)
- Удаляет Quick Action из контекстного меню
- Опционально удаляет зависимости (whisper-cpp, ffmpeg)
- Очищает кэш Homebrew (если нужно)

---

### Способ 2: Ручной

Если скрипт не работает или вы хотите удалить вручную:

#### 1. Удалить основное приложение
```bash
rm -rf "$HOME/Library/Application Support/Transcribe"
```
**Освобождает:** ~3.1 GB (приложение + модель)

#### 2. Удалить Quick Action
```bash
rm -rf "$HOME/Library/Services/Транскрибировать.workflow"
```

Перезапустить Finder:
```bash
killall Finder
```

#### 3. Удалить зависимости (опционально)

**Внимание:** Эти инструменты могут использоваться другими программами!

```bash
# Удалить whisper-cpp
brew uninstall whisper-cpp

# Удалить ffmpeg (если он не нужен)
brew uninstall ffmpeg

# Очистить кэш Homebrew
brew cleanup -s
```

#### 4. Удалить Homebrew (только если больше не нужен)

**ВНИМАНИЕ:** Homebrew используется многими программами на Mac!

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
```

---

## Что НЕ удаляется

**Ваши транскрибированные файлы** - они остаются на месте  
**Homebrew** - остается установленным (может использоваться другими программами)  
**Исходные аудио/видео файлы** - не затрагиваются

---

## Детальный обзор компонентов

### Что и где установлено

| Компонент | Путь | Размер | Можно удалить отдельно? |
|-----------|------|--------|-------------------------|
| **Transcribe App** | `~/Library/Application Support/Transcribe/` | ~10 MB | Да |
| **AI Модель** | `~/Library/Application Support/Transcribe/models/` | ~3.0 GB | Да (но приложение не будет работать) |
| **Quick Action** | `~/Library/Services/Транскрибировать.workflow` | <1 MB | Да |
| **whisper-cpp** | `/opt/homebrew/Cellar/whisper-cpp/` | ~5 MB | Да (через Homebrew) |
| **ffmpeg** | `/opt/homebrew/bin/ffmpeg` | ~95 MB | Может использоваться другими программами |
| **Homebrew** | `/opt/homebrew/` | ~100 MB + кэш | Используется многими программами |

---

## Частичное удаление

### Удалить только AI модель (освободить 3 GB)
```bash
rm -f "$HOME/Library/Application Support/Transcribe/models/ggml-large-v3.bin"
```
**Эффект:** Приложение перестанет работать, но можно переустановить модель через `install.sh`

### Удалить только Quick Action
```bash
rm -rf "$HOME/Library/Services/Транскрибировать.workflow"
killall Finder
```
**Эффект:** Пропадет пункт из контекстного меню, но скрипт транскрибации останется доступным

### Очистить кэш Homebrew
```bash
brew cleanup -s
```
**Эффект:** Освободит несколько гигабайт места, но не удалит приложение

---

## Проверка полного удаления

После удаления проверьте:

```bash
# Проверить основное приложение
ls "$HOME/Library/Application Support/Transcribe" 2>/dev/null && echo "Еще установлено" || echo "Удалено"

# Проверить Quick Action
ls "$HOME/Library/Services/Транскрибировать.workflow" 2>/dev/null && echo "Еще установлен" || echo "Удален"

# Проверить whisper-cpp
brew list whisper-cpp &> /dev/null && echo "Еще установлен" || echo "Удален"

# Проверить ffmpeg
brew list ffmpeg &> /dev/null && echo "Еще установлен" || echo "Удален"
```

---

## Переустановка

Если хотите переустановить после удаления:

```bash
# Скачать и запустить установщик
bash <(curl -fsSL https://your-url/install.sh)

# Или если у вас есть локальная копия
bash ~/Downloads/install.sh
```

---

## Проблемы при удалении

### "Permission denied"
```bash
# Добавить sudo (потребуется пароль администратора)
sudo rm -rf "$HOME/Library/Application Support/Transcribe"
```

### Quick Action не пропадает из меню
```bash
# Очистить кэш служб
/System/Library/CoreServices/pbs -flush
killall Finder

# Перезагрузить компьютер (если не помогло)
```

### Homebrew ругается при удалении пакетов
```bash
# Принудительное удаление
brew uninstall --force whisper-cpp
brew uninstall --force ffmpeg
```

---

## Поддержка

Если возникли проблемы с удалением:
1. Откройте Issue на GitHub
2. Запустите автоматический скрипт удаления (он безопаснее)
3. Приложите вывод команд для диагностики

---

**Совет:** Перед удалением убедитесь, что у вас есть все нужные транскрибации - они не удаляются автоматически!

