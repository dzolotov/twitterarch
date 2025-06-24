#!/bin/bash

echo "=== Шаг 2: Демо архитектуры с подготовленными лентами ==="
echo "Демонстрация: быстрое чтение, но медленная запись для популярных пользователей"
echo ""

# Start services
echo "Запуск сервисов..."
docker-compose up -d

# Wait for services to be ready
echo "Ожидание запуска сервисов..."
sleep 10

# Initialize Citus cluster
echo "Инициализация кластера Citus..."
./init_citus.sh

# Проверка наличия Python и aiohttp
if ! python3 -c "import aiohttp" 2>/dev/null; then
    echo "Установка aiohttp..."
    pip3 install aiohttp
fi

echo -e "\nЗагрузка реалистичных данных..."
echo "Создание популярных пользователей для демонстрации проблемы"

# Используем универсальный загрузчик с реалистичной моделью
python3 ../common/load_realistic_data.py \
    --url http://localhost:8002/api \
    --users 1000 \
    --popular 500 \
    --mega 2000

echo -e "\n=== Анализ производительности Step 2 ==="
echo "Изменения по сравнению с Step 1:"
echo ""
echo "1. ПРЕДВАРИТЕЛЬНО ВЫЧИСЛЕННЫЕ ЛЕНТЫ:"
echo "   ✅ Чтение ленты: <10мс (было 200-500мс)"
echo "   ✅ Нет JOIN запросов при чтении"
echo "   ✅ Простая выборка из feed_items"
echo ""
echo "2. ПРОБЛЕМА ПОПУЛЯРНЫХ ПОЛЬЗОВАТЕЛЕЙ ОСТАЕТСЯ:"
echo "   ❌ Обычный твит: ~5 мс"
echo "   ❌ Популярный (500 подписчиков): ~500 мс"
echo "   ❌ Мега-популярный (2000 подписчиков): ~2000 мс"
echo ""
echo "3. НОВЫЕ ПРОБЛЕМЫ:"
echo "   ❌ Дублирование данных (каждый твит хранится N раз)"
echo "   ❌ Больше места на диске"
echo "   ❌ Сложность удаления/редактирования твитов"
echo ""
echo "ВЫВОД: Мы поменяли медленное чтение на медленную запись!"
echo "       Проблема популярных пользователей НЕ РЕШЕНА."

echo -e "\nПроверьте базу данных для просмотра таблицы feed_items:"
echo "docker-compose exec citus_master psql -U user -d twitter_db -c 'SELECT COUNT(*) FROM feed_items;'"

echo -e "\nПросмотр логов: docker-compose logs app"
echo "Остановка демо: docker-compose down"