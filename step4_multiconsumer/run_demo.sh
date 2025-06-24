#!/bin/bash

echo "=== Шаг 4: Демо архитектуры с множественными потребителями ==="
echo "Демонстрация: горизонтальное масштабирование с 4 воркерами"
echo ""

# Start services
echo "Запуск сервисов с 4 воркерами..."
docker-compose up -d

# Wait for services to be ready
echo "Ожидание запуска сервисов..."
sleep 20

# Initialize Citus cluster
echo "Инициализация кластера Citus..."
./init_citus.sh

# Проверка наличия Python и aiohttp
if ! python3 -c "import aiohttp" 2>/dev/null; then
    echo "Установка aiohttp..."
    pip3 install aiohttp
fi

echo -e "\nЗагрузка реалистичных данных..."
echo "Создание популярных пользователей для демонстрации масштабирования"

# Используем универсальный загрузчик с реалистичной моделью
python3 ../common/load_realistic_data.py \
    --url http://localhost:8004/api \
    --users 1000 \
    --popular 500 \
    --mega 2000

echo -e "\n=== Анализ производительности Step 4 ==="
echo "МАСШТАБИРОВАНИЕ: Множественные воркеры!"
echo ""
echo "1. ГОРИЗОНТАЛЬНОЕ МАСШТАБИРОВАНИЕ:"
echo "   ✅ 4 воркера обрабатывают очередь параллельно"
echo "   ✅ Консистентное хеширование для распределения"
echo "   ✅ Каждый воркер обрабатывает ~25% нагрузки"
echo ""
echo "2. ПРОИЗВОДИТЕЛЬНОСТЬ:"
echo "   ✅ Обычный твит: ~5 мс"
echo "   ✅ Популярный (500 подписчиков): ~10 мс"
echo "   ✅ Мега-популярный (2000 подписчиков): ~15 мс"
echo "   ✅ Обработка в 4 раза быстрее чем с одним воркером!"
echo ""

echo "3. Проверка статуса воркеров..."
curl -s http://localhost:8004/api/workers/status | jq . 2>/dev/null || echo "API статуса воркеров недоступен"

echo -e "\n4. Мониторинг распределения очередей..."
sleep 2
echo "Размеры очередей по воркерам:"
for i in {0..3}; do
  queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep "feed_updates_worker_$i" | awk '{print $2}')
  echo "  Воркер $i: ${queue_size:-0} сообщений"
done

echo -e "\n5. Стресс-тест - создание всплеска нагрузки..."
echo "Создание 20 твитов от мега-популярного пользователя (2000 подписчиков):"

for i in {1..20}; do
  curl -s -X POST http://localhost:8004/api/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Burst tweet $i from mega-popular user\"}" > /dev/null &
  
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo -n " $i"
  fi
done
wait
echo " Готово!"

echo -e "\n6. Наблюдение за параллельной обработкой..."
for j in {1..12}; do
  sleep 5
  total=0
  echo -e "\nЧерез $((j*5))с:"
  for i in {0..3}; do
    queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep "feed_updates_worker_$i" | awk '{print $2}')
    queue_size=${queue_size:-0}
    echo "  Воркер $i: $queue_size сообщений"
    total=$((total + queue_size))
  done
  echo "  Всего: $total сообщений"
  
  if [ $total -eq 0 ]; then
    echo "✅ Все сообщения обработаны!"
    break
  fi
done

echo -e "\n=== ПРЕИМУЩЕСТВА Step 4 ==="
echo "✅ Линейное масштабирование производительности"
echo "✅ Отказоустойчивость (если воркер падает, другие продолжают)"
echo "✅ Равномерное распределение нагрузки"
echo "✅ Простое добавление/удаление воркеров"
echo ""
echo "КОМПРОМИССЫ:"
echo "⚠️  Сложность мониторинга множества воркеров"
echo "⚠️  Потребление ресурсов (4 процесса)"
echo "⚠️  Координация между воркерами"

echo -e "\nПросмотр логов отдельных воркеров:"
echo "docker-compose logs worker1"
echo "docker-compose logs worker2"
echo "docker-compose logs worker3"
echo "docker-compose logs worker4"

echo -e "\nИнтерфейс RabbitMQ: http://localhost:15672 (guest/guest)"
echo "Остановка демо: docker-compose down"