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

# --- Конфигурация (env-переменные) -------------------------------------------
# RU-1: язык. auto = автоопределение; ru/en/… — зафиксировать (убирает ложные
#       детекты на коротких/шумных фразах, чуть быстрее старт).
LANG_CODE="${TRANSCRIBE_LANG:-auto}"
# RU-2: профиль качества. max — точнее, но в 2–4× медленнее; fast — жадный поиск.
#       Самообучающийся множитель времени подстроится сам.
QUALITY="${QUALITY:-balanced}"
# RU-3: VAD против галлюцинаций в тишине/паузах (нужна скачанная VAD-модель).
USE_VAD="${VAD:-0}"
VAD_MODEL_PATH="$INSTALL_DIR/models/ggml-silero-v5.1.2.bin"
# FEAT-1: TIMESTAMPS=1 — вставить таймкоды [ЧЧ:ММ:СС] прямо в расшифровку.
USE_TIMESTAMPS="${TIMESTAMPS:-0}"
# FEAT-3: READABLE=1 — разбивка на абзацы по паузам + перенос длинных строк.
USE_READABLE="${READABLE:-0}"
PARA_GAP="${PARA_GAP:-2.0}"   # пауза (сек) между репликами → новый абзац
WRAP_WIDTH="${WRAP_WIDTH:-90}" # ширина переноса строк для читаемого режима

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
# Расширение входит в имя результата (meeting.mp4 → meeting.mp4.txt): иначе
# meeting.mp3 и meeting.mp4 дали бы один meeting.txt (второй затёр бы первый),
# и легко затереть заметки пользователя meeting.txt. См. BACKLOG BUG-1.
OUTPUT_NAME="${INPUT_NAME}.txt"
OUTPUT_TXT="$INPUT_DIR/${OUTPUT_NAME}"
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
cleanup() { rm -f "$TEMP_AUDIO" "${TEMP_OUTPUT}.txt" "${TEMP_OUTPUT}.srt" "${TEMP_OUTPUT}.body"; }
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

# Видео без аудиодорожки / пустой звук → whisper галлюцинирует выдуманный текст.
# Существование WAV ещё не значит, что в нём есть звук. См. BACKLOG BUG-2.
if [ ! -s "$TEMP_AUDIO" ] || [ "$DUR_INT" -lt 1 ]; then
    notify "Ошибка транскрибации" "В «$INPUT_NAME» нет звука (пустая или отсутствующая аудиодорожка)" "Basso"
    exit 1
fi

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
    echo "Когда закончится, рядом появится файл «${OUTPUT_NAME}», а этот файл исчезнет."
} > "$PROGRESS_TXT" 2>/dev/null

notify "Transcribe" "Начинаю: $INPUT_NAME — примерно $EST_FMT" "Glass"

# --- Сборка аргументов whisper -----------------------------------------------
case "$QUALITY" in
    max)  QUALITY_ARGS=(--beam-size 8 --best-of 8 --entropy-thold 2.4 --max-context 64) ;;
    fast) QUALITY_ARGS=(--beam-size 1 --best-of 1) ;;
    *)    QUALITY_ARGS=(--beam-size 5 --best-of 5 --entropy-thold 2.4 --max-context 64) ;;  # balanced
esac

VAD_ARGS=()
if [ "$USE_VAD" = "1" ]; then
    if [ -f "$VAD_MODEL_PATH" ]; then
        VAD_ARGS=(--vad --vad-model "$VAD_MODEL_PATH")
    else
        notify "Transcribe" "VAD-модель не найдена — продолжаю без VAD"
    fi
fi

# .srt нужен и для таймкодов (FEAT-1), и для разбивки на абзацы по паузам (FEAT-3).
TS_ARGS=()
if [ "$USE_TIMESTAMPS" = "1" ] || [ "$USE_READABLE" = "1" ]; then
    TS_ARGS=(--output-srt)
fi

# --- Транскрибация с пингами прогресса ---------------------------------------
"$WHISPER_BIN" \
    -m "$MODEL_PATH" \
    -f "$TEMP_AUDIO" \
    -l "$LANG_CODE" \
    "${QUALITY_ARGS[@]}" \
    "${VAD_ARGS[@]}" \
    "${TS_ARGS[@]}" \
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

# --- Тело расшифровки --------------------------------------------------------
TRANSCRIPT_BODY="${TEMP_OUTPUT}.body"
SRT="${TEMP_OUTPUT}.srt"

# FEAT-3: читаемый режим — абзацы по паузам + перенос строк. На python3, потому
# что awk/fold на macOS считают байты и рвут кириллицу (UTF-8). Аргументы:
# PARA_GAP WRAP_WIDTH USE_TIMESTAMPS SRT.
format_readable() {
    python3 - "$PARA_GAP" "$WRAP_WIDTH" "$USE_TIMESTAMPS" "$SRT" <<'PY'
import sys, re, textwrap

gap     = float(sys.argv[1])
width   = int(sys.argv[2])
want_ts = sys.argv[3] == "1"
path    = sys.argv[4]

def tosec(t):
    h, m, rest = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(rest.replace(",", "."))

with open(path, encoding="utf-8", errors="replace") as f:
    content = f.read().strip()

cues = []
for block in re.split(r"\r?\n\r?\n", content):
    lines = block.splitlines()
    ts_idx = next((i for i, l in enumerate(lines) if "-->" in l), None)
    if ts_idx is None:
        continue
    a, b = lines[ts_idx].split("-->")
    text = " ".join(x.strip() for x in lines[ts_idx + 1:] if x.strip())
    if text:
        cues.append((tosec(a.strip().split()[0]), a.strip()[:8], tosec(b.strip().split()[0]), text))

# Группируем в абзацы: пауза между репликами > gap → новый абзац.
paras, cur, cur_ts, prev_end = [], [], None, None
for s, label, e, text in cues:
    if prev_end is not None and (s - prev_end) > gap and cur:
        paras.append((cur_ts, " ".join(cur)))
        cur = []
    if not cur:
        cur_ts = label
    cur.append(text)
    prev_end = e
if cur:
    paras.append((cur_ts, " ".join(cur)))

out = []
for ts, ptext in paras:
    prefix = "[%s] " % ts if want_ts else ""
    out.append(textwrap.fill(
        ptext, width=width,
        initial_indent=prefix, subsequent_indent=" " * len(prefix),
        break_long_words=False, break_on_hyphens=False))
    out.append("")  # пустая строка между абзацами

sys.stdout.write(("\n".join(out)).rstrip() + "\n")
PY
}

build_body() {
    if [ "$USE_READABLE" = "1" ] && [ -f "$SRT" ] && command -v python3 >/dev/null 2>&1; then
        if format_readable > "$TRANSCRIPT_BODY" 2>/dev/null && [ -s "$TRANSCRIPT_BODY" ]; then
            return
        fi
    fi
    # FEAT-1: только таймкоды — строки «[ЧЧ:ММ:СС] текст».
    if [ "$USE_TIMESTAMPS" = "1" ] && [ -f "$SRT" ]; then
        awk '
            /-->/               { split($1, t, ","); ts=t[1]; text=""; next }
            /^[0-9]+\r?$/        { next }
            /^[[:space:]]*\r?$/  { if (ts!="") { print "[" ts "] " text; ts=""; text="" } next }
                                { sub(/\r$/,""); text=(text=="" ? $0 : text " " $0) }
            END                 { if (ts!="") print "[" ts "] " text }
        ' "$SRT" > "$TRANSCRIPT_BODY"
        return
    fi
    # Обычная сплошная расшифровка.
    cp "${TEMP_OUTPUT}.txt" "$TRANSCRIPT_BODY"
}

build_body

# --- Финальный файл с результатом --------------------------------------------
{
    echo "========================================="
    echo "Исходный файл: $INPUT_NAME"
    echo "Длительность аудио: $DURATION_FMT"
    echo "Старт транскрибации: $START_HUMAN"
    echo "Завершение транскрибации: $FINISH_REAL"
    echo "Время транскрибации: $ELAPSED_FMT"
    echo "Модель: Whisper Large-v3 (язык: $LANG_CODE, качество: $QUALITY)"
    echo "========================================="
    echo ""
    cat "$TRANSCRIPT_BODY"
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

notify "Готово ✅" "Готово за ${ELAPSED_FMT}: ${OUTPUT_NAME}" "Glass"
exit 0
