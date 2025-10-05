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

# Директории установки
INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"
SERVICES_DIR="$HOME/Library/Services"

# URLs для загрузки
WHISPER_CPP_VERSION="1.8.0"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
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
            /bin/bash "$BREW_INSTALL_SCRIPT"
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
    echo "  Устанавливаю whisper-cpp..."
    brew install whisper-cpp
    echo -e "${GREEN}✓ whisper-cpp установлен${NC}"
else
    echo -e "${GREEN}✓ whisper-cpp уже установлен${NC}"
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "  Устанавливаю ffmpeg..."
    brew install ffmpeg
    echo -e "${GREEN}✓ ffmpeg установлен${NC}"
else
    echo -e "${GREEN}✓ ffmpeg уже установлен${NC}"
fi
echo ""

# Скачивание модели
echo -e "${BLUE}[4/5]${NC} Загрузка AI модели (это займет время)..."
MODEL_PATH="$MODEL_DIR/ggml-large-v3.bin"

if [ -f "$MODEL_PATH" ]; then
    echo -e "${GREEN}✓ Модель уже скачана${NC}"
else
    echo "  Скачиваю модель ($MODEL_SIZE)..."
    echo "  URL: $WHISPER_MODEL_URL"
    echo ""
    
    # Скачиваем с прогресс-баром
    if command -v wget &> /dev/null; then
        wget --progress=bar:force -O "$MODEL_PATH" "$WHISPER_MODEL_URL" 2>&1 | \
            grep --line-buffered -oP '\d+(?=%)' | \
            while read percent; do
                echo -ne "  Прогресс: $percent%\r"
            done
        echo ""
    else
        curl -# -L -o "$MODEL_PATH" "$WHISPER_MODEL_URL"
    fi
    
    echo -e "${GREEN}✓ Модель успешно скачана${NC}"
    echo ""
    
    # Проверка целостности модели
    echo "  Проверка целостности модели..."
    if command -v shasum &> /dev/null; then
        ACTUAL_SHA256=$(shasum -a 256 "$MODEL_PATH" | cut -d' ' -f1)
    elif command -v sha256sum &> /dev/null; then
        ACTUAL_SHA256=$(sha256sum "$MODEL_PATH" | cut -d' ' -f1)
    else
        echo -e "${YELLOW}⚠ Предупреждение: shasum не найден, пропускаю проверку целостности${NC}"
        ACTUAL_SHA256=""
    fi
    
    if [ -n "$ACTUAL_SHA256" ]; then
        if [ "$ACTUAL_SHA256" = "$EXPECTED_MODEL_SHA256" ]; then
            echo -e "${GREEN}✓ Контрольная сумма совпадает (модель подлинная)${NC}"
        else
            echo -e "${RED}✗ ОШИБКА: Контрольная сумма не совпадает!${NC}"
            echo -e "${RED}  Ожидалось: $EXPECTED_MODEL_SHA256${NC}"
            echo -e "${RED}  Получено:  $ACTUAL_SHA256${NC}"
            echo -e "${RED}  Модель может быть повреждена или подменена.${NC}"
            rm -f "$MODEL_PATH"
            exit 1
        fi
    fi
fi
echo ""

# Создание скрипта транскрибации
echo -e "${BLUE}[5/5]${NC} Настройка транскрибатора..."

cat > "$BIN_DIR/transcribe.sh" << 'EOFSCRIPT'
#!/bin/bash

# Скрипт для транскрибации аудио/видео файлов

INPUT_FILE="$1"
INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
MODEL_PATH="$INSTALL_DIR/models/ggml-large-v3.bin"

# Проверка входного файла
if [ ! -f "$INPUT_FILE" ]; then
    osascript -e "display notification \"Файл не найден: $INPUT_FILE\" with title \"Ошибка транскрибации\""
    exit 1
fi

# Получаем директорию и имя файла
INPUT_DIR=$(dirname "$INPUT_FILE")
INPUT_NAME=$(basename "$INPUT_FILE")
INPUT_BASE="${INPUT_NAME%.*}"

# Путь для временного аудио и выходного текста
TEMP_AUDIO="$TMPDIR/${INPUT_BASE}.wav"
OUTPUT_TXT="$INPUT_DIR/${INPUT_BASE}.txt"

# Уведомление о начале
osascript -e "display notification \"Начинаю транскрибацию файла: $INPUT_NAME\" with title \"Transcribe\" sound name \"Glass\""

# Извлечение аудио (поддержка видео и аудио)
ffmpeg -i "$INPUT_FILE" -ac 1 -ar 16000 -c:a pcm_s16le "$TEMP_AUDIO" -y 2>/dev/null

if [ ! -f "$TEMP_AUDIO" ]; then
    osascript -e "display notification \"Не удалось извлечь аудио\" with title \"Ошибка\""
    exit 1
fi

# Получаем длительность
DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$TEMP_AUDIO" 2>/dev/null)
DURATION_FORMATTED=$(printf "%02d:%02d:%02d" $((${DURATION%.*}/3600)) $((${DURATION%.*}/60%60)) $((${DURATION%.*}%60)))

# Транскрибация
START_TIME=$(date +%s)

WHISPER_BIN=$(find /opt/homebrew/Cellar/whisper-cpp -name "whisper-cli" -type f 2>/dev/null | head -n 1)

if [ -z "$WHISPER_BIN" ]; then
    osascript -e "display notification \"Whisper-cpp не найден\" with title \"Ошибка\""
    exit 1
fi

TEMP_OUTPUT="$TMPDIR/${INPUT_BASE}_transcript"

"$WHISPER_BIN" \
    -m "$MODEL_PATH" \
    -f "$TEMP_AUDIO" \
    -l ru \
    --output-txt \
    --output-file "$TEMP_OUTPUT" 2>&1 | grep -E "progress|output_txt|whisper_print_timings" || true

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_FORMATTED=$(printf "%02d:%02d:%02d" $((ELAPSED/3600)) $((ELAPSED/60%60)) $((ELAPSED%60)))

# Формируем финальный файл с метаданными
{
    echo "========================================="
    echo "Исходный файл: $INPUT_NAME"
    echo "Длительность аудио: $DURATION_FORMATTED"
    echo "Время транскрибации: $ELAPSED_FORMATTED"
    echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Модель: Whisper Large-v3"
    echo "========================================="
    echo ""
    cat "${TEMP_OUTPUT}.txt" 2>/dev/null
} > "$OUTPUT_TXT"

# Очистка
rm -f "$TEMP_AUDIO" "${TEMP_OUTPUT}.txt"

# Уведомление об успехе
osascript -e "display notification \"Транскрибация завершена!\nФайл: ${INPUT_BASE}.txt\" with title \"Готово\" sound name \"Glass\""

# Открываем файл
open "$OUTPUT_TXT"

exit 0
EOFSCRIPT

chmod +x "$BIN_DIR/transcribe.sh"
echo -e "${GREEN}✓ Скрипт транскрибации создан${NC}"

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
                <string>public.mpeg-4</string>
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
    "$HOME/Library/Application Support/Transcribe/bin/transcribe.sh" "\$f" &amp;
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

