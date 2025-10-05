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

TOTAL_SIZE=0

# Проверяем размер установленных компонентов
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
        SIZE=$(brew info $pkg 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[MG]B' | head -1)
        echo "    • $pkg ($SIZE)"
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

