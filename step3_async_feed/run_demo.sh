#!/bin/bash

echo "=== Step 3: Async Feed with RabbitMQ Demo ==="
echo "Starting services..."

# Start services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 15

# Initialize Citus cluster
echo "Initializing Citus cluster..."
./init_citus.sh

# API URL
API_URL="http://localhost:8003/api"

echo -e "\n1. Creating test users..."
for i in {1..100}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  if [ $((i % 10)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n2. Creating celebrity user with many followers..."
curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"celebrity\", \"email\": \"celebrity@example.com\"}" > /dev/null

# Make 99 users follow the celebrity
for i in {1..99}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 101}" > /dev/null
  if [ $((i % 10)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n3. Testing tweet creation performance (async processing)..."
echo "Creating tweets from celebrity (100 followers) - should return immediately:"

for i in {1..5}; do
  echo -n "Tweet $i: "
  time curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 101" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Async tweet $i - this returns immediately!\"}" > /dev/null
done

echo -e "\n4. Checking RabbitMQ queue..."
sleep 2
queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages | grep feed_updates | awk '{print $2}')
echo "Messages in queue: ${queue_size:-0}"

echo -e "\n5. Load test - Rapid tweet creation..."
echo "Creating 100 tweets rapidly (they will queue up):"

start_time=$(date +%s)
for i in {1..100}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 101" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Rapid tweet $i at $(date +%s%N)\"}" > /dev/null &
  
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo -n "."
  fi
done
wait
end_time=$(date +%s)
echo -e "\nAll tweets created in $((end_time - start_time)) seconds"

echo -e "\n6. Monitoring async processing..."
echo "Checking queue size over time:"
for i in {1..10}; do
  sleep 3
  queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep feed_updates | awk '{print $2}')
  echo "After $((i*3))s: ${queue_size:-0} messages remaining"
  if [ "${queue_size:-0}" -eq 0 ]; then
    echo "All messages processed!"
    break
  fi
done

echo -e "\n7. Verifying eventual consistency..."
sleep 5
echo "Checking a follower's feed:"
feed_count=$(curl -s $API_URL/feed/ -H "X-User-ID: 1" | grep -o "tweet_id" | wc -l)
echo "User 1's feed contains $feed_count tweets"

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "✅ Tweet creation returns immediately (non-blocking)"
echo "✅ System handles traffic spikes gracefully"
echo "✅ Messages queue up and are processed asynchronously"
echo "✅ Feeds are eventually consistent"
echo "⚠️  Single worker might be a bottleneck for very high volume"

echo -e "\nRabbitMQ Management UI: http://localhost:15672 (guest/guest)"
echo "View logs: docker-compose logs app"
echo "Stop demo: docker-compose down"