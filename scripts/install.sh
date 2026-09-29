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
# VAD-модель Silero для RU-3 (несколько МБ) — против галлюцинаций в паузах.
VAD_MODEL_URL="https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin"
# Turbo-модель (~1.6 ГБ) — опционально, для MODEL=turbo (~3× быстрее large-v3).
TURBO_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
# Канонические скрипты (transcribe.sh, gigaam_transcribe.py) — единый источник правды.
# Установщик копирует соседние файлы при запуске из клона репозитория, иначе докачивает по URL.
RAW_SCRIPTS_URL="https://raw.githubusercontent.com/PMCulture-pro/transcribe-app/main/scripts"
# GigaAM v3 E2E-RNN-T (опционально, WITH_GIGAAM=1) — вторая нейросеть для двойной
# расшифровки. Пакет ставится с GitHub (на PyPI лежит устаревшая 0.1.0 под torch ≤ 2.5)
# и закреплён на коммите; веса — с CDN Sber, md5 — из gigaam/__init__.py (_MODEL_HASHES).
GIGAAM_GIT="git+https://github.com/salute-developers/GigaAM.git@7447938d791c4f3e643386ee22c33777004293a5"
GIGAAM_CDN="https://cdn.chatwm.opensmodel.sberdevices.ru/GigaAM"
GIGAAM_CKPT_MD5="2730de7545ac43ad256485a462b0a27a"
GIGAAM_TOKENIZER_SHA256="828c12c991019eef952a960661f25a92d6ad279591e2ea466b4aeddf1d20a18a"
GIGAAM_SIZE="~1.5 GB"   # venv с PyTorch ~1 ГБ + модель 450 МБ + спикеры ~35 МБ
# Разметка спикеров (FEAT-5, ставится вместе с GigaAM в тот же venv): sherpa-onnx +
# модели, что внутри pyannote/speaker-diarization-3.1, в ONNX (без токена Hugging Face).
# Источник — релизы k2-fsa/sherpa-onnx на GitHub; версии и SHA256 закреплены.
SHERPA_ONNX_PKG="sherpa-onnx==1.13.8"
DIAR_SEG_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2"
DIAR_SEG_TAR_SHA256="24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488"
DIAR_SEG_SHA256="220ad67ca923bef2fa91f2390c786097bf305bceb5e261d4af67b38e938e1079"
DIAR_EMB_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx"
DIAR_EMB_SHA256="e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012"
MODEL_SIZE="3.0 GB"
FFMPEG_SIZE="95 MB"
TOTAL_SIZE="3.1 GB"

# SHA256 контрольные суммы моделей для проверки целостности.
# Источник: LFS-указатели соответствующих файлов на Hugging Face.
EXPECTED_MODEL_SHA256="64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
EXPECTED_TURBO_SHA256="1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
EXPECTED_VAD_SHA256="29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf"

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
if [ "${WITH_GIGAAM:-0}" = "1" ]; then
    echo "  ✓ GigaAM v3 E2E-RNN-T (Sber) - вторая AI модель: каждый файл распознаётся"
    echo "    двумя сетями, рядом появляются <имя>.whisper.txt и <имя>.gigaam.txt"
    echo "    + разметка спикеров (SPEAKERS=auto в файле настроек)"
    echo "    Размер: $GIGAAM_SIZE (Python-окружение с PyTorch + модель)"
    echo ""
    TOTAL_SIZE="4.6 GB"
fi
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

# sha256_file <файл> → печатает sha256 файла или ничего, если нечем считать
sha256_file() {
    if command -v shasum &> /dev/null; then
        shasum -a 256 "$1" | cut -d' ' -f1
    elif command -v sha256sum &> /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    fi
}

# verify_sha <файл> <ожидаемая-sha> → 0 совпадает · 1 не совпадает · 2 нечем проверить
verify_sha() {
    local actual; actual=$(sha256_file "$1")
    [ -z "$actual" ] && return 2
    [ "$actual" = "$2" ]
}

# 0 = SHA совпадает · 1 = не совпадает · 2 = нечем проверить
verify_model_sha() { verify_sha "$MODEL_PATH" "$EXPECTED_MODEL_SHA256"; }

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
    # curl на macOS есть всегда, умеет resume (-C -) и прогресс-бар (-#).
    # wget — запасной: его прогресс через `grep -oP` несовместим с BSD grep, поэтому
    # парсинг убран, используется собственный прогресс-бар wget.
    # set -e иначе оборвёт скрипт на неудачном curl ДО проверки кода — ловим через ||.
    DL_STATUS=0
    if command -v curl &> /dev/null; then
        curl -fL -C - -# -o "$MODEL_PATH" "$WHISPER_MODEL_URL" || DL_STATUS=$?
    else
        wget -c -O "$MODEL_PATH" "$WHISPER_MODEL_URL" || DL_STATUS=$?
    fi

    # Явная проверка кода возврата загрузки (INS-2).
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

# --- VAD-модель (опционально, для RU-3: VAD=1 против галлюцинаций в паузах) ---
VAD_MODEL_PATH="$MODEL_DIR/ggml-silero-v5.1.2.bin"
if [ -f "$VAD_MODEL_PATH" ] && verify_sha "$VAD_MODEL_PATH" "$EXPECTED_VAD_SHA256"; then
    echo -e "${GREEN}✓ VAD-модель уже скачана и проверена${NC}"
else
    echo "  Скачиваю VAD-модель (несколько МБ; нужна только для VAD=1)..."
    if curl -fL -C - -o "$VAD_MODEL_PATH" "$VAD_MODEL_URL" && \
       verify_sha "$VAD_MODEL_PATH" "$EXPECTED_VAD_SHA256"; then
        echo -e "${GREEN}✓ VAD-модель скачана и проверена${NC}"
    else
        rm -f "$VAD_MODEL_PATH"
        echo -e "${YELLOW}⚠ VAD-модель не скачалась или не прошла проверку — VAD недоступен (необязательно)${NC}"
    fi
fi
echo ""

# --- Turbo-модель (опционально, ~1.6 ГБ; только при WITH_TURBO=1) -------------
TURBO_MODEL_PATH="$MODEL_DIR/ggml-large-v3-turbo.bin"
if [ -f "$TURBO_MODEL_PATH" ] && verify_sha "$TURBO_MODEL_PATH" "$EXPECTED_TURBO_SHA256"; then
    echo -e "${GREEN}✓ Turbo-модель уже скачана и проверена${NC}"
elif [ "${WITH_TURBO:-0}" = "1" ]; then
    echo "  Скачиваю turbo-модель (~1.6 ГБ; для MODEL=turbo, ~3× быстрее)..."
    if curl -fL -C - -# -o "$TURBO_MODEL_PATH" "$TURBO_MODEL_URL" && \
       verify_sha "$TURBO_MODEL_PATH" "$EXPECTED_TURBO_SHA256"; then
        echo -e "${GREEN}✓ Turbo-модель скачана и проверена${NC}"
    else
        rm -f "$TURBO_MODEL_PATH"
        echo -e "${YELLOW}⚠ Turbo-модель не скачалась или не прошла проверку (необязательно)${NC}"
    fi
else
    echo -e "${BLUE}ℹ Turbo-модель пропущена. Для ~3× ускорения: переустановить с WITH_TURBO=1, затем MODEL=turbo${NC}"
fi
echo ""

# --- GigaAM v3 E2E-RNN-T (опционально; только при WITH_GIGAAM=1) --------------
# Вторая нейросеть для двойной расшифровки одного файла (ENGINE=auto/both в
# transcribe.sh): Python-venv с PyTorch, GigaAM и Silero VAD в $INSTALL_DIR/gigaam,
# веса модели — в $MODEL_DIR/gigaam (всё внутри папки приложения — деинсталлятор
# снесёт целиком). Ошибки здесь НЕ валят установку: Whisper остаётся рабочим, GigaAM
# можно доставить повторным запуском с WITH_GIGAAM=1. См. BACKLOG FEAT-6.
GIGAAM_VENV="$INSTALL_DIR/gigaam/venv"
GIGAAM_MODELS_DIR="$MODEL_DIR/gigaam"
GIGAAM_STATUS="skipped"   # skipped | ok | failed

md5_of() { md5 -q "$1" 2>/dev/null || openssl md5 -r "$1" 2>/dev/null | cut -d' ' -f1; }

find_python() {  # первый Python 3.10–3.13 с venv+ensurepip (под них есть колёса torch и onnxruntime)
    local c p
    for c in python3.12 python3.11 python3.13 python3.10 python3; do
        p="$(command -v "$c" 2>/dev/null)" || continue
        if "$p" -c 'import sys, venv, ensurepip; sys.exit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)' 2>/dev/null; then
            printf '%s\n' "$p"; return 0
        fi
    done
    return 1
}

install_gigaam() {
    local py ckpt tok
    if ! py="$(find_python)"; then
        echo "  Python 3.10–3.13 не найден — устанавливаю python@3.12 через Homebrew..."
        brew install -q python@3.12 || return 1
        py="$(brew --prefix python@3.12)/bin/python3.12"
    fi
    echo "  Python: $py"
    if [ ! -x "$GIGAAM_VENV/bin/python" ]; then
        "$py" -m venv "$GIGAAM_VENV" || return 1
    fi
    start_heartbeat "  Установка PyTorch + GigaAM + Silero VAD (~1 ГБ)"
    "$GIGAAM_VENV/bin/python" -m pip install -q --upgrade pip \
        && "$GIGAAM_VENV/bin/python" -m pip install -q "torch>=2.6" "torchaudio>=2.6" "silero-vad" "gigaam @ $GIGAAM_GIT" \
        && "$GIGAAM_VENV/bin/python" -c 'import torch, gigaam, silero_vad'
    local rc=$?
    stop_background_progress
    echo ""
    [ "$rc" -eq 0 ] || return 1
    echo -e "${GREEN}✓ Python-окружение GigaAM готово${NC}"

    # Веса модели (450 МБ) — с докачкой и проверкой md5, чтобы первый запуск из Finder
    # не висел на скачивании. Не скачались — не страшно: раннер докачает при первом запуске.
    mkdir -p "$GIGAAM_MODELS_DIR"
    ckpt="$GIGAAM_MODELS_DIR/v3_e2e_rnnt.ckpt"
    tok="$GIGAAM_MODELS_DIR/v3_e2e_rnnt_tokenizer.model"
    if [ -f "$ckpt" ] && [ "$(md5_of "$ckpt")" = "$GIGAAM_CKPT_MD5" ]; then
        echo -e "${GREEN}✓ Модель GigaAM уже скачана и проверена${NC}"
    else
        echo "  Скачиваю модель GigaAM v3 E2E-RNN-T (450 МБ)..."
        if curl -fL -C - -# -o "$ckpt" "$GIGAAM_CDN/v3_e2e_rnnt.ckpt" && [ "$(md5_of "$ckpt")" = "$GIGAAM_CKPT_MD5" ]; then
            echo -e "${GREEN}✓ Модель GigaAM скачана (md5 совпадает)${NC}"
        else
            rm -f "$ckpt"
            echo -e "${YELLOW}⚠ Модель GigaAM не скачалась — будет скачана при первом запуске${NC}"
        fi
    fi
    if ! { [ -s "$tok" ] && verify_sha "$tok" "$GIGAAM_TOKENIZER_SHA256"; }; then
        if curl -fsSL -o "$tok.part" "$GIGAAM_CDN/v3_e2e_rnnt_tokenizer.model" \
            && verify_sha "$tok.part" "$GIGAAM_TOKENIZER_SHA256"; then
            mv "$tok.part" "$tok"
        else
            rm -f "$tok.part"
            echo -e "${YELLOW}⚠ Токенизатор GigaAM не скачался или не прошёл проверку SHA256${NC}"
        fi
    fi

    # Разметка спикеров: ошибка здесь не валит GigaAM — просто SPEAKERS будет недоступен.
    install_diarization || echo -e "${YELLOW}⚠ Разметка спикеров не установилась — GigaAM и Whisper работают без неё${NC}"
    return 0
}

install_diarization() {  # sherpa-onnx в venv GigaAM + модели сегментации и эмбеддингов (SHA256)
    local dir="$MODEL_DIR/diarization" seg emb tar tmpd
    seg="$dir/segmentation-3.0.onnx"
    emb="$dir/wespeaker_en_voxceleb_resnet34_LM.onnx"
    mkdir -p "$dir"
    "$GIGAAM_VENV/bin/python" -m pip install -q "$SHERPA_ONNX_PKG" \
        && "$GIGAAM_VENV/bin/python" -c 'import sherpa_onnx' || return 1
    if ! { [ -f "$seg" ] && verify_sha "$seg" "$DIAR_SEG_SHA256"; }; then
        tar="$dir/segmentation.tar.bz2"
        tmpd="$dir/.seg"
        curl -fsSL -o "$tar" "$DIAR_SEG_URL" && verify_sha "$tar" "$DIAR_SEG_TAR_SHA256" || { rm -f "$tar"; return 1; }
        rm -rf "$tmpd" && mkdir -p "$tmpd" \
            && tar -xjf "$tar" -C "$tmpd" sherpa-onnx-pyannote-segmentation-3-0/model.onnx \
            && verify_sha "$tmpd/sherpa-onnx-pyannote-segmentation-3-0/model.onnx" "$DIAR_SEG_SHA256" \
            && mv -f "$tmpd/sherpa-onnx-pyannote-segmentation-3-0/model.onnx" "$seg"
        local rc=$?
        rm -rf "$tmpd" "$tar"
        [ "$rc" -eq 0 ] || return 1
    fi
    if ! { [ -f "$emb" ] && verify_sha "$emb" "$DIAR_EMB_SHA256"; }; then
        curl -fsSL -o "$emb.part" "$DIAR_EMB_URL" && verify_sha "$emb.part" "$DIAR_EMB_SHA256" \
            && mv -f "$emb.part" "$emb" || { rm -f "$emb.part"; return 1; }
    fi
    echo -e "${GREEN}✓ Разметка спикеров готова (pyannote segmentation-3.0 + WeSpeaker ResNet34-LM)${NC}"
}

if [ "${WITH_GIGAAM:-0}" = "1" ]; then
    echo "  Устанавливаю GigaAM v3 E2E-RNN-T (вторая нейросеть, $GIGAAM_SIZE)..."
    if install_gigaam; then
        GIGAAM_STATUS="ok"
        echo -e "${GREEN}✓ GigaAM установлен — каждый файл будет распознан двумя сетями${NC}"
    else
        GIGAAM_STATUS="failed"
        echo -e "${YELLOW}⚠ GigaAM не установился — Whisper работает как обычно.${NC}"
        echo -e "${YELLOW}  Повторить: WITH_GIGAAM=1 bash install.sh${NC}"
    fi
elif [ -x "$GIGAAM_VENV/bin/python" ]; then
    GIGAAM_STATUS="ok"
    echo -e "${GREEN}✓ GigaAM уже установлен${NC}"
else
    echo -e "${BLUE}ℹ GigaAM пропущен. Для двойной расшифровки (Whisper + GigaAM v3): переустановить с WITH_GIGAAM=1${NC}"
fi
echo ""

# Создание скрипта транскрибации
echo -e "${BLUE}[5/5]${NC} Настройка транскрибатора..."

# scripts/transcribe.sh и scripts/gigaam_transcribe.py — единый источник правды
# (раньше transcribe.sh дублировался здесь heredoc'ом и молча расходился с репозиторием).
# При запуске установщика из клона копируем соседний файл; иначе докачиваем из
# репозитория. См. BACKLOG MNT-1.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

install_script() {  # $1 — имя файла из scripts/: локальная копия рядом с установщиком или скачивание
    local name="$1" local_copy="$SCRIPT_DIR/$1" tmp="$BIN_DIR/.$1.new"
    # Сначала во временный файл, потом mv: bash читает скрипт по ходу исполнения, и если
    # в этот момент идёт транскрибация (из Finder, минуты), перезапись cp «на месте»
    # ломает работающий процесс (syntax error посреди слова). mv подменяет только имя —
    # запущенный экземпляр дочитает старую копию.
    if [ -n "$SCRIPT_DIR" ] && [ -f "$local_copy" ]; then
        cp "$local_copy" "$tmp"
        echo -e "${GREEN}✓ $name установлен (локальная копия)${NC}"
    elif curl -fsSL "$RAW_SCRIPTS_URL/$name" -o "$tmp"; then
        echo -e "${GREEN}✓ $name загружен${NC}"
    else
        rm -f "$tmp"
        echo -e "${RED}✗ Не удалось получить $name${NC}"
        echo -e "${RED}  Нет локальной копии рядом с установщиком и не удалось скачать:${NC}"
        echo -e "${RED}  $RAW_SCRIPTS_URL/$name${NC}"
        return 1
    fi
    chmod +x "$tmp" && mv -f "$tmp" "$BIN_DIR/$name"
}

install_script transcribe.sh || exit 1
# Раннер GigaAM ставим всегда (он маленький): venv можно доставить позже через WITH_GIGAAM=1.
install_script gigaam_transcribe.py || echo -e "${YELLOW}⚠ gigaam_transcribe.py не получен — GigaAM будет недоступен${NC}"
install_script diarize.py || echo -e "${YELLOW}⚠ diarize.py не получен — разметка спикеров будет недоступна${NC}"
echo -e "${GREEN}✓ Скрипт транскрибации готов${NC}"

# Файл настроек (язык, качество, таймкоды, движки) — шаблон создаётся один раз,
# при переустановке существующий файл не трогаем.
if SETTINGS_PATH="$(bash "$BIN_DIR/transcribe.sh" --init-settings 2>/dev/null)"; then
    echo -e "${GREEN}✓ Файл настроек: $SETTINGS_PATH${NC}"
fi

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

if [ -x "$INSTALL_DIR/gigaam/venv/bin/python" ]; then
    echo "  ✓ GigaAM v3 (Python-окружение и модель — внутри папки приложения)"
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
    <key>CFBundleIdentifier</key>
    <string>com.mok.transcribe.quickaction</string>
    <key>CFBundleName</key>
    <string>Транскрибировать</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>ru_RU</string>
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
            <!-- Реальные медиа-UTI покрывают mp3/mov/mp4/m4a/wav/flac/ogg/aac/avi/webm/wma.
                 public.data не используем: он показывал бы пункт на ВСЕХ файлах (pdf/txt/…).
                 mkv/opus имеют на macOS только динамический dyn.* UTI и в меню не попадут —
                 для них используйте запуск из командной строки. -->
            <key>NSSendFileTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.audio</string>
                <string>public.audiovisual-content</string>
                <string>public.mpeg-4</string>
                <string>org.webmproject.webm</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# document.wflow для workflow — ПОЛНЫЙ документ Automator, а не только массив actions.
# Finder запускает Службу через строгий WorkflowServiceRunner, который падает с
# assertion (AMWorkflowServiceRunner.m) на неполном документе — пункт меню виден,
# но клик молча ничего не делает. Структура сверена с документом, который создаёт
# сам Automator (macOS 15): AMDocumentVersion, метаданные действия (BundleIdentifier
# com.apple.RunShellScript, Class Name, уникальные UUID, nibPath) и workflowMetaData
# с workflowTypeIdentifier = com.apple.Automator.servicesMenu.
WF_IN_UUID="$(uuidgen)"
WF_OUT_UUID="$(uuidgen)"
WF_ACT_UUID="$(uuidgen)"

cat > "$WORKFLOW_PATH/Contents/document.wflow" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>534</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>AMDocumentVersion</key>
    <string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Optional</key>
                    <true/>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.string</string>
                    </array>
                </dict>
                <key>AMActionVersion</key>
                <string>2.0.3</string>
                <key>AMApplication</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>AMParameterProperties</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <dict/>
                    <key>CheckedForUserDefaultShell</key>
                    <dict/>
                    <key>inputMethod</key>
                    <dict/>
                    <key>shell</key>
                    <dict/>
                    <key>source</key>
                    <dict/>
                </dict>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.string</string>
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
    "\$HOME/Library/Application Support/Transcribe/bin/transcribe.sh" "\$f"
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
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key>
                <string>2.0.3</string>
                <key>CanShowSelectedItemsWhenRun</key>
                <false/>
                <key>CanShowWhenRun</key>
                <true/>
                <key>Category</key>
                <array>
                    <string>AMCategoryUtilities</string>
                </array>
                <key>Class Name</key>
                <string>RunShellScriptAction</string>
                <key>InputUUID</key>
                <string>${WF_IN_UUID}</string>
                <key>Keywords</key>
                <array>
                    <string>Shell</string>
                    <string>Script</string>
                    <string>Command</string>
                    <string>Run</string>
                    <string>Unix</string>
                </array>
                <key>OutputUUID</key>
                <string>${WF_OUT_UUID}</string>
                <key>UUID</key>
                <string>${WF_ACT_UUID}</string>
                <key>UnlocalizedApplications</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>arguments</key>
                <dict>
                    <key>0</key>
                    <dict>
                        <key>default value</key>
                        <integer>0</integer>
                        <key>name</key>
                        <string>inputMethod</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>0</string>
                    </dict>
                    <key>1</key>
                    <dict>
                        <key>default value</key>
                        <false/>
                        <key>name</key>
                        <string>CheckedForUserDefaultShell</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>1</string>
                    </dict>
                    <key>2</key>
                    <dict>
                        <key>default value</key>
                        <string></string>
                        <key>name</key>
                        <string>source</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>2</string>
                    </dict>
                    <key>3</key>
                    <dict>
                        <key>default value</key>
                        <string></string>
                        <key>name</key>
                        <string>COMMAND_STRING</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>3</string>
                    </dict>
                    <key>4</key>
                    <dict>
                        <key>default value</key>
                        <string>/bin/sh</string>
                        <key>name</key>
                        <string>shell</string>
                        <key>required</key>
                        <string>0</string>
                        <key>type</key>
                        <string>0</string>
                        <key>uuid</key>
                        <string>4</string>
                    </dict>
                </dict>
                <key>isViewVisible</key>
                <integer>1</integer>
                <key>location</key>
                <string>309.000000:253.000000</string>
                <key>nibPath</key>
                <string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
            </dict>
            <key>isViewVisible</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>connectors</key>
    <dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>applicationBundleIDsByPath</key>
        <dict/>
        <key>applicationPaths</key>
        <array/>
        <key>inputTypeIdentifier</key>
        <string>com.apple.Automator.fileSystemObject</string>
        <key>outputTypeIdentifier</key>
        <string>com.apple.Automator.nothing</string>
        <key>presentationMode</key>
        <integer>11</integer>
        <key>processesInput</key>
        <integer>0</integer>
        <key>serviceApplicationBundleID</key>
        <string>com.apple.finder</string>
        <key>serviceApplicationPath</key>
        <string>/System/Library/CoreServices/Finder.app</string>
        <key>serviceInputTypeIdentifier</key>
        <string>com.apple.Automator.fileSystemObject</string>
        <key>serviceOutputTypeIdentifier</key>
        <string>com.apple.Automator.nothing</string>
        <key>serviceProcessesInput</key>
        <integer>0</integer>
        <key>systemImageName</key>
        <string>NSActionTemplate</string>
        <key>useAutomaticInputType</key>
        <integer>0</integer>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
    </dict>
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
if [ "$GIGAAM_STATUS" = "ok" ]; then
    echo "     Файлов будет два: <имя>.whisper.txt и <имя>.gigaam.txt (GigaAM v3) —"
    echo "     одна запись, два независимых распознавания. Только Whisper: ENGINE=whisper"
fi
echo ""
echo -e "${YELLOW}💡 Совет:${NC} Первая транскрибация может занять больше времени"
echo -e "${YELLOW}   из-за инициализации модели.${NC}"
echo ""
echo -e "${BLUE}Установлено в:${NC}"
echo "  • Приложение: $INSTALL_DIR"
echo "  • Quick Action: $SERVICES_DIR/Транскрибировать.workflow"
echo "  • Настройки: $INSTALL_DIR/settings.txt (язык, качество, таймкоды, движки —"
echo "    действуют и для правого клика в Finder; откройте в TextEdit)"
echo ""
echo -e "${YELLOW}🗑️  Для удаления запустите:${NC}"
echo "  bash \"$BIN_DIR/uninstall.sh\""
echo ""
echo -e "${GREEN}Спасибо за использование Transcribe App! 🎉${NC}"
echo ""

