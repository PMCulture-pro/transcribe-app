#!/bin/bash

# Скрипт для транскрибации аудио с whisper-cpp
# Использование: ./transcribe.sh <input_audio> <output_text>

if [ $# -ne 2 ]; then
    echo "Использование: $0 <input_audio> <output_text>"
    echo "Пример: $0 audio.wav text.txt"
    exit 1
fi

INPUT_AUDIO="$1"
OUTPUT_TEXT="$2"

# Проверяем существование входного файла
if [ ! -f "$INPUT_AUDIO" ]; then
    echo "Ошибка: файл '$INPUT_AUDIO' не найден"
    exit 1
fi

# Получаем длину аудио файла
echo "Анализирую аудио файл..."
DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT_AUDIO" 2>/dev/null)
if [ -z "$DURATION" ]; then
    echo "Ошибка: не удалось определить длительность аудио"
    exit 1
fi

# Форматируем длительность в ЧЧ:ММ:СС
DURATION_FORMATTED=$(printf "%02d:%02d:%02d" $((${DURATION%.*}/3600)) $((${DURATION%.*}/60%60)) $((${DURATION%.*}/1%60)))

echo "Длительность аудио: $DURATION_FORMATTED"
echo "Начинаю транскрибацию..."

# Засекаем время начала
START_TIME=$(date +%s)

# Создаем временный файл для вывода whisper
TEMP_OUTPUT=$(mktemp)

# Запускаем whisper-cpp с подавлением вывода текста
/opt/homebrew/Cellar/whisper-cpp/1.8.0/libexec/bin/whisper-cli \
    -m "$HOME/.cache/whisper/ggml-large-v3.bin" \
    -f "$INPUT_AUDIO" \
    -l ru \
    --print-progress \
    --output-txt \
    --output-file "$TEMP_OUTPUT" 2>&1 | grep -E "(whisper_print_progress_callback|output_txt:|whisper_print_timings:)" || true

# Засекаем время окончания
END_TIME=$(date +%s)
TRANSCRIBE_TIME=$((END_TIME - START_TIME))
TRANSCRIBE_TIME_FORMATTED=$(printf "%02d:%02d:%02d" $((TRANSCRIBE_TIME/3600)) $((TRANSCRIBE_TIME/60%60)) $((TRANSCRIBE_TIME%60)))

echo "Транскрибация завершена за $TRANSCRIBE_TIME_FORMATTED"

# Создаем итоговый файл с метаданными
{
    echo "=== МЕТАДАННЫЕ ТРАНСКРИБАЦИИ ==="
    echo "Исходный файл: $(basename "$INPUT_AUDIO")"
    echo "Длительность аудио: $DURATION_FORMATTED"
    echo "Время транскрибации: $TRANSCRIBE_TIME_FORMATTED"
    echo "Дата транскрибации: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Модель: whisper-large-v3"
    echo "================================="
    echo ""
    echo "=== ТРАНСКРИПЦИЯ ==="
    echo ""
    
    # Добавляем содержимое транскрипции
    if [ -f "${TEMP_OUTPUT}.txt" ]; then
        cat "${TEMP_OUTPUT}.txt"
    else
        echo "Ошибка: файл транскрипции не найден"
    fi
} > "$OUTPUT_TEXT"

# Удаляем временные файлы
rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.txt"

echo "Результат сохранен в: $OUTPUT_TEXT"
echo "Готово!"
