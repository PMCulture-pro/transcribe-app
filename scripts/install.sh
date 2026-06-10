#!/bin/bash

# Transcribe App Installer
# Автоматическая установка whisper-cpp и зависимостей для транскрибации

set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Вспомогательные функции прогресса
SPINNER_CHARS='|/-\\'
HEARTBEAT_PID=""
LOG_FOLLOW_PID=""

stop_background_progress() {
    if [ -n "$HEARTBEAT_PID" ] && kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
        kill "$HEARTBEAT_PID" 2>/dev/null || true
        wait "$HEARTBEAT_PID" 2>/dev/null || true
        HEARTBEAT_PID=""
    fi
    if [ -n "$LOG_FOLLOW_PID" ] && kill -0 "$LOG_FOLLOW_PID" 2>/dev/null; then
        kill "$LOG_FOLLOW_PID" 2>/dev/null || true
        wait "$LOG_FOLLOW_PID" 2>/dev/null || true
        LOG_FOLLOW_PID=""
    fi
}

trap stop_background_progress EXIT INT TERM

start_log_follow() {
    # Показываем только релевантные строки про CLT/softwareupdate
    # Без блокировки — будет убито по завершению
    if command -v sudo >/dev/null 2>&1; then
        sudo -n true 2>/dev/null || true
        sudo tail -n0 -F /var/log/install.log 2>/dev/null | \
        grep --line-buffered -E "Command Line Tools|softwareupdate|CLTools|Installing|Downloaded|Verifying" &
        LOG_FOLLOW_PID=$!
    else
        tail -n0 -F /var/log/install.log 2>/dev/null | \
        grep --line-buffered -E "Command Line Tools|softwareupdate|CLTools|Installing|Downloaded|Verifying" &
        LOG_FOLLOW_PID=$!
    fi
}

start_heartbeat() {
    local title="$1"
    (
        local i=0
        local start_ts
        start_ts=$(date +%s)
        while true; do
            i=$(((i+1)%4))
            local now
            now=$(date +%s)
            local elapsed=$((now-start_ts))
            printf "\r%s %s  ⏳ %02d:%02d:%02d" "$title" "${SPINNER_CHARS:$i:1}" $((elapsed/3600)) $(((elapsed/60)%60)) $((elapsed%60))
            sleep 1
        done
    ) &
    HEARTBEAT_PID=$!
}

# Директории установки
INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"
SERVICES_DIR="$HOME/Library/Services"

# URLs для загрузки
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
# Канонический transcribe.sh — единый источник правды. Установщик копирует
# соседний файл при запуске из клона репозитория, иначе докачивает по этому URL.
TRANSCRIBE_RAW_URL="https://raw.githubusercontent.com/277zdwvw9f-pixel/transcribe-app/main/scripts/transcribe.sh"
MODEL_SIZE="3.0 GB"
FFMPEG_SIZE="95 MB"
TOTAL_SIZE="3.1 GB"

# SHA256 контрольная сумма модели для проверки целостности
# Источник: https://huggingface.co/ggerganov/whisper.cpp
EXPECTED_MODEL_SHA256="64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                   ║${NC}"
echo -e "${BLUE}║        🎙️  Transcribe App Installer 🎙️           ║${NC}"
echo -e "${BLUE}║                                                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Этот установщик скачает и настроит все необходимое для${NC}"
echo -e "${YELLOW}локальной транскрибации аудио и видео файлов.${NC}"
echo ""

# Проверка компонентов
echo -e "${BLUE}📦 Что будет установлено:${NC}"
echo ""
echo "  ✓ Whisper Model (large-v3) - AI модель для транскрибации"
echo "    Размер: $MODEL_SIZE"
echo ""
echo "  ✓ Whisper-cpp - Оптимизированный транскрибатор для Apple Silicon"
echo "    Размер: ~5 MB"
echo ""
echo "  ✓ FFmpeg - Инструмент для работы с аудио/видео"
echo "    Размер: $FFMPEG_SIZE"
echo ""
echo "  ✓ Quick Action - Интеграция в контекстное меню Finder"
echo "    Размер: <1 MB"
echo ""
echo -e "${YELLOW}╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${NC}"
echo -e "${GREEN}Общий объем загрузки: ~$TOTAL_SIZE${NC}"
echo -e "${GREEN}Время установки: ~10-15 минут (зависит от скорости интернета)${NC}"
echo -e "${YELLOW}╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${NC}"
echo ""
echo -e "${BLUE}Установка в:${NC} $INSTALL_DIR"
echo ""

# Запрос подтверждения
read -p "Продолжить установку? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[YyДд]$ ]]
then
    echo -e "${RED}Установка отменена.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}▶ Начинаю установку...${NC}"
echo ""

# Создание директорий
echo -e "${BLUE}[1/5]${NC} Создание директорий..."
mkdir -p "$BIN_DIR"
mkdir -p "$MODEL_DIR"
mkdir -p "$SERVICES_DIR"
echo -e "${GREEN}✓ Директории созданы${NC}"
echo ""

# Проверка и установка Homebrew
echo -e "${BLUE}[2/5]${NC} Проверка Homebrew..."
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}⚠ Homebrew не найден.${NC}"
    echo ""
    echo "Для установки Transcribe App требуется Homebrew."
    echo ""
    echo "Вариант 1 (Рекомендуется): Установите Homebrew вручную"
    echo "  1. Откройте: https://brew.sh"
    echo "  2. Следуйте официальным инструкциям"
    echo "  3. Запустите этот скрипт снова"
    echo ""
    echo "Вариант 2: Автоматическая установка (требует подтверждения)"
    read -p "Установить Homebrew автоматически? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[YyДд]$ ]]; then
        echo "Устанавливаю Homebrew..."
        echo ""
        
        # Скачиваем скрипт установки во временный файл
        BREW_INSTALL_SCRIPT="/tmp/brew_install_$$.sh"
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$BREW_INSTALL_SCRIPT"
        
        # Показываем первые строки скрипта для проверки
        echo "Первые 10 строк скрипта установки Homebrew:"
        echo "---"
        head -10 "$BREW_INSTALL_SCRIPT"
        echo "---"
        echo ""
        read -p "Продолжить установку? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[YyДд]$ ]]; then
            echo "Запускаю установку Homebrew. Это может установить Xcode Command Line Tools."
            echo "Показываю живой лог softwareupdate и индикатор времени..."
            start_log_follow
            start_heartbeat "  Установка Homebrew/CLT идёт"

            # Запускаем скрипт установки в фоне, чтобы параллельно показывать прогресс
            (
                /bin/bash "$BREW_INSTALL_SCRIPT"
            ) &
            BREW_BOOTSTRAP_PID=$!
            wait "$BREW_BOOTSTRAP_PID"

            # Очищаем прогресс-индикаторы
            stop_background_progress
            echo -e "\r${GREEN}✓ Установка Homebrew завершена${NC}                               "
            rm -f "$BREW_INSTALL_SCRIPT"
            
            # Добавляем Homebrew в PATH для Apple Silicon
            if [[ $(uname -m) == 'arm64' ]]; then
                # Проверяем что строка еще не добавлена
                if ! grep -q "/opt/homebrew/bin/brew shellenv" ~/.zprofile 2>/dev/null; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                fi
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
            echo -e "${GREEN}✓ Homebrew установлен${NC}"
        else
            echo -e "${RED}Установка отменена. Установите Homebrew вручную и запустите скрипт снова.${NC}"
            rm -f "$BREW_INSTALL_SCRIPT"
            exit 1
        fi
    else
        echo -e "${RED}Установка отменена. Установите Homebrew вручную и запустите скрипт снова.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Homebrew уже установлен${NC}"
fi
echo ""

# Установка whisper-cpp и ffmpeg через Homebrew
echo -e "${BLUE}[3/5]${NC} Установка whisper-cpp и ffmpeg..."
if ! brew list whisper-cpp &> /dev/null; then
    echo "  Устанавливаю whisper-cpp (verbose)..."
    brew install -v whisper-cpp
    echo -e "${GREEN}✓ whisper-cpp установлен${NC}"
else
    echo -e "${GREEN}✓ whisper-cpp уже установлен${NC}"
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "  Устанавливаю ffmpeg (verbose)..."
    brew install -v ffmpeg
    echo -e "${GREEN}✓ ffmpeg установлен${NC}"
else
    echo -e "${GREEN}✓ ffmpeg уже установлен${NC}"
fi
echo ""

# Скачивание модели
echo -e "${BLUE}[4/5]${NC} Загрузка AI модели (это займет время)..."
MODEL_PATH="$MODEL_DIR/ggml-large-v3.bin"

# 0 = SHA совпадает · 1 = не совпадает · 2 = нечем проверить
verify_model_sha() {
    local actual=""
    if command -v shasum &> /dev/null; then
        actual=$(shasum -a 256 "$MODEL_PATH" | cut -d' ' -f1)
    elif command -v sha256sum &> /dev/null; then
        actual=$(sha256sum "$MODEL_PATH" | cut -d' ' -f1)
    else
        return 2
    fi
    [ "$actual" = "$EXPECTED_MODEL_SHA256" ]
}

# Готовая модель определяется по контрольной сумме, а не по факту существования
# файла: иначе оборванная закачка считалась бы «уже скачанной». См. BACKLOG INS-1.
if [ -f "$MODEL_PATH" ] && verify_model_sha; then
    echo -e "${GREEN}✓ Модель уже скачана и проверена${NC}"
else
    if [ -f "$MODEL_PATH" ]; then
        echo "  Найден неполный файл модели — продолжаю докачку..."
    else
        echo "  Скачиваю модель ($MODEL_SIZE)..."
    fi
    echo "  URL: $WHISPER_MODEL_URL"
    echo ""

    # Докачка (resume): обрыв сети не заставит качать 3 ГБ заново. INS-1.
    if command -v wget &> /dev/null; then
        wget -c --progress=bar:force -O "$MODEL_PATH" "$WHISPER_MODEL_URL" 2>&1 | \
            grep --line-buffered -oP '\d+(?=%)' | \
            while read -r percent; do
                echo -ne "  Прогресс: $percent%\r"
            done
        DL_STATUS=${PIPESTATUS[0]}
        echo ""
    else
        curl -fL -C - -# -o "$MODEL_PATH" "$WHISPER_MODEL_URL"
        DL_STATUS=$?
    fi

    # Пайп wget|grep|while скрывает код возврата от set -e — проверяем явно. INS-2.
    if [ "$DL_STATUS" -ne 0 ]; then
        echo -e "${RED}✗ Ошибка загрузки модели (код $DL_STATUS)${NC}"
        echo -e "${RED}  Запустите установщик ещё раз — закачка продолжится с места обрыва.${NC}"
        exit 1
    fi
    echo ""

    # Проверка целостности модели
    echo "  Проверка целостности модели..."
    if verify_model_sha; then
        echo -e "${GREEN}✓ Контрольная сумма совпадает (модель подлинная)${NC}"
    else
        rc=$?
        if [ "$rc" = "2" ]; then
            echo -e "${YELLOW}⚠ shasum не найден, пропускаю проверку целостности${NC}"
        else
            echo -e "${RED}✗ ОШИБКА: контрольная сумма не совпадает!${NC}"
            echo -e "${RED}  Ожидалось: $EXPECTED_MODEL_SHA256${NC}"
            echo -e "${RED}  Файл повреждён или подменён. Удаляю — запустите установщик снова.${NC}"
            rm -f "$MODEL_PATH"
            exit 1
        fi
    fi
fi
echo ""

# Создание скрипта транскрибации
echo -e "${BLUE}[5/5]${NC} Настройка транскрибатора..."

# scripts/transcribe.sh — единый источник правды (раньше дублировался здесь
# heredoc'ом и молча расходился с репозиторием). При запуске установщика из
# клона копируем соседний файл; иначе докачиваем из репозитория. См. BACKLOG MNT-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
LOCAL_TRANSCRIBE="$SCRIPT_DIR/transcribe.sh"

if [ -n "$SCRIPT_DIR" ] && [ -f "$LOCAL_TRANSCRIBE" ]; then
    cp "$LOCAL_TRANSCRIBE" "$BIN_DIR/transcribe.sh"
    echo -e "${GREEN}✓ Скрипт транскрибации установлен (локальная копия)${NC}"
elif curl -fsSL "$TRANSCRIBE_RAW_URL" -o "$BIN_DIR/transcribe.sh"; then
    echo -e "${GREEN}✓ Скрипт транскрибации загружен${NC}"
else
    echo -e "${RED}✗ Не удалось получить transcribe.sh${NC}"
    echo -e "${RED}  Нет локальной копии рядом с установщиком и не удалось скачать:${NC}"
    echo -e "${RED}  $TRANSCRIBE_RAW_URL${NC}"
    exit 1
fi

chmod +x "$BIN_DIR/transcribe.sh"
echo -e "${GREEN}✓ Скрипт транскрибации готов${NC}"

# Создание скрипта удаления
echo "  Создание скрипта удаления..."
cat > "$BIN_DIR/uninstall.sh" << 'EOFUNINSTALL'
#!/bin/bash

# Transcribe App Uninstaller
# Полное удаление всех компонентов и зависимостей

set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Директории для удаления
INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW_PATH="$SERVICES_DIR/Транскрибировать.workflow"

echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║                                                   ║${NC}"
echo -e "${RED}║        🗑️  Transcribe App Uninstaller 🗑️          ║${NC}"
echo -e "${RED}║                                                   ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Этот скрипт полностью удалит Transcribe App${NC}"
echo -e "${YELLOW}и все связанные компоненты.${NC}"
echo ""

# Проверяем что будет удалено
echo -e "${BLUE}📋 Что будет удалено:${NC}"
echo ""

if [ -d "$INSTALL_DIR" ]; then
    SIZE=$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1)
    echo "  ✓ Transcribe App и AI модель"
    echo "    Путь: $INSTALL_DIR"
    echo "    Размер: $SIZE"
    echo ""
fi

if [ -d "$WORKFLOW_PATH" ]; then
    echo "  ✓ Quick Action (контекстное меню)"
    echo "    Путь: $WORKFLOW_PATH"
    echo ""
fi

# Проверяем Homebrew пакеты
HOMEBREW_PACKAGES=""
if command -v brew &> /dev/null; then
    if brew list whisper-cpp &> /dev/null 2>&1; then
        HOMEBREW_PACKAGES="$HOMEBREW_PACKAGES whisper-cpp"
    fi
    if brew list ffmpeg &> /dev/null 2>&1; then
        HOMEBREW_PACKAGES="$HOMEBREW_PACKAGES ffmpeg"
    fi
fi

if [ -n "$HOMEBREW_PACKAGES" ]; then
    echo -e "${YELLOW}⚠️  Homebrew пакеты (опционально):${NC}"
    for pkg in $HOMEBREW_PACKAGES; do
        echo "    • $pkg"
    done
    echo ""
    echo -e "${YELLOW}    Эти пакеты могут использоваться другими программами.${NC}"
    echo -e "${YELLOW}    Вы сможете выбрать, удалять их или нет.${NC}"
    echo ""
fi

# Проверяем есть ли что удалять
if [ ! -d "$INSTALL_DIR" ] && [ ! -d "$WORKFLOW_PATH" ]; then
    echo -e "${GREEN}✓ Transcribe App не установлен или уже удален.${NC}"
    exit 0
fi

echo -e "${YELLOW}╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${NC}"

# Запрос подтверждения
read -p "Удалить Transcribe App? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[YyДд]$ ]]; then
    echo -e "${GREEN}Удаление отменено.${NC}"
    exit 0
fi

echo ""
echo -e "${RED}▶ Начинаю удаление...${NC}"
echo ""

# Удаление Quick Action
echo -e "${BLUE}[1/3]${NC} Удаление Quick Action из контекстного меню..."
if [ -d "$WORKFLOW_PATH" ]; then
    rm -rf "$WORKFLOW_PATH"
    echo -e "${GREEN}✓ Quick Action удален${NC}"
    
    # Перезагружаем Services для применения изменений
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
    killall Finder 2>/dev/null || true
else
    echo -e "${YELLOW}⚠ Quick Action не найден${NC}"
fi
echo ""

# Удаление основного приложения
echo -e "${BLUE}[2/3]${NC} Удаление Transcribe App и AI модели..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo -e "${GREEN}✓ Transcribe App удален${NC}"
else
    echo -e "${YELLOW}⚠ Transcribe App не найден${NC}"
fi
echo ""

# Удаление Homebrew пакетов (опционально)
echo -e "${BLUE}[3/3]${NC} Удаление зависимостей..."

if [ -n "$HOMEBREW_PACKAGES" ]; then
    echo ""
    echo -e "${YELLOW}Найдены Homebrew пакеты:${NC} $HOMEBREW_PACKAGES"
    echo -e "${YELLOW}⚠️  Внимание: эти пакеты могут использоваться другими программами!${NC}"
    echo ""
    
    read -p "Удалить whisper-cpp и ffmpeg из Homebrew? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[YyДд]$ ]]; then
        for pkg in $HOMEBREW_PACKAGES; do
            echo "  Удаляю $pkg..."
            brew uninstall $pkg 2>/dev/null || true
            echo -e "${GREEN}✓ $pkg удален${NC}"
        done
        
        # Опционально: очистка кэша Homebrew
        echo ""
        read -p "Очистить кэш Homebrew? (освободит дополнительное место) (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[YyДд]$ ]]; then
            brew cleanup -s 2>/dev/null || true
            echo -e "${GREEN}✓ Кэш очищен${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Homebrew пакеты оставлены${NC}"
    fi
else
    echo -e "${GREEN}✓ Нет дополнительных зависимостей для удаления${NC}"
fi

echo ""

# Финальное сообщение
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║              ✅ Удаление завершено! ✅             ║${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Что было удалено:${NC}"
echo ""
echo "  ✓ Transcribe App и AI модель"
echo "  ✓ Quick Action из контекстного меню"
if [ -n "$HOMEBREW_PACKAGES" ]; then
    echo "  ✓ Homebrew пакеты (если выбрано)"
fi
echo ""
echo -e "${YELLOW}💡 Примечание:${NC}"
echo "  • Homebrew остается установленным (может использоваться другими программами)"
echo "  • Ваши транскрибированные файлы НЕ удалены"
echo "  • Для переустановки запустите install.sh снова"
echo ""
echo -e "${GREEN}Спасибо за использование Transcribe App! 👋${NC}"
echo ""
EOFUNINSTALL

chmod +x "$BIN_DIR/uninstall.sh"
echo -e "${GREEN}✓ Скрипт удаления создан${NC}"
echo ""

# Создание Automator Quick Action
echo "  Создание Quick Action для контекстного меню..."

WORKFLOW_PATH="$SERVICES_DIR/Транскрибировать.workflow"

if [ -d "$WORKFLOW_PATH" ]; then
    rm -rf "$WORKFLOW_PATH"
fi

mkdir -p "$WORKFLOW_PATH/Contents"

# Info.plist для workflow
cat > "$WORKFLOW_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Транскрибировать</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSRequiredContext</key>
            <dict>
                <key>NSApplicationIdentifier</key>
                <string>com.apple.finder</string>
            </dict>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.audio</string>
                <string>public.audiovisual-content</string>
                <string>public.mpeg-4</string>
                <string>org.matroska.mkv</string>
                <string>org.webmproject.webm</string>
                <!-- public.data: показывать пункт для всех форматов, что читает ffmpeg
                     (flac/ogg и пр.), не подпадающих под UTI выше. См. BACKLOG BUG-3. -->
                <string>public.data</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# document.wflow для workflow
cat > "$WORKFLOW_PATH/Contents/document.wflow" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.path</string>
                    </array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>for f in "\$@"
do
    "$HOME/Library/Application Support/Transcribe/bin/transcribe.sh" "\$f"
done</string>
                    <key>CheckedForUserDefaultShell</key>
                    <true/>
                    <key>inputMethod</key>
                    <integer>1</integer>
                    <key>shell</key>
                    <string>/bin/bash</string>
                    <key>source</key>
                    <string></string>
                </dict>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo -e "${GREEN}✓ Quick Action установлен${NC}"
echo ""

# Финальное сообщение
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║              ✅ Установка завершена! ✅            ║${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Как использовать:${NC}"
echo ""
echo "  1. Откройте Finder"
echo "  2. Найдите любой видео или аудио файл (.mov, .mp4, .mp3, .wav, etc.)"
echo "  3. Кликните правой кнопкой мыши → Quick Actions → Транскрибировать"
echo "  4. Дождитесь уведомления о завершении"
echo "  5. Текстовый файл появится рядом с исходным файлом"
echo ""
echo -e "${YELLOW}💡 Совет:${NC} Первая транскрибация может занять больше времени"
echo -e "${YELLOW}   из-за инициализации модели.${NC}"
echo ""
echo -e "${BLUE}Установлено в:${NC}"
echo "  • Приложение: $INSTALL_DIR"
echo "  • Quick Action: $SERVICES_DIR/Транскрибировать.workflow"
echo ""
echo -e "${YELLOW}🗑️  Для удаления запустите:${NC}"
echo "  bash \"$BIN_DIR/uninstall.sh\""
echo ""
echo -e "${GREEN}Спасибо за использование Transcribe App! 🎉${NC}"
echo ""

