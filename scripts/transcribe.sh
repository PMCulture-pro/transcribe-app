#!/bin/bash
#
# Transcribe — транскрибация одного аудио/видео файла через whisper.cpp.
#
# Поведение:
#   • При старте рядом с исходником создаётся файл "<имя.ext>.InProgress.txt" со
#     временем старта, оценкой длительности и ожидаемым временем завершения
#     (расширение .txt — чтобы открывался Quick Look / пробелом).
#   • По завершении создаётся "<имя>.txt" с результатом, а .InProgress.txt
#     удаляется (если удалить не удалось — остаётся, пользователь уберёт сам).
#   • Оценка времени самообучающаяся: реальная скорость машины запоминается
#     в last_speed_factor и используется для следующих оценок.
#
# Использование: transcribe.sh <путь к аудио/видео>

# Finder Quick Action запускает скрипт с урезанным PATH (без Homebrew).
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

INPUT_FILE="$1"

INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
STATE_FILE="$INSTALL_DIR/last_speed_factor"   # realtime-множитель: сек аудио / сек обработки
SEED_FACTOR="4.0"                              # стартовая прикидка, пока нет истории

# --- Уведомления (безопасно к кавычкам/спецсимволам в тексте) ----------------
notify() {
    /usr/bin/osascript - "$1" "$2" "${3:-}" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
    set theTitle to item 1 of argv
    set theMsg to item 2 of argv
    set theSound to item 3 of argv
    if theSound is "" then
        display notification theMsg with title theTitle
    else
        display notification theMsg with title theTitle sound name theSound
    end if
end run
APPLESCRIPT
}

fmt_hms() { printf "%02d:%02d:%02d" $(($1/3600)) $((($1/60)%60)) $(($1%60)); }

# --- Проверка входа ----------------------------------------------------------
if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    notify "Ошибка транскрибации" "Файл не найден: ${INPUT_FILE:-<пусто>}"
    exit 1
fi

INPUT_DIR=$(dirname "$INPUT_FILE")
INPUT_NAME=$(basename "$INPUT_FILE")
INPUT_BASE="${INPUT_NAME%.*}"
OUTPUT_TXT="$INPUT_DIR/${INPUT_BASE}.txt"
PROGRESS_TXT="$INPUT_DIR/${INPUT_NAME}.InProgress.txt"

# --- Поиск модели (переиспользуем уже скачанную) -----------------------------
MODEL_PATH=""
for m in \
    "$INSTALL_DIR/models/ggml-large-v3.bin" \
    "$HOME/.cache/whisper/ggml-large-v3.bin"
do
    if [ -f "$m" ]; then MODEL_PATH="$m"; break; fi
done
if [ -z "$MODEL_PATH" ]; then
    notify "Ошибка транскрибации" "AI-модель ggml-large-v3.bin не найдена"
    exit 1
fi

# --- Поиск бинарников --------------------------------------------------------
WHISPER_BIN="$(command -v whisper-cli 2>/dev/null)"
if [ -z "$WHISPER_BIN" ]; then
    WHISPER_BIN="$(find /opt/homebrew/Cellar/whisper-cpp -name whisper-cli -type f 2>/dev/null | head -n 1)"
fi
FFMPEG_BIN="$(command -v ffmpeg 2>/dev/null)"
FFPROBE_BIN="$(command -v ffprobe 2>/dev/null)"
if [ -z "$WHISPER_BIN" ] || [ ! -x "$WHISPER_BIN" ]; then
    notify "Ошибка транскрибации" "whisper-cli не найден (brew install whisper-cpp)"
    exit 1
fi
if [ -z "$FFMPEG_BIN" ] || [ -z "$FFPROBE_BIN" ]; then
    notify "Ошибка транскрибации" "ffmpeg не найден (brew install ffmpeg)"
    exit 1
fi

# --- Извлечение аудио в WAV 16 кГц моно --------------------------------------
TEMP_DIR="${TMPDIR:-/tmp}"
TEMP_AUDIO="$TEMP_DIR/transcribe_$$.wav"
TEMP_OUTPUT="$TEMP_DIR/transcribe_$$_out"
cleanup() { rm -f "$TEMP_AUDIO" "${TEMP_OUTPUT}.txt"; }
trap cleanup EXIT

"$FFMPEG_BIN" -nostdin -i "$INPUT_FILE" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$TEMP_AUDIO" -y >/dev/null 2>&1
if [ ! -f "$TEMP_AUDIO" ]; then
    notify "Ошибка транскрибации" "Не удалось извлечь аудио из $INPUT_NAME"
    exit 1
fi

# --- Длительность ------------------------------------------------------------
DURATION=$("$FFPROBE_BIN" -v quiet -show_entries format=duration -of csv=p=0 "$TEMP_AUDIO" 2>/dev/null)
DUR_INT=${DURATION%.*}; DUR_INT=${DUR_INT:-0}
DURATION_FMT=$(fmt_hms "$DUR_INT")

# --- Оценка времени (самообучающийся множитель скорости) ---------------------
FACTOR="$SEED_FACTOR"
if [ -f "$STATE_FILE" ]; then
    v=$(cat "$STATE_FILE" 2>/dev/null)
    if awk -v x="$v" 'BEGIN{exit !(x+0>0)}'; then FACTOR="$v"; fi
fi
EST_SECS=$(awk -v d="$DUR_INT" -v f="$FACTOR" 'BEGIN{ if(f<=0)f=4; printf "%d", (d/f)+0.5 }')
[ "$EST_SECS" -lt 1 ] && EST_SECS=1
EST_FMT=$(fmt_hms "$EST_SECS")

START_EPOCH=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
FINISH_HUMAN=$(date -r $((START_EPOCH + EST_SECS)) '+%Y-%m-%d %H:%M:%S')

# --- Файл-индикатор "идёт транскрибация" -------------------------------------
{
    echo "$INPUT_NAME"
    echo "Старт транскрибации: $START_HUMAN"
    echo "Длительность аудио: $DURATION_FMT"
    echo "Примерное время транскрибации: $EST_FMT"
    echo "Примерное время завершения транскрибации: $FINISH_HUMAN"
    echo ""
    echo "Идёт распознавание…"
    echo "Когда закончится, рядом появится файл «${INPUT_BASE}.txt», а этот файл исчезнет."
} > "$PROGRESS_TXT" 2>/dev/null

notify "Transcribe" "Начинаю: $INPUT_NAME — примерно $EST_FMT" "Glass"

# --- Транскрибация с пингами прогресса ---------------------------------------
"$WHISPER_BIN" \
    -m "$MODEL_PATH" \
    -f "$TEMP_AUDIO" \
    -l ru \
    --print-progress \
    --output-txt \
    --output-file "$TEMP_OUTPUT" 2>&1 | {
        last=0
        while IFS= read -r line; do
            if [[ "$line" =~ progress[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
                p="${BASH_REMATCH[1]}"
                if   [ "$p" -ge 75 ] && [ "$last" -lt 75 ]; then notify "Transcribe" "Транскрибация… 75%"; last=75
                elif [ "$p" -ge 50 ] && [ "$last" -lt 50 ]; then notify "Transcribe" "Транскрибация… 50%"; last=50
                elif [ "$p" -ge 25 ] && [ "$last" -lt 25 ]; then notify "Transcribe" "Транскрибация… 25%"; last=25
                fi
            fi
        done
    }
WHISPER_STATUS=${PIPESTATUS[0]}

END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
ELAPSED_FMT=$(fmt_hms "$ELAPSED")
FINISH_REAL=$(date '+%Y-%m-%d %H:%M:%S')

# --- Обработка ошибки --------------------------------------------------------
if [ "$WHISPER_STATUS" -ne 0 ] || [ ! -f "${TEMP_OUTPUT}.txt" ]; then
    {
        echo "$INPUT_NAME"
        echo "Старт транскрибации: $START_HUMAN"
        echo "❌ Ошибка: не удалось завершить транскрибацию (код $WHISPER_STATUS)."
        echo "Попробуйте запустить ещё раз. Этот файл можно удалить."
    } > "$PROGRESS_TXT" 2>/dev/null
    notify "Ошибка транскрибации" "Не удалось транскрибировать $INPUT_NAME" "Basso"
    exit 1
fi

# --- Финальный файл с результатом --------------------------------------------
{
    echo "========================================="
    echo "Исходный файл: $INPUT_NAME"
    echo "Длительность аудио: $DURATION_FMT"
    echo "Старт транскрибации: $START_HUMAN"
    echo "Завершение транскрибации: $FINISH_REAL"
    echo "Время транскрибации: $ELAPSED_FMT"
    echo "Модель: Whisper Large-v3"
    echo "========================================="
    echo ""
    cat "${TEMP_OUTPUT}.txt"
} > "$OUTPUT_TXT"

# --- Удаляем файл-индикатор (best-effort) ------------------------------------
rm -f "$PROGRESS_TXT" 2>/dev/null || true

# --- Обновляем оценку скорости (только для файлов от 60 c) --------------------
if [ "$DUR_INT" -ge 60 ] && [ "$ELAPSED" -gt 0 ]; then
    NEWF=$(awk -v d="$DUR_INT" -v e="$ELAPSED" 'BEGIN{printf "%.3f", d/e}')
    if [ -f "$STATE_FILE" ]; then
        OLD=$(cat "$STATE_FILE" 2>/dev/null)
        NEWF=$(awk -v o="$OLD" -v n="$NEWF" 'BEGIN{ if(o+0<=0){print n} else {printf "%.3f", 0.5*o+0.5*n} }')
    fi
    echo "$NEWF" > "$STATE_FILE" 2>/dev/null || true
fi

notify "Готово ✅" "Готово за ${ELAPSED_FMT}: ${INPUT_BASE}.txt" "Glass"
exit 0
