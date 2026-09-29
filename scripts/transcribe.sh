#!/bin/bash
#
# Transcribe — транскрибация одного аудио/видео файла через whisper.cpp и/или GigaAM.
#
# Поведение:
#   • При старте рядом с исходником создаётся файл "<имя.ext>.InProgress.txt" со
#     временем старта, оценкой длительности и ожидаемым временем завершения
#     (расширение .txt — чтобы открывался Quick Look / пробелом).
#   • По завершении рядом появляются результаты: "<имя.ext>.whisper.txt" (Whisper) и/или
#     "<имя.ext>.gigaam.txt" (GigaAM v3 E2E-RNN-T) — одно и то же аудио, распознанное
#     двумя независимыми сетями. .InProgress.txt удаляется (если удалить не удалось —
#     остаётся, пользователь уберёт сам).
#   • Оценка времени самообучающаяся: реальная скорость машины запоминается
#     отдельно для каждого движка (last_speed_factor, last_speed_factor_gigaam).
#   • Настройки берутся из env-переменных, а если их нет — из файла settings.txt
#     рядом с моделями (так настройки действуют и для правого клика в Finder).
#
# Использование: transcribe.sh <путь к аудио/видео>
#                transcribe.sh --init-settings   # создать шаблон settings.txt

# Finder Quick Action запускает скрипт с урезанным PATH (без Homebrew).
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"

INPUT_FILE="$1"

INSTALL_DIR="$HOME/Library/Application Support/Transcribe"
STATE_FILE="$INSTALL_DIR/last_speed_factor"   # realtime-множитель Whisper: сек аудио / сек обработки
SEED_FACTOR="4.0"                              # стартовая прикидка, пока нет истории
LOG_DIR="$INSTALL_DIR/logs"                    # вывод движков последнего запуска (для разбора ошибок)
SETTINGS_FILE="$INSTALL_DIR/settings.txt"      # пользовательские настройки (КЛЮЧ=значение)

# --- Файл настроек -----------------------------------------------------------
# Finder Quick Action не умеет передавать env-переменные, поэтому те же ключи можно
# записать в settings.txt. Приоритет: env из командной строки > файл > умолчания ниже.
# Файл НЕ исполняется как shell: читаются только строки КЛЮЧ=значение с известными
# ключами (опечатка или мусор в файле не сломают запуск).
SETTING_KEYS="ENGINE MODEL TRANSCRIBE_LANG QUALITY VAD TIMESTAMPS READABLE PARA_GAP WRAP_WIDTH STRIP_FILLERS WHISPER_CLEANUP GIGAAM_DEVICE SPEAKERS"

write_settings_template() {  # создаёт шаблон, если файла ещё нет (существующий не трогаем)
    [ -e "$SETTINGS_FILE" ] && return 0
    mkdir -p "$INSTALL_DIR" 2>/dev/null || return 1
    cat > "$SETTINGS_FILE" <<'SETTINGS_EOF'
# Настройки Transcribe. Читаются при каждом запуске — и из Finder, и из командной строки.
# Формат: КЛЮЧ=значение, по одной настройке в строке. Строки с # в начале — комментарии.
# Чтобы включить настройку, уберите # перед ней и поставьте нужное значение.
# Переменные окружения, заданные в командной строке, важнее этого файла.

# Какими сетями распознавать: auto (обе, если GigaAM установлен) | whisper | gigaam | both
#ENGINE=auto

# Язык для Whisper: auto (автоопределение) | ru | en | … GigaAM всегда русский.
#TRANSCRIBE_LANG=auto

# Модель Whisper: large | turbo (turbo ~3× быстрее; нужна скачанная turbo-модель)
#MODEL=large

# Качество Whisper: fast | balanced | max (max точнее, но в 2–4 раза медленнее)
#QUALITY=balanced

# Таймкоды [ЧЧ:ММ:СС] в тексте: 0 | 1
#TIMESTAMPS=0

# Кто говорит — подписи «Спикер 1:», «Спикер 2:» (нужна установка с WITH_GIGAAM=1):
# 0 — выкл | auto — число спикеров определить самому | 2, 3, … — точное число (надёжнее)
#SPEAKERS=0

# Разбивка на абзацы по паузам и перенос длинных строк: 0 | 1
#READABLE=0
# Пауза (сек) между репликами, после которой начинается новый абзац, и ширина строки
#PARA_GAP=2.0
#WRAP_WIDTH=90

# VAD для Whisper — отсекать выдуманный текст в тишине: auto (если модель скачана) | 1 | 0
#VAD=auto

# Убрать междометия «э-э», «а-а», «м-м» из расшифровки: 0 | 1
#STRIP_FILLERS=0

# Убирать титры-галлюцинации Whisper («Редактор субтитров…») и повторы строк: 0 | 1
# Удалённые титры пишутся рядом в «<имя>.filtered.txt» — для сверки.
#WHISPER_CLEANUP=1

# Где считать GigaAM: auto (GPU с откатом на CPU) | mps | cpu
#GIGAAM_DEVICE=auto
SETTINGS_EOF
}

load_settings() {  # КЛЮЧ=значение построчно; только известные ключи; env важнее файла
    local line key val
    [ -f "$SETTINGS_FILE" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*([A-Za-z_]+)[[:space:]]*=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        val="${val%%#*}"                          # комментарий после значения
        val="${val#"${val%%[![:space:]]*}"}"      # пробелы слева
        val="${val%"${val##*[![:space:]]}"}"      # пробелы справа
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        case " $SETTING_KEYS " in *" $key "*) ;; *) continue ;; esac
        if [ -z "$(eval "printf '%s' \"\${$key+x}\"")" ]; then   # не задано в env → берём из файла
            eval "$key=\"\$val\""
        fi
    done < "$SETTINGS_FILE"
}

if [ "$INPUT_FILE" = "--init-settings" ]; then
    write_settings_template && printf '%s\n' "$SETTINGS_FILE"
    exit $?
fi
write_settings_template 2>/dev/null || true
load_settings

# --- Конфигурация (env-переменные или settings.txt) --------------------------
# FEAT-6: движок распознавания. whisper | gigaam | both | auto (по умолчанию).
#   auto = обе сети, если GigaAM установлен (install.sh с WITH_GIGAAM=1) и язык
#   auto/ru (GigaAM v3 — только русский); иначе только Whisper.
ENGINE="${ENGINE:-auto}"
# Модель Whisper: large (large-v3, по умолчанию) или turbo (large-v3-turbo — ~3× быстрее,
#         качество сопоставимое; нужна скачанная turbo-модель).
MODEL="${MODEL:-large}"
# RU-1: язык Whisper. auto (по умолчанию) = автоопределение (~100 языков); ru/en/… —
#       зафиксировать (убирает ложные детекты на коротких/шумных фразах, чуть быстрее
#       старт). GigaAM всегда русский: при auto он тоже запускается (ENGINE=auto).
LANG_CODE="${TRANSCRIBE_LANG:-auto}"
# RU-2: профиль качества Whisper. max — точнее, но в 2–4× медленнее; fast — жадный поиск.
#       Самообучающийся множитель времени подстроится сам.
QUALITY="${QUALITY:-balanced}"
# RU-3: VAD против галлюцинаций в тишине/паузах. auto = включить, если VAD-модель
#       скачана (ставится установщиком); 1 = принудительно; 0 = выключить. Только Whisper:
#       GigaAM режет речь своим VAD (Silero) всегда.
USE_VAD="${VAD:-auto}"
VAD_MODEL_PATH="$INSTALL_DIR/models/ggml-silero-v5.1.2.bin"
# FEAT-1: TIMESTAMPS=1 — вставить таймкоды [ЧЧ:ММ:СС] прямо в расшифровку (оба движка).
USE_TIMESTAMPS="${TIMESTAMPS:-0}"
# FEAT-3: READABLE=1 — разбивка на абзацы по паузам + перенос длинных строк (оба движка).
USE_READABLE="${READABLE:-0}"
PARA_GAP="${PARA_GAP:-2.0}"   # пауза (сек) между репликами → новый абзац
WRAP_WIDTH="${WRAP_WIDTH:-90}" # ширина переноса строк для читаемого режима
# STRIP_FILLERS=1 — убрать междометия-растяжки «э-э», «а-а», «м-м» (GigaAM пишет их
#   дословно, Whisper — изредка). Оба движка.
STRIP_FILLERS="${STRIP_FILLERS:-0}"
# WHISPER_CLEANUP=1 (по умолчанию) — убрать известные галлюцинации Whisper: титры из
#   обучающих субтитров («Редактор субтитров…», «Продолжение следует», «Спасибо за
#   просмотр»), которые он дописывает на тишине или в конце записи, и схлопнуть
#   одинаковые строки подряд (петли). Удалённые титры — рядом в «<имя>.filtered.txt»
#   для сверки. Только Whisper. FILTER=0 — прежнее имя выключателя, тоже работает.
WHISPER_CLEANUP="${WHISPER_CLEANUP:-${FILTER:-1}}"
# GigaAM: устройство auto | mps | cpu (auto = Metal/MPS на Apple Silicon с откатом на CPU).
GIGAAM_DEVICE="${GIGAAM_DEVICE:-auto}"
GIGAAM_PY="$INSTALL_DIR/gigaam/venv/bin/python"
GIGAAM_RUNNER="$INSTALL_DIR/bin/gigaam_transcribe.py"
GIGAAM_MODELS_DIR="$INSTALL_DIR/models/gigaam"
GIGAAM_STATE_FILE="$INSTALL_DIR/last_speed_factor_gigaam"
GIGAAM_SEED_FACTOR="8.0"
GIGAAM_LABEL="GigaAM v3 E2E-RNN-T"
# FEAT-5: SPEAKERS — разметка по спикерам (диаризация). 0 — выкл (по умолчанию);
#   auto — число спикеров определяется само; N — точное число (надёжнее, если известно).
#   Работает в Python-окружении GigaAM (sherpa-onnx + модели pyannote-3.0/WeSpeaker).
SPEAKERS="${SPEAKERS:-0}"
DIARIZE_RUNNER="$INSTALL_DIR/bin/diarize.py"
DIARIZE_MODELS_DIR="$INSTALL_DIR/models/diarization"

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
# Расширение входит в имя результата (meeting.mp4 → meeting.mp4.whisper.txt): иначе
# meeting.mp3 и meeting.mp4 дали бы один результат (второй затёр бы первый),
# и легко затереть заметки пользователя meeting.txt. См. BACKLOG BUG-1.
# Суффикс движка — по аналогии с .gigaam.txt: сразу видно, какая сеть писала файл.
OUTPUT_NAME="${INPUT_NAME}.whisper.txt"          # результат Whisper
OUTPUT_TXT="$INPUT_DIR/${OUTPUT_NAME}"
GIGAAM_OUTPUT_NAME="${INPUT_NAME}.gigaam.txt"    # результат GigaAM
GIGAAM_OUTPUT_TXT="$INPUT_DIR/${GIGAAM_OUTPUT_NAME}"
PROGRESS_TXT="$INPUT_DIR/${INPUT_NAME}.InProgress.txt"

# --- Выбор движков -----------------------------------------------------------
gigaam_available() { [ -x "$GIGAAM_PY" ] && [ -f "$GIGAAM_RUNNER" ]; }

RUN_WHISPER=1; RUN_GIGAAM=0
case "$ENGINE" in
    whisper) ;;
    gigaam)  RUN_WHISPER=0; RUN_GIGAAM=1 ;;
    both)    RUN_GIGAAM=1 ;;
    *)       ENGINE="auto"
             if gigaam_available && { [ "$LANG_CODE" = "auto" ] || [ "$LANG_CODE" = "ru" ]; }; then
                 RUN_GIGAAM=1
             fi ;;
esac
if [ "$RUN_GIGAAM" = "1" ] && ! gigaam_available; then
    if [ "$RUN_WHISPER" = "1" ]; then
        notify "Transcribe" "GigaAM не установлен — только Whisper (установка: WITH_GIGAAM=1)"
        RUN_GIGAAM=0
    else
        notify "Ошибка транскрибации" "GigaAM не установлен: запустите install.sh с WITH_GIGAAM=1"
        exit 1
    fi
fi

# --- Спикеры (FEAT-5) --------------------------------------------------------
diarize_available() {
    [ -x "$GIGAAM_PY" ] && [ -f "$DIARIZE_RUNNER" ] \
        && [ -f "$DIARIZE_MODELS_DIR/segmentation-3.0.onnx" ] \
        && [ -f "$DIARIZE_MODELS_DIR/wespeaker_en_voxceleb_resnet34_LM.onnx" ]
}
RUN_DIARIZE=0
case "$SPEAKERS" in
    0|"") ;;
    *) if diarize_available; then
           RUN_DIARIZE=1
       else
           notify "Transcribe" "Разметка спикеров не установлена — без спикеров (установка: WITH_GIGAAM=1)"
       fi ;;
esac

# --- Выбор и поиск модели Whisper (переиспользуем уже скачанную) --------------
case "$MODEL" in
    turbo) MODEL_FILE="ggml-large-v3-turbo.bin"; MODEL_LABEL="Whisper Large-v3-turbo" ;;
    *)     MODEL="large"; MODEL_FILE="ggml-large-v3.bin"; MODEL_LABEL="Whisper Large-v3" ;;
esac
find_model() {  # печатает путь к файлу-модели $1, если найден
    for d in "$INSTALL_DIR/models" "$HOME/.cache/whisper"; do
        [ -f "$d/$1" ] && { printf '%s\n' "$d/$1"; return 0; }
    done
    return 1
}
if [ "$RUN_WHISPER" = "1" ]; then
    MODEL_PATH="$(find_model "$MODEL_FILE")"
    # turbo запрошена, но не скачана → откатываемся на large, чтобы не падать.
    if [ -z "$MODEL_PATH" ] && [ "$MODEL" = "turbo" ]; then
        MODEL_PATH="$(find_model ggml-large-v3.bin)"
        if [ -n "$MODEL_PATH" ]; then
            MODEL_LABEL="Whisper Large-v3"
            notify "Transcribe" "turbo-модель не найдена — использую large-v3"
        fi
    fi
    if [ -z "$MODEL_PATH" ]; then
        notify "Ошибка транскрибации" "AI-модель $MODEL_FILE не найдена"
        exit 1
    fi
fi

# --- Поиск бинарников --------------------------------------------------------
WHISPER_BIN="$(command -v whisper-cli 2>/dev/null)"
if [ -z "$WHISPER_BIN" ]; then
    WHISPER_BIN="$(find /opt/homebrew/Cellar/whisper-cpp -name whisper-cli -type f 2>/dev/null | head -n 1)"
fi
# vad-speech-segments идёт в комплекте whisper-cpp — нужен для выравнивания таймкодов.
VAD_SEG_BIN="$(command -v vad-speech-segments 2>/dev/null)"
[ -z "$VAD_SEG_BIN" ] && [ -n "$WHISPER_BIN" ] && [ -x "$(dirname "$WHISPER_BIN")/vad-speech-segments" ] \
    && VAD_SEG_BIN="$(dirname "$WHISPER_BIN")/vad-speech-segments"
FFMPEG_BIN="$(command -v ffmpeg 2>/dev/null)"
FFPROBE_BIN="$(command -v ffprobe 2>/dev/null)"
if [ "$RUN_WHISPER" = "1" ] && { [ -z "$WHISPER_BIN" ] || [ ! -x "$WHISPER_BIN" ]; }; then
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
TEMP_WHISPER="$TEMP_DIR/transcribe_$$_whisper"   # база временных файлов Whisper (.txt/.srt/.body/.removed)
TEMP_GIGAAM="$TEMP_DIR/transcribe_$$_gigaam"     # база временных файлов GigaAM (.txt/.srt/.body/.meta)
TEMP_TURNS="$TEMP_DIR/transcribe_$$.turns"       # диаризация: начало<TAB>конец<TAB>спикер
cleanup() {
    rm -f "$TEMP_AUDIO" "$TEMP_TURNS"
    for b in "$TEMP_WHISPER" "$TEMP_GIGAAM"; do rm -f "$b.txt" "$b.srt" "$b.body" "$b.meta" "$b.removed" "$b.vad"; done
}
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

# --- Оценка времени (самообучающийся множитель скорости, свой у каждого движка) ---
read_factor() {  # печатает выученный множитель из файла $1, иначе стартовый $2
    local v
    if [ -f "$1" ]; then
        v=$(cat "$1" 2>/dev/null)
        if awk -v x="$v" 'BEGIN{exit !(x+0>0)}'; then printf '%s\n' "$v"; return; fi
    fi
    printf '%s\n' "$2"
}
est_secs() {  # $1 длительность, $2 множитель → секунды обработки (не меньше 1)
    awk -v d="$1" -v f="$2" 'BEGIN{ if(f<=0)f=4; s=int((d/f)+0.5); if(s<1)s=1; print s }'
}
update_factor() {  # $1 файл состояния, $2 длительность, $3 реальное время — учим множитель (файлы от 60 с)
    { [ "$2" -ge 60 ] && [ "$3" -gt 0 ]; } || return 0
    local raw old
    raw=$(awk -v d="$2" -v e="$3" 'BEGIN{printf "%.3f", d/e}')
    old=""
    [ -f "$1" ] && old=$(cat "$1" 2>/dev/null)
    if [ -n "$old" ] && awk -v o="$old" -v r="$raw" 'BEGIN{exit !(o+0>0 && r+0>0 && r < o/3)}'; then
        : # Аномально медленный замер (в 3+ раза ниже выученного) — почти наверняка
          # сон/прерывание во время распознавания. Не обновляем, чтобы не испортить оценку.
    elif [ -n "$old" ] && awk -v o="$old" 'BEGIN{exit !(o+0>0)}'; then
        awk -v o="$old" -v n="$raw" 'BEGIN{printf "%.3f", 0.5*o+0.5*n}' > "$1" 2>/dev/null || true
    else
        echo "$raw" > "$1" 2>/dev/null || true
    fi
}

EST_WHISPER=0; EST_GIGAAM=0
[ "$RUN_WHISPER" = "1" ] && EST_WHISPER=$(est_secs "$DUR_INT" "$(read_factor "$STATE_FILE" "$SEED_FACTOR")")
[ "$RUN_GIGAAM" = "1" ]  && EST_GIGAAM=$(est_secs "$DUR_INT" "$(read_factor "$GIGAAM_STATE_FILE" "$GIGAAM_SEED_FACTOR")")
EST_DIARIZE=0
[ "$RUN_DIARIZE" = "1" ] && EST_DIARIZE=$(est_secs "$DUR_INT" 20)   # ~20× realtime на Apple Silicon
EST_SECS=$((EST_WHISPER + EST_GIGAAM + EST_DIARIZE))
EST_FMT=$(fmt_hms "$EST_SECS")

START_EPOCH=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
FINISH_HUMAN=$(date -r $((START_EPOCH + EST_SECS)) '+%Y-%m-%d %H:%M:%S')

# Подписи для индикатора/уведомлений: какие движки и какие файлы ждать.
ENGINES_LABEL=""; EXPECTED_FILES=""
if [ "$RUN_WHISPER" = "1" ]; then ENGINES_LABEL="$MODEL_LABEL"; EXPECTED_FILES="«${OUTPUT_NAME}»"; fi
if [ "$RUN_GIGAAM" = "1" ]; then
    ENGINES_LABEL="${ENGINES_LABEL:+$ENGINES_LABEL + }$GIGAAM_LABEL"
    EXPECTED_FILES="${EXPECTED_FILES:+$EXPECTED_FILES и }«${GIGAAM_OUTPUT_NAME}»"
fi
[ "$RUN_DIARIZE" = "1" ] && ENGINES_LABEL="$ENGINES_LABEL + спикеры"

# --- Файл-индикатор "идёт транскрибация" -------------------------------------
{
    echo "$INPUT_NAME"
    echo "Старт транскрибации: $START_HUMAN"
    echo "Длительность аудио: $DURATION_FMT"
    echo "Модели: $ENGINES_LABEL"
    echo "Примерное время транскрибации: $EST_FMT"
    echo "Примерное время завершения транскрибации: $FINISH_HUMAN"
    echo ""
    echo "Идёт распознавание…"
    echo "Когда закончится, рядом появится $EXPECTED_FILES, а этот файл исчезнет."
} > "$PROGRESS_TXT" 2>/dev/null

notify "Transcribe" "Начинаю: $INPUT_NAME — примерно $EST_FMT ($ENGINES_LABEL)" "Glass"

# --- Сборка аргументов whisper -----------------------------------------------
# --max-context 0: НЕ переносить предыдущий текст между сегментами. Conditioning
# на прошлый текст вызывает самоподдерживающиеся петли-галлюцинации на длинных
# записях (одна фраза повторяется десятки раз и затирает реальную речь). Связность
# терминов чуть ниже, но это несопоставимо с потерей куска расшифровки.
case "$QUALITY" in
    max)  QUALITY_ARGS=(--beam-size 8 --best-of 8 --entropy-thold 2.4 --max-context 0) ;;
    fast) QUALITY_ARGS=(--beam-size 1 --best-of 1 --max-context 0) ;;
    *)    QUALITY_ARGS=(--beam-size 5 --best-of 5 --entropy-thold 2.4 --max-context 0) ;;  # balanced
esac

VAD_ARGS=()
if [ "$USE_VAD" != "0" ] && [ "$RUN_WHISPER" = "1" ]; then
    if [ -f "$VAD_MODEL_PATH" ]; then
        VAD_ARGS=(--vad --vad-model "$VAD_MODEL_PATH")
    elif [ "$USE_VAD" = "1" ]; then
        notify "Transcribe" "VAD-модель не найдена — продолжаю без VAD"
    fi
fi

# .srt нужен и для таймкодов (FEAT-1), и для разбивки на абзацы по паузам (FEAT-3).
TS_ARGS=(); GIGAAM_SRT_ARGS=()
if [ "$USE_TIMESTAMPS" = "1" ] || [ "$USE_READABLE" = "1" ] || [ "$RUN_DIARIZE" = "1" ]; then
    TS_ARGS=(--output-srt)
    GIGAAM_SRT_ARGS=(--srt)
fi

# caffeinate -i не даёт системе уснуть в простое во время распознавания: иначе
# на длинной записи сон приостанавливает процесс и ломает замер времени.
CAFFEINATE=()
command -v caffeinate >/dev/null 2>&1 && CAFFEINATE=(caffeinate -i)

mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="$TEMP_DIR"

# --- Пингер прогресса: читает вывод движка, шлёт уведомления на 25/50/75% -----
pipe_progress() {  # $1 — подпись движка; $2 — файл лога (весь вывод движка)
    local last=0 line p
    while IFS= read -r line; do
        printf '%s\n' "$line" >> "$2"
        if [[ "$line" =~ progress[[:space:]]*=[[:space:]]*([0-9]+) ]]; then
            p="${BASH_REMATCH[1]}"
            if   [ "$p" -ge 75 ] && [ "$last" -lt 75 ]; then notify "Transcribe" "$1… 75%"; last=75
            elif [ "$p" -ge 50 ] && [ "$last" -lt 50 ]; then notify "Transcribe" "$1… 50%"; last=50
            elif [ "$p" -ge 25 ] && [ "$last" -lt 25 ]; then notify "Transcribe" "$1… 25%"; last=25
            fi
        fi
    done
}

# --- Движки ------------------------------------------------------------------
run_whisper() {  # результат в "$TEMP_WHISPER.txt" (+ .srt); код 0 = успех
    : > "$LOG_DIR/last_whisper.log"
    "${CAFFEINATE[@]}" "$WHISPER_BIN" \
        -m "$MODEL_PATH" \
        -f "$TEMP_AUDIO" \
        -l "$LANG_CODE" \
        "${QUALITY_ARGS[@]}" \
        "${VAD_ARGS[@]}" \
        "${TS_ARGS[@]}" \
        --suppress-nst \
        --print-progress \
        --output-txt \
        --output-file "$TEMP_WHISPER" 2>&1 | pipe_progress "Whisper" "$LOG_DIR/last_whisper.log"
    local st=${PIPESTATUS[0]}
    [ "$st" -eq 0 ] && [ -f "${TEMP_WHISPER}.txt" ]
}

run_gigaam() {  # результат в "$TEMP_GIGAAM.txt" (+ .srt, .meta); код 0 = успех
    : > "$LOG_DIR/last_gigaam.log"
    "${CAFFEINATE[@]}" "$GIGAAM_PY" "$GIGAAM_RUNNER" \
        --wav "$TEMP_AUDIO" \
        --out "$TEMP_GIGAAM" \
        --models-dir "$GIGAAM_MODELS_DIR" \
        --device "$GIGAAM_DEVICE" \
        "${GIGAAM_TURNS_ARGS[@]}" \
        "${GIGAAM_SRT_ARGS[@]}" 2>&1 | pipe_progress "GigaAM" "$LOG_DIR/last_gigaam.log"
    local st=${PIPESTATUS[0]}
    [ "$st" -eq 0 ] && [ -f "${TEMP_GIGAAM}.txt" ]
}

run_diarize() {  # результат в "$TEMP_TURNS"; код 0 = успех
    : > "$LOG_DIR/last_diarize.log"
    "${CAFFEINATE[@]}" "$GIGAAM_PY" "$DIARIZE_RUNNER" \
        --wav "$TEMP_AUDIO" \
        --out "$TEMP_TURNS" \
        --models-dir "$DIARIZE_MODELS_DIR" \
        --speakers "$SPEAKERS" 2>&1 | pipe_progress "Спикеры" "$LOG_DIR/last_diarize.log"
    local st=${PIPESTATUS[0]}
    [ "$st" -eq 0 ] && [ -s "$TEMP_TURNS" ]
}

# --- Пост-обработка вывода движка (.txt и .srt на месте) ---------------------
# Междометия (STRIP_FILLERS) и галлюцинации Whisper (WHISPER_CLEANUP). На python3:
# sed/awk на macOS считают байты и не дружат с кириллицей. Аргументы:
# база временных файлов, движок, STRIP_FILLERS, WHISPER_CLEANUP.
postprocess() {
    if [ "$STRIP_FILLERS" != "1" ] && { [ "$2" != "whisper" ] || [ "$WHISPER_CLEANUP" != "1" ]; }; then
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || return 0
    python3 - "$1" "$2" "$STRIP_FILLERS" "$WHISPER_CLEANUP" <<'PY' 2>/dev/null || true
import os, re, sys

base, engine = sys.argv[1], sys.argv[2]
strip_fillers = sys.argv[3] == "1"
cleanup = sys.argv[4] == "1" and engine == "whisper"

# Междометия-растяжки, как их пишет GigaAM: «э-э», «а-а-а», «м-м», «и-и-и».
FILLER = re.compile(r"(?<![\w-])[аэоуыиеёмнАЭОУЫИЕЁМН](?:-[аэоуыиеёмн])+(?![\w-])")
# Титры и призывы из обучающих субтитров — Whisper дописывает их на тишине/в конце.
JUNK = re.compile(
    r"(редактор субтитров|корректор [а-яё]\.|субтитры\s+(сделал|создал|создавал|подготовил|делал|предоставил[аи]?|от|по)\b"
    r"|продолжение следует|спасибо за просмотр|подписывайтесь на|ставьте лайк"
    r"|subtitles by|thanks for watching|thank you for watching|amara\.org|dimatorzok)", re.I)

# После «, э-э, » запятую оставляем только перед союзом/союзным словом («помним, э-э, что» →
# «помним, что»); иначе обе запятые — от междометия («расхождения, м-м, по» → «расхождения по»).
KEEP_COMMA = {"что", "чтобы", "который", "которая", "которое", "которые", "где", "когда", "если",
              "потому", "поскольку", "хотя", "но", "а", "то", "как", "чем", "зачем", "почему",
              "куда", "откуда", "пока", "так"}
ENCLOSED = re.compile(r",\s*" + FILLER.pattern + r"\s*,\s*(?=(\S+))")

def strip_fill(text):
    lead = FILLER.match(text.lstrip())
    lead_upper = bool(lead) and lead.group(0)[0].isupper()
    out = ENCLOSED.sub(lambda m: ", " if m.group(1).lower().strip(",.!?;:") in KEEP_COMMA else " ", text)
    out = FILLER.sub("", out)
    out = re.sub(r",\s*,", ",", out)               # «новый, , реквизит» → «новый, реквизит»
    out = re.sub(r"\s+([,.!?…;:])", r"\1", out)    # пробел перед знаком препинания
    out = re.sub(r"[ \t]{2,}", " ", out).strip()
    out = re.sub(r"^[,;:\s]+", "", out)
    if lead_upper and out[:1].islower():           # междометие открывало фразу → заглавная
        out = out[0].upper() + out[1:]
    return out

def is_junk(text):
    return bool(JUNK.search(text)) and len(text.split()) <= 12

class Filter:
    def __init__(self, removed=None):
        self.prev = None
        self.removed = removed  # сюда складываем выброшенные титры (для .filtered.txt)
    def __call__(self, text):
        """Возвращает очищенный текст или None, если реплику надо выбросить."""
        if strip_fillers:
            text = strip_fill(text)
        if not re.search(r"\w", text):                # пусто или одни знаки («Э-э.» → «.»)
            return None
        if cleanup:
            if is_junk(text):
                if self.removed is not None:
                    self.removed.append(text)
                return None
            key = re.sub(r"\W+", " ", text).strip().lower()
            if key and key == self.prev:           # петля-галлюцинация: одна строка подряд
                return None
            self.prev = key
        return text

txt = base + ".txt"
if os.path.exists(txt):
    with open(txt, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    removed = []
    flt = Filter(removed)
    kept = [t for t in (flt(l) for l in lines) if t is not None]
    with open(txt, "w", encoding="utf-8") as f:
        f.write("\n".join(kept) + ("\n" if kept else ""))
    if removed:
        with open(base + ".removed", "w", encoding="utf-8") as f:
            f.write("\n".join(removed) + "\n")

srt = base + ".srt"
if os.path.exists(srt):
    with open(srt, encoding="utf-8", errors="replace") as f:
        content = f.read().strip()
    flt, kept = Filter(), []
    for block in re.split(r"\r?\n\r?\n", content):
        ls = block.splitlines()
        ti = next((i for i, l in enumerate(ls) if "-->" in l), None)
        if ti is None:
            continue
        text = flt(" ".join(x.strip() for x in ls[ti + 1:] if x.strip()))
        if text is not None:
            kept.append((ls[ti].strip(), text))
    with open(srt, "w", encoding="utf-8") as f:
        for n, (timing, text) in enumerate(kept, 1):
            f.write("%d\n%s\n%s\n\n" % (n, timing, text))
PY
}

# --- Выравнивание таймкодов Whisper по реальной речи ---------------------------
# whisper.cpp (1.8, и с VAD, и без) выдаёт сегменты встык: начало реплики = конец
# предыдущей, поэтому пауза «приклеивается» к следующей фразе — её таймкод раньше
# реального на длину паузы (на тесте с паузами 2.7 с: [00:00:05] вместо 7.9 с), а
# READABLE не видит пауз и не делит на абзацы. Лечим: берём границы речи от Silero
# VAD (vad-speech-segments, та же модель) и сдвигаем начало реплики на первое
# начало речи внутри неё, конец — на последний конец речи. Ничего не найдено —
# таймкод остаётся как был. Нет модели/утилиты/python3 — шаг пропускается.
align_srt_to_speech() {  # $1 — база временных файлов Whisper
    [ -f "$1.srt" ] && [ -f "$VAD_MODEL_PATH" ] && [ -n "$VAD_SEG_BIN" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    "$VAD_SEG_BIN" -f "$TEMP_AUDIO" --vad-model "$VAD_MODEL_PATH" -np 2>/dev/null > "$1.vad" || return 0
    python3 - "$1.srt" "$1.vad" <<'PY' 2>/dev/null || true
import re, sys

srt_path, vad_path = sys.argv[1], sys.argv[2]
# «Speech segment N: start = 179.00, end = 528.00» — единицы 10 мс (как t0/t1 в whisper.cpp).
speech = [(float(a) / 100, float(b) / 100) for a, b in
          re.findall(r"start\s*=\s*([\d.]+),\s*end\s*=\s*([\d.]+)", open(vad_path).read())]
if not speech:
    sys.exit(0)

def tosec(t):
    h, m, rest = t.strip().split(":")
    return int(h) * 3600 + int(m) * 60 + float(rest.replace(",", "."))

def fmt(sec):
    ms = int(round(sec * 1000))
    h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)

cues = []
for block in re.split(r"\r?\n\r?\n", open(srt_path, encoding="utf-8", errors="replace").read().strip()):
    ls = block.splitlines()
    ti = next((i for i, l in enumerate(ls) if "-->" in l), None)
    if ti is None:
        continue
    a, b = ls[ti].split("-->")
    cues.append([tosec(a), tosec(b), ls[ti + 1:]])

TAIL = 0.6  # речь, заканчивающаяся в первые 0.6 с реплики, — хвост предыдущей фразы

for c in cues:
    start, end = c[0], c[1]
    inside = [(s, e) for s, e in speech if s < end and e > start]
    if not inside:
        continue
    # Речь, начавшаяся до реплики, — либо её законное продолжение (оставляем начало),
    # либо короткий хвост предыдущей фразы: тогда начало — первое начало речи внутри.
    carry = [e for s, e in inside if s <= start]
    later = [s for s, _ in inside if s > start]
    if later and (not carry or max(carry) - start < TAIL):
        start = min(later)
        inside = [(s, e) for s, e in inside if s >= start]
    last_end = max(e for _, e in inside)
    if last_end < end:                                # хвост реплики — тишина → к концу речи
        end = last_end
    if start < end:
        c[0], c[1] = start, end

with open(srt_path, "w", encoding="utf-8") as f:
    for n, (s, e, text) in enumerate(cues, 1):
        f.write("%d\n%s --> %s\n%s\n\n" % (n, fmt(s), fmt(e), "\n".join(text)))
PY
    rm -f "$1.vad"
}

# --- Тело расшифровки --------------------------------------------------------
# FEAT-3: читаемый режим — абзацы по паузам + перенос строк. На python3, потому
# что awk/fold на macOS считают байты и рвут кириллицу (UTF-8). Аргументы:
# PARA_GAP WRAP_WIDTH USE_TIMESTAMPS SRT.
format_readable() {  # $1 — путь к .srt
    python3 - "$PARA_GAP" "$WRAP_WIDTH" "$USE_TIMESTAMPS" "$1" <<'PY'
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

# Страховка от петель-галлюцинаций: схлопываем подряд идущие идентичные реплики.
deduped = []
for c in cues:
    if deduped and deduped[-1][3].strip().lower() == c[3].strip().lower():
        continue
    deduped.append(c)
cues = deduped

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

# FEAT-5: расшифровка по спикерам. Каждой реплике .srt назначается спикер с наибольшим
# перекрытием по времени (диаризация одна на оба движка); подряд идущие реплики одного
# спикера — один абзац «Спикер N: …», новый абзац также после паузы > PARA_GAP.
# С TIMESTAMPS — таймкод в начале абзаца, с READABLE — перенос строк. Аргументы:
# PARA_GAP WRAP_WIDTH USE_TIMESTAMPS USE_READABLE SRT TURNS.
format_speakers() {  # $1 — путь к .srt
    python3 - "$PARA_GAP" "$WRAP_WIDTH" "$USE_TIMESTAMPS" "$USE_READABLE" "$1" "$TEMP_TURNS" <<'PY'
import re, sys, textwrap

gap, width = float(sys.argv[1]), int(sys.argv[2])
want_ts, readable = sys.argv[3] == "1", sys.argv[4] == "1"
srt_path, turns_path = sys.argv[5], sys.argv[6]

def tosec(t):
    h, m, rest = t.strip().split()[0].split(":")
    return int(h) * 3600 + int(m) * 60 + float(rest.replace(",", "."))

turns = []
for line in open(turns_path, encoding="utf-8"):
    p = line.split("\t")
    if len(p) >= 3:
        turns.append((float(p[0]), float(p[1]), p[2].strip()))

cues = []
for block in re.split(r"\r?\n\r?\n", open(srt_path, encoding="utf-8", errors="replace").read().strip()):
    ls = block.splitlines()
    ti = next((i for i, l in enumerate(ls) if "-->" in l), None)
    if ti is None:
        continue
    a, b = ls[ti].split("-->")
    text = " ".join(x.strip() for x in ls[ti + 1:] if x.strip())
    if text:
        cues.append((tosec(a), tosec(b), text))

def speaker_of(start, end, prev):
    best, best_ov = None, 0.0
    for s, e, spk in turns:
        ov = min(end, e) - max(start, s)
        if ov > best_ov:
            best, best_ov = spk, ov
    if best is None:  # реплика в «дыре» диаризации — ближайший по времени спикер
        near = min(turns, key=lambda t: min(abs(t[0] - end), abs(t[1] - start)), default=None)
        best = near[2] if near else prev
    return best

paras, prev_spk, prev_end = [], None, None
for start, end, text in cues:
    spk = speaker_of(start, end, prev_spk)
    same = bool(paras) and spk == prev_spk
    if same and text.strip().lower() == paras[-1][2][-1].strip().lower():
        pass  # петля-галлюцинация: та же реплика подряд
    elif same and (start - prev_end) <= gap:
        paras[-1][2].append(text)
    else:
        paras.append((start, spk, [text]))
    prev_spk, prev_end = spk, end

def hms(sec):
    sec = int(sec)
    return "%02d:%02d:%02d" % (sec // 3600, (sec // 60) % 60, sec % 60)

out = []
for start, spk, texts in paras:
    prefix = ("[%s] " % hms(start) if want_ts else "") + ("Спикер %s: " % spk if spk else "")
    body = " ".join(texts)
    if readable:
        out.append(textwrap.fill(body, width=width, initial_indent=prefix,
                                 subsequent_indent=" " * (len(prefix) if want_ts else 0),
                                 break_long_words=False, break_on_hyphens=False))
        out.append("")
    else:
        out.append(prefix + body)
sys.stdout.write(("\n".join(out)).rstrip() + "\n")
PY
}

build_body() {  # $1 — база временных файлов движка; тело расшифровки → "$1.body"
    local srt="$1.srt" body="$1.body"
    if [ "$RUN_DIARIZE" = "1" ] && [ -s "$TEMP_TURNS" ] && [ -f "$srt" ] && command -v python3 >/dev/null 2>&1; then
        if format_speakers "$srt" > "$body" 2>/dev/null && [ -s "$body" ]; then
            return
        fi
    fi
    if [ "$USE_READABLE" = "1" ] && [ -f "$srt" ] && command -v python3 >/dev/null 2>&1; then
        if format_readable "$srt" > "$body" 2>/dev/null && [ -s "$body" ]; then
            return
        fi
    fi
    # FEAT-1: только таймкоды — строки «[ЧЧ:ММ:СС] текст».
    if [ "$USE_TIMESTAMPS" = "1" ] && [ -f "$srt" ]; then
        # prev — страховка от петель: подряд идущие идентичные реплики не дублируем.
        awk '
            function emit() { if (ts!="" && text!=prev) { print "[" ts "] " text; prev=text } ts=""; text="" }
            /-->/               { split($1, t, ","); ts=t[1]; text=""; next }
            /^[0-9]+\r?$/        { next }
            /^[[:space:]]*\r?$/  { emit(); next }
                                { sub(/\r$/,""); text=(text=="" ? $0 : text " " $0) }
            END                 { emit() }
        ' "$srt" > "$body"
        return
    fi
    # Обычная сплошная расшифровка. Схлопываем подряд идущие идентичные строки —
    # страховка от петель-галлюцинаций и в дефолтном (не-srt) выводе Quick Action,
    # где --max-context 0 остаётся единственной защитой. Сравнение по строке без
    # крайних пробелов; пустые строки пропускаем как есть.
    awk '{
            line=$0; key=line; gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == "" || key != prev) print line
            prev=key
         }' "$1.txt" > "$body"
    # Пустое тело (например, GigaAM не нашёл речи) — лучше явная пометка, чем пустой файл.
    [ -s "$body" ] || echo "(речь не обнаружена)" > "$body"
}

# Удалённые пост-обработкой титры-галлюцинации Whisper → «<имя>.filtered.txt» рядом с
# исходником, чтобы можно было убедиться, что реальная речь не пострадала.
# Выставляет FILTERED_NOTE — строку для шапки результата (пусто, если ничего не удалено).
write_filtered_report() {  # $1 — база временных файлов движка
    local n
    FILTERED_NOTE=""
    [ -s "$1.removed" ] || return 0
    n=$(grep -c . "$1.removed" 2>/dev/null); n=${n:-0}
    [ "$n" -gt 0 ] || return 0
    {
        echo "Отфильтровано как вероятные галлюцинации Whisper (титры/подписи на тишине)."
        echo "Исходный файл: $INPUT_NAME · Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Если среди строк ниже есть реальная речь — сообщите, поправим фильтр (WHISPER_CLEANUP=0 отключает)."
        echo "-----------------------------------------"
        cat "$1.removed"
    } > "$INPUT_DIR/${INPUT_NAME}.filtered.txt" 2>/dev/null
    FILTERED_NOTE="Отфильтровано служебных строк (титры): $n → ${INPUT_NAME}.filtered.txt"
}

write_result() {  # $1 база временных файлов, $2 итоговый файл, $3 подпись модели, $4 старт, $5 финиш, $6 длительность, [$7 $8 доп. строки шапки]
    build_body "$1"
    {
        echo "========================================="
        echo "Исходный файл: $INPUT_NAME"
        echo "Длительность аудио: $DURATION_FMT"
        echo "Старт транскрибации: $4"
        echo "Завершение транскрибации: $5"
        echo "Время транскрибации: $6"
        echo "Модель: $3"
        [ -n "${7:-}" ] && echo "$7"
        [ -n "${8:-}" ] && echo "$8"
        echo "========================================="
        echo ""
        cat "$1.body"
    } > "$2"
}

# --- Запуск движков по очереди (оба грузят GPU/CPU — параллельно только мешали бы) ---
FAILED=""; DONE_FILES=""; SPEAKERS_NOTE=""

# Диаризация — первой и один раз на оба движка: GigaAM режет чанки по смене спикера.
GIGAAM_TURNS_ARGS=()
if [ "$RUN_DIARIZE" = "1" ]; then
    if run_diarize; then
        N_SPK=$(cut -f3 "$TEMP_TURNS" | sort -u | grep -c .)
        SPEAKERS_NOTE="Спикеры: $N_SPK (SPEAKERS=$SPEAKERS; нумерация по порядку появления в записи)"
        GIGAAM_TURNS_ARGS=(--turns "$TEMP_TURNS")
    else
        RUN_DIARIZE=0
        notify "Transcribe" "Не удалось разметить спикеров — расшифровка без них (лог: $LOG_DIR)"
    fi
fi

if [ "$RUN_WHISPER" = "1" ]; then
    W_START_EPOCH=$(date +%s); W_START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
    if run_whisper; then
        W_ELAPSED=$(( $(date +%s) - W_START_EPOCH ))
        align_srt_to_speech "$TEMP_WHISPER"
        postprocess "$TEMP_WHISPER" whisper
        write_filtered_report "$TEMP_WHISPER"
        write_result "$TEMP_WHISPER" "$OUTPUT_TXT" \
            "$MODEL_LABEL (язык: $LANG_CODE, качество: $QUALITY)" \
            "$W_START_HUMAN" "$(date '+%Y-%m-%d %H:%M:%S')" "$(fmt_hms "$W_ELAPSED")" \
            "$FILTERED_NOTE" "$SPEAKERS_NOTE"
        update_factor "$STATE_FILE" "$DUR_INT" "$W_ELAPSED"
        DONE_FILES="«${OUTPUT_NAME}»"
        if [ "$RUN_GIGAAM" = "1" ]; then
            notify "Transcribe" "Whisper готов за $(fmt_hms "$W_ELAPSED") — теперь GigaAM (~$(fmt_hms "$EST_GIGAAM"))"
        fi
    else
        FAILED="Whisper"
    fi
fi

if [ "$RUN_GIGAAM" = "1" ]; then
    G_START_EPOCH=$(date +%s); G_START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
    if run_gigaam; then
        G_ELAPSED=$(( $(date +%s) - G_START_EPOCH ))
        postprocess "$TEMP_GIGAAM" gigaam
        G_DEVICE=$(sed -n 's/^device=//p' "${TEMP_GIGAAM}.meta" 2>/dev/null)
        write_result "$TEMP_GIGAAM" "$GIGAAM_OUTPUT_TXT" \
            "$GIGAAM_LABEL (язык: ru, устройство: ${G_DEVICE:-?})" \
            "$G_START_HUMAN" "$(date '+%Y-%m-%d %H:%M:%S')" "$(fmt_hms "$G_ELAPSED")" \
            "" "$SPEAKERS_NOTE"
        update_factor "$GIGAAM_STATE_FILE" "$DUR_INT" "$G_ELAPSED"
        DONE_FILES="${DONE_FILES:+$DONE_FILES, }«${GIGAAM_OUTPUT_NAME}»"
    else
        FAILED="${FAILED:+$FAILED, }GigaAM"
    fi
fi

ELAPSED=$(( $(date +%s) - START_EPOCH ))
ELAPSED_FMT=$(fmt_hms "$ELAPSED")

# --- Обработка ошибки --------------------------------------------------------
if [ -n "$FAILED" ]; then
    {
        echo "$INPUT_NAME"
        echo "Старт транскрибации: $START_HUMAN"
        echo "❌ Ошибка: не удалось завершить транскрибацию ($FAILED)."
        [ -n "$DONE_FILES" ] && echo "✅ Готово: $DONE_FILES"
        echo "Подробности: $LOG_DIR"
        echo "Попробуйте запустить ещё раз. Этот файл можно удалить."
    } > "$PROGRESS_TXT" 2>/dev/null
    notify "Ошибка транскрибации" "$FAILED: не удалось транскрибировать $INPUT_NAME" "Basso"
    exit 1
fi

# --- Удаляем файл-индикатор (best-effort) ------------------------------------
rm -f "$PROGRESS_TXT" 2>/dev/null || true

notify "Готово ✅" "Готово за ${ELAPSED_FMT}: ${DONE_FILES}" "Glass"
exit 0
