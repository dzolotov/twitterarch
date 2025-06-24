#!/bin/bash

echo "=== Step 1: Сравнение PostgreSQL vs Citus ==="
echo ""
echo "Этот скрипт запустит тесты производительности для обеих конфигураций"
echo "и покажет детальное сравнение результатов."
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Очистка старых данных
echo "Очистка старых данных..."
docker-compose -f docker-compose.postgres.yml down -v 2>/dev/null
docker-compose -f docker-compose.citus.yml down -v 2>/dev/null

# 1. Запуск PostgreSQL версии
echo ""
echo -e "${BLUE}═══ ТЕСТ 1: PostgreSQL (одиночный узел) ═══${NC}"
echo "Запуск контейнеров..."
docker-compose -f docker-compose.postgres.yml up -d

# Ждем готовности
echo "Ожидание готовности PostgreSQL..."
until docker-compose -f docker-compose.postgres.yml exec -T postgres pg_isready -U user -d twitter_db > /dev/null 2>&1; do
    sleep 1
done
sleep 2

# Запускаем тесты
echo "Запуск тестов производительности..."
docker-compose -f docker-compose.postgres.yml exec -T -e DB_TYPE=postgres app python step1_basic/load_comparison_data.py | tee postgres_results.txt

# Останавливаем
echo "Остановка PostgreSQL..."
docker-compose -f docker-compose.postgres.yml down

echo ""

# 2. Запуск Citus версии
echo -e "${BLUE}═══ ТЕСТ 2: Citus (распределенная БД) ═══${NC}"
echo "Запуск контейнеров..."
docker-compose -f docker-compose.citus.yml up -d

# Ждем готовности
echo "Ожидание готовности Citus..."
until docker-compose -f docker-compose.citus.yml exec -T citus_master pg_isready -U user -d twitter_db > /dev/null 2>&1; do
    sleep 1
done
sleep 5

# Инициализируем Citus
echo "Инициализация Citus кластера..."
chmod +x init_citus_comparison.sh
./init_citus_comparison.sh

# Запускаем тесты
echo "Запуск тестов производительности..."
docker-compose -f docker-compose.citus.yml exec -T -e DB_TYPE=citus app python step1_basic/load_comparison_data.py | tee citus_results.txt

# Останавливаем
echo "Остановка Citus..."
docker-compose -f docker-compose.citus.yml down

echo ""

# 3. Итоговое сравнение
echo -e "${YELLOW}═══ ИТОГОВОЕ СРАВНЕНИЕ ═══${NC}"

# Объединяем результаты для финального сравнения
cat postgres_results.txt citus_results.txt | python3 -c "
import sys
content = sys.stdin.read()

# Извлекаем метрики из обоих тестов
postgres_metrics = {}
citus_metrics = {}

current_db = None
for line in content.split('\n'):
    if 'PostgreSQL' in line and 'ТЕСТИРОВАНИЕ' in line.upper():
        current_db = 'postgres'
    elif 'Citus' in line and 'ТЕСТИРОВАНИЕ' in line.upper():
        current_db = 'citus'
    
    if current_db and 'Время:' in line:
        if 'пользователей' in line:
            time = float(line.split('Время:')[1].split('сек')[0].strip())
            if current_db == 'postgres':
                postgres_metrics['users'] = time
            else:
                citus_metrics['users'] = time
        elif 'подписок' in line:
            time = float(line.split('Время:')[1].split('сек')[0].strip())
            if current_db == 'postgres':
                postgres_metrics['follows'] = time
            else:
                citus_metrics['follows'] = time
        elif '5000 твитов' in line:
            time = float(line.split('Время:')[1].split('сек')[0].strip())
            if current_db == 'postgres':
                postgres_metrics['tweets_5k'] = time
            else:
                citus_metrics['tweets_5k'] = time
        elif '10000 твитов' in line:
            time = float(line.split('Время:')[1].split('сек')[0].strip())
            if current_db == 'postgres':
                postgres_metrics['tweets_10k'] = time
            else:
                citus_metrics['tweets_10k'] = time
    
    if current_db and '500 подписок' in line and 'мс' in line:
        time = float(line.split(':')[1].split('мс')[0].strip()) / 1000
        key = 'feed_initial' if '15K' not in line else 'feed_final'
        if current_db == 'postgres':
            postgres_metrics[key] = time
        else:
            citus_metrics[key] = time

# Выводим сравнение
print()
print('Операция                        PostgreSQL    Citus         Разница')
print('─' * 70)

if 'users' in postgres_metrics and 'users' in citus_metrics:
    pg, ct = postgres_metrics['users'], citus_metrics['users']
    print(f'Создание 1000 пользователей     {pg:>8.1f}s    {ct:>8.1f}s     {ct/pg:>5.1f}x')

if 'follows' in postgres_metrics and 'follows' in citus_metrics:
    pg, ct = postgres_metrics['follows'], citus_metrics['follows']
    print(f'Создание 500 подписок           {pg:>8.1f}s    {ct:>8.1f}s     {ct/pg:>5.1f}x')

if 'tweets_5k' in postgres_metrics and 'tweets_5k' in citus_metrics:
    pg, ct = postgres_metrics['tweets_5k'], citus_metrics['tweets_5k']
    print(f'Создание 5000 твитов            {pg:>8.1f}s    {ct:>8.1f}s     {ct/pg:>5.1f}x')

if 'feed_initial' in postgres_metrics and 'feed_initial' in citus_metrics:
    pg, ct = postgres_metrics['feed_initial']*1000, citus_metrics['feed_initial']*1000
    print(f'Чтение ленты (5K твитов)        {pg:>8.1f}ms   {ct:>8.1f}ms    {ct/pg:>5.1f}x')

if 'tweets_10k' in postgres_metrics and 'tweets_10k' in citus_metrics:
    pg, ct = postgres_metrics['tweets_10k'], citus_metrics['tweets_10k']
    print(f'Создание 10000 твитов           {pg:>8.1f}s    {ct:>8.1f}s     {ct/pg:>5.1f}x')

if 'feed_final' in postgres_metrics and 'feed_final' in citus_metrics:
    pg, ct = postgres_metrics['feed_final']*1000, citus_metrics['feed_final']*1000
    print(f'Чтение ленты (15K твитов)       {pg:>8.1f}ms   {ct:>8.1f}ms    {ct/pg:>5.1f}x')
"

echo ""
echo -e "${GREEN}Анализ результатов:${NC}"
echo "• На малых объемах данных PostgreSQL работает быстрее"
echo "• Citus имеет накладные расходы на координацию между узлами"
echo "• Преимущества Citus проявятся при:"
echo "  - Миллионах пользователей и твитов"
echo "  - Необходимости горизонтального масштабирования"
echo "  - Распределенной обработке больших запросов"

echo ""
echo "Полные логи сохранены в:"
echo "  - postgres_results.txt"
echo "  - citus_results.txt"

# Очистка
docker-compose -f docker-compose.postgres.yml down -v
docker-compose -f docker-compose.citus.yml down -v