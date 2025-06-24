#!/bin/bash

echo "=== Демонстрация проблемы популярных пользователей ==="
echo "Запуск сервисов..."

# Start services
docker-compose down -v
docker-compose up -d

# Wait for services to be ready
echo "Ожидание запуска сервисов..."
sleep 5

# Запуск приложения
echo "Запуск приложения..."
python main.py &
APP_PID=$!

sleep 3

# API URL
API_URL="http://localhost:8001/api"

echo -e "\n1. Создание пользователей..."
# Создаем 1000 пользователей для реалистичности
for i in {1..1000}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null &
  if [ $((i % 100)) -eq 0 ]; then
    wait
    echo -n " $i"
  fi
done
wait
echo " Готово!"

echo -e "\n2. Создание популярных пользователей..."
echo "   user1: популярный пользователь (500 подписчиков)"
# 500 подписчиков для user1
for follower in {2..501}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $follower" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 1}" > /dev/null &
  if [ $((follower % 50)) -eq 0 ]; then
    wait
  fi
done
wait
echo "   ✓ 500 подписчиков"

echo "   user2: мега-популярный пользователь (900 подписчиков)"
# 900 подписчиков для user2
for follower in {3..902}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $follower" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 2}" > /dev/null &
  if [ $((follower % 100)) -eq 0 ]; then
    wait
  fi
done
wait
echo "   ✓ 900 подписчиков"

echo -e "\n=== ДЕМОНСТРАЦИЯ ПРОБЛЕМЫ ==="

echo -e "\nСоздание твита от обычного пользователя (0 подписчиков):"
times_normal=()
for i in {1..3}; do
  echo -n "   Попытка $i: "
  start_time=$(date +%s%3N)
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 999" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Обычный твит #$i\"}" > /dev/null
  end_time=$(date +%s%3N)
  response_time=$((end_time - start_time))
  echo "$response_time мс"
  times_normal+=($response_time)
done

echo -e "\nСоздание твита от популярного пользователя (500 подписчиков):"
times_popular=()
for i in {1..3}; do
  echo -n "   Попытка $i: "
  start_time=$(date +%s%3N)
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Популярный твит #$i\"}" > /dev/null
  end_time=$(date +%s%3N)
  response_time=$((end_time - start_time))
  echo "$response_time мс"
  times_popular+=($response_time)
done

echo -e "\nСоздание твита от мега-популярного пользователя (900 подписчиков):"
times_mega=()
for i in {1..3}; do
  echo -n "   Попытка $i: "
  start_time=$(date +%s%3N)
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Мега-популярный твит #$i\"}" > /dev/null
  end_time=$(date +%s%3N)
  response_time=$((end_time - start_time))
  echo "$response_time мс"
  times_mega+=($response_time)
done

# Вычисление средних
sum_normal=0
sum_popular=0
sum_mega=0
for t in "${times_normal[@]}"; do sum_normal=$((sum_normal + t)); done
for t in "${times_popular[@]}"; do sum_popular=$((sum_popular + t)); done
for t in "${times_mega[@]}"; do sum_mega=$((sum_mega + t)); done

avg_normal=$((sum_normal / ${#times_normal[@]}))
avg_popular=$((sum_popular / ${#times_popular[@]}))
avg_mega=$((sum_mega / ${#times_mega[@]}))

echo -e "\n=== РЕЗУЛЬТАТЫ ==="
echo -e "\nСреднее время создания твита:"
echo "  0 подписчиков:   $avg_normal мс"
echo "  500 подписчиков: $avg_popular мс ($(( avg_popular / avg_normal ))x медленнее)"
echo "  900 подписчиков: $avg_mega мс ($(( avg_mega / avg_normal ))x медленнее)"

echo -e "\nПроблема:"
echo "Время создания твита растет линейно с количеством подписчиков!"
echo "В реальном Twitter у знаменитостей миллионы подписчиков..."

# Останавливаем приложение
echo -e "\n\nОстановка приложения..."
kill $APP_PID 2>/dev/null

echo -e "\nДля полного теста используйте: python load_test_data.py"
echo "Остановка демо: docker-compose down"