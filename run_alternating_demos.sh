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
echo "Демонстрация эволюции архитектуры Twitter"
echo "Чередование между Citus и PostgreSQL"
echo "С реалистичной моделью популярных пользователей"
echo "========================================${NC}"

# Функция для запуска демо с определённым типом БД
run_demo() {
    local step_dir=$1
    local db_type=$2
    local step_name=$3
    local step_num=$4
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ "$db_type" = "Citus" ]; then
        echo -e "${PURPLE}🐘 $step_name (с Citus распределённой PostgreSQL)${NC}"
    else
        echo -e "${CYAN}🗄️  $step_name (с одиночной PostgreSQL)${NC}"
    fi
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    cd $step_dir
    
    # Остановка всех запущенных контейнеров
    docker-compose -f docker-compose.yml down -v 2>/dev/null
    if [ -f "docker-compose.postgres.yml" ]; then
        docker-compose -f docker-compose.postgres.yml down -v 2>/dev/null
    fi
    
    # Использование подходящего docker-compose файла
    if [ "$db_type" = "Citus" ]; then
        export COMPOSE_FILE=docker-compose.yml
    else
        # Проверка существования отдельного файла для PostgreSQL
        if [ -f "docker-compose.postgres.yml" ]; then
            export COMPOSE_FILE=docker-compose.postgres.yml
        else
            # Для шагов 4-6 используем один файл для обеих БД
            export COMPOSE_FILE=docker-compose.yml
            echo "Примечание: Используется общий docker-compose.yml для $db_type"
        fi
    fi
    
    # Запуск сервисов
    echo -e "${GREEN}Запуск сервисов с $db_type...${NC}"
    docker-compose up -d
    
    # Ожидание готовности сервисов
    if [ "$db_type" = "Citus" ]; then
        echo "Ожидание готовности кластера Citus..."
        sleep 15
        # Инициализация Citus при необходимости
        if [ -f "./init_citus.sh" ]; then
            echo "Инициализация кластера Citus..."
            ./init_citus.sh
        fi
    else
        echo "Ожидание готовности PostgreSQL..."
        sleep 10
    fi
    
    # Запуск Python-скрипта для загрузки реалистичных данных
    echo -e "\n${GREEN}Загрузка реалистичных данных...${NC}"
    
    API_URL="http://localhost:800${step_num}/api"
    
    # Используем универсальный загрузчик
    python3 ../common/load_realistic_data.py \
        --url $API_URL \
        --users 500 \
        --popular 200 \
        --mega 400 \
        --no-measure
    
    # Тестирование производительности
    echo -e "\n${CYAN}Тестирование производительности с популярными пользователями:${NC}"
    
    # Тест создания твитов для разных типов пользователей
    echo -e "\nВремя создания твита:"
    
    # Обычный пользователь (мало подписчиков)
    echo -n "  Обычный пользователь (0 подписчиков): "
    total_time=0
    for i in {1..5}; do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 499" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Обычный твит $i от $db_type\"}" > /dev/null
        end=$(date +%s%N)
        duration=$(((end - start) / 1000000))
        total_time=$((total_time + duration))
    done
    avg_normal=$((total_time / 5))
    echo -e "${GREEN}${avg_normal}мс${NC}"
    
    # Популярный пользователь (200 подписчиков)
    echo -n "  Популярный (200 подписчиков): "
    total_time=0
    for i in {1..5}; do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 1" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Популярный твит $i от $db_type\"}" > /dev/null
        end=$(date +%s%N)
        duration=$(((end - start) / 1000000))
        total_time=$((total_time + duration))
    done
    avg_popular=$((total_time / 5))
    echo -e "${YELLOW}${avg_popular}мс (${avg_popular}x медленнее)${NC}"
    
    # Мега-популярный пользователь (400 подписчиков)
    echo -n "  Мега-популярный (400 подписчиков): "
    total_time=0
    for i in {1..5}; do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 2" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Мега твит $i от $db_type\"}" > /dev/null
        end=$(date +%s%N)
        duration=$(((end - start) / 1000000))
        total_time=$((total_time + duration))
    done
    avg_mega=$((total_time / 5))
    echo -e "${RED}${avg_mega}мс (${avg_mega}x медленнее)${NC}"
    
    # Ожидание асинхронной обработки для шагов 3+
    if [ $step_num -ge 3 ]; then
        echo -e "\nОжидание асинхронной обработки..."
        sleep 5
    fi
    
    # Тестирование чтения ленты
    echo -e "\nВремя чтения ленты:"
    
    # Обычный пользователь
    echo -n "  Обычный пользователь (~100 подписок): "
    start=$(date +%s%N)
    feed_data=$(curl -s $API_URL/feed/ -H "X-User-ID: 100")
    end=$(date +%s%N)
    duration1=$(((end - start) / 1000000))
    tweet_count=$(echo "$feed_data" | grep -o "tweet_id" | wc -l | tr -d ' ')
    echo -e "${GREEN}${duration1}мс (твитов: $tweet_count)${NC}"
    
    # Показ итоговой информации
    echo -e "\n${YELLOW}Итоги для $db_type:${NC}"
    echo "- Тип базы данных: $db_type"
    echo "- Обычный твит: ${avg_normal}мс"
    echo "- Популярный (200 подписчиков): ${avg_popular}мс"
    echo "- Мега-популярный (400 подписчиков): ${avg_mega}мс"
    echo "- Деградация производительности: до ${avg_mega}x"
    echo "- Чтение ленты: ${duration1}мс"
    
    if [ "$db_type" = "Citus" ]; then
        echo -e "\n${PURPLE}Специфичная информация Citus:${NC}"
        docker-compose exec -T citus_master psql -U user -d twitter_db -c "SELECT COUNT(*) as shards FROM pg_dist_shard;" 2>/dev/null || echo "Информация о шардах недоступна"
    fi
    
    # Проверка очередей для асинхронных шагов
    if [ $step_num -ge 3 ] && [ $step_num -le 5 ]; then
        echo -e "\n${CYAN}Статус очередей RabbitMQ:${NC}"
        docker-compose exec -T rabbitmq rabbitmqctl list_queues 2>/dev/null | grep feed_updates || echo "Очереди не найдены"
    fi
    
    # Остановка сервисов
    echo -e "\n${BLUE}Нажмите Enter для остановки этого демо и продолжения...${NC}"
    read
    docker-compose down -v
    
    cd ..
}

# Основное выполнение
echo ""
echo "Эта демонстрация покажет проблему популярных пользователей"
echo "и разницу в производительности между Citus и PostgreSQL"
echo "для каждого шага архитектуры."
echo ""
echo -e "${RED}Модель данных:${NC}"
echo "- 500 пользователей"
echo "- user1: популярный (200 подписчиков)"
echo "- user2: мега-популярный (400 подписчиков)"
echo "- Обычные пользователи: 50-200 подписок"
echo ""
read -p "Нажмите Enter для запуска последовательности демо..."

# Запуск конкретного шага или всех
if [ "$1" ]; then
    case $1 in
        1)
            run_demo "step1_basic" "PostgreSQL" "Шаг 1: Базовая архитектура" 1
            run_demo "step1_basic" "Citus" "Шаг 1: Базовая архитектура" 1
            ;;
        2)
            run_demo "step2_prepared_feed" "PostgreSQL" "Шаг 2: Подготовленные ленты" 2
            run_demo "step2_prepared_feed" "Citus" "Шаг 2: Подготовленные ленты" 2
            ;;
        3)
            run_demo "step3_async_feed" "PostgreSQL" "Шаг 3: Асинхронная обработка" 3
            run_demo "step3_async_feed" "Citus" "Шаг 3: Асинхронная обработка" 3
            ;;
        4)
            run_demo "step4_multiconsumer" "PostgreSQL" "Шаг 4: Мультипотребители" 4
            run_demo "step4_multiconsumer" "Citus" "Шаг 4: Мультипотребители" 4
            ;;
        5)
            run_demo "step5_balanced" "PostgreSQL" "Шаг 5: Балансировка" 5
            run_demo "step5_balanced" "Citus" "Шаг 5: Балансировка" 5
            ;;
        6)
            run_demo "step6_cached" "PostgreSQL" "Шаг 6: Кэширование" 6
            run_demo "step6_cached" "Citus" "Шаг 6: Кэширование" 6
            ;;
        *)
            echo "Использование: $0 [1|2|3|4|5|6]"
            echo "Запустить сравнение конкретного шага или всех, если аргумент не указан"
            ;;
    esac
else
    # Запуск всех сравнений - PostgreSQL затем Citus для каждого шага
    for step in {1..6}; do
        case $step in
            1) name="Базовая архитектура" ;;
            2) name="Подготовленные ленты" ;;
            3) name="Асинхронная обработка" ;;
            4) name="Мультипотребители" ;;
            5) name="Балансировка" ;;
            6) name="Кэширование" ;;
        esac
        
        run_demo "step${step}_*" "PostgreSQL" "Шаг $step: $name" $step
        run_demo "step${step}_*" "Citus" "Шаг $step: $name" $step
    done
fi

echo ""
echo -e "${GREEN}========================================"
echo "✅ Демонстрация завершена!"
echo "========================================${NC}"
echo ""
echo -e "${CYAN}Ключевые наблюдения с реалистичной моделью:${NC}"
echo ""
echo "1. ${YELLOW}Проблема популярных пользователей:${NC}"
echo "   - Время создания твита растет линейно с количеством подписчиков"
echo "   - 400 подписчиков = 400x медленнее в синхронных архитектурах"
echo ""
echo "2. ${YELLOW}Эволюция архитектуры:${NC}"
echo "   - Шаг 1-2: Синхронная обработка блокирует популярных пользователей"
echo "   - Шаг 3: Асинхронность решает проблему блокировки"
echo "   - Шаг 4: Множество воркеров распределяют нагрузку"
echo "   - Шаг 5: Умная маршрутизация оптимизирует обработку"
echo "   - Шаг 6: Кэширование значительно ускоряет чтение"
echo ""
echo "3. ${YELLOW}PostgreSQL vs Citus:${NC}"
echo "   - На малых объемах PostgreSQL часто быстрее (меньше накладных расходов)"
echo "   - Citus лучше масштабируется горизонтально"
echo "   - Распределение данных в Citus помогает при миллионах записей"
echo ""
echo -e "${RED}В реальном Twitter знаменитости имеют миллионы подписчиков!${NC}"
echo ""
echo -e "${YELLOW}Очистить ресурсы Docker:${NC}"
echo "docker system prune -a"