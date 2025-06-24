#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # Без цвета

echo -e "${BLUE}========================================"
echo "ДЕМОНСТРАЦИЯ ЭВОЛЮЦИИ АРХИТЕКТУРЫ TWITTER"
echo "Проблема популярных пользователей"
echo "========================================${NC}"
echo ""
echo -e "${YELLOW}Модель данных:${NC}"
echo "- 1000 пользователей"
echo "- User1: популярный (500 подписчиков)"
echo "- User2: мега-популярный (2000 подписчиков)"
echo ""
echo "Проблема: время создания твита растет линейно"
echo "с количеством подписчиков!"
echo ""

# Результаты производительности для каждого шага
declare -A normal_times
declare -A popular_times
declare -A mega_times

# Ожидаемые результаты (в миллисекундах)
normal_times=(
    ["Step 1"]="5"
    ["Step 2"]="5"
    ["Step 3"]="5"
    ["Step 4"]="5"
    ["Step 5"]="5"
    ["Step 6"]="3"
)

popular_times=(
    ["Step 1"]="500"
    ["Step 2"]="500"
    ["Step 3"]="10"
    ["Step 4"]="10"
    ["Step 5"]="10"
    ["Step 6"]="5"
)

mega_times=(
    ["Step 1"]="2000"
    ["Step 2"]="2000"
    ["Step 3"]="15"
    ["Step 4"]="15"
    ["Step 5"]="15"
    ["Step 6"]="8"
)

echo -e "${CYAN}ЭВОЛЮЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ:${NC}"
echo ""
echo "                    Обычный | Популярный | Мега-популярный"
echo "                    (0 подп) | (500 подп) | (2000 подп)"
echo "----------------------------------------------------------------"

for step in "Step 1" "Step 2" "Step 3" "Step 4" "Step 5" "Step 6"; do
    normal=${normal_times[$step]}
    popular=${popular_times[$step]}
    mega=${mega_times[$step]}
    
    case $step in
        "Step 1")
            name="Базовая синхронная    "
            color=$RED
            ;;
        "Step 2")
            name="Подготовленные ленты  "
            color=$RED
            ;;
        "Step 3")
            name="Асинхронная обработка "
            color=$GREEN
            ;;
        "Step 4")
            name="Мульти-воркеры        "
            color=$GREEN
            ;;
        "Step 5")
            name="Балансировка нагрузки "
            color=$GREEN
            ;;
        "Step 6")
            name="Кэширование           "
            color=$CYAN
            ;;
    esac
    
    printf "${color}%-22s${NC} %6s мс | %8s мс | %10s мс\n" "$name" "$normal" "$popular" "$mega"
done

echo ""
echo -e "${YELLOW}КЛЮЧЕВЫЕ ВЫВОДЫ:${NC}"
echo ""
echo "1. ${RED}Шаги 1-2: ПРОБЛЕМА${NC}"
echo "   - Синхронное обновление всех лент"
echo "   - Линейная зависимость от подписчиков"
echo "   - 2000 подписчиков = 2 секунды задержки!"
echo ""
echo "2. ${GREEN}Шаги 3-5: РЕШЕНИЕ${NC}"
echo "   - Асинхронная обработка через RabbitMQ"
echo "   - Горизонтальное масштабирование"
echo "   - Время не зависит от количества подписчиков"
echo ""
echo "3. ${CYAN}Шаг 6: ОПТИМИЗАЦИЯ${NC}"
echo "   - Redis кэширование"
echo "   - Еще быстрее для всех типов пользователей"
echo ""

echo -e "${PURPLE}ЗАПУСК ДЕМОНСТРАЦИЙ:${NC}"
echo ""
echo "Быстрый тест одного шага:"
echo "  cd step1_basic && ./quick_demo.sh"
echo ""
echo "Полная демонстрация шага:"
echo "  cd step3_async_feed && ./run_demo.sh"
echo ""
echo "Сравнение всех шагов:"
echo "  ./performance_comparison.sh"
echo ""
echo "Чередование PostgreSQL/Citus:"
echo "  ./run_alternating_demos.sh"
echo ""

echo -e "${RED}ВАЖНО:${NC}"
echo "В реальном Twitter у знаменитостей МИЛЛИОНЫ подписчиков!"
echo "Без асинхронной обработки система была бы неработоспособна."