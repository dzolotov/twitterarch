#!/bin/bash

echo "=== Step 4: Multi-Consumer Architecture Demo ==="
echo "Starting services with 4 workers..."

# Start services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 20

# Initialize Citus cluster
echo "Initializing Citus cluster..."
./init_citus.sh

# API URL
API_URL="http://localhost:8004/api"

echo -e "\n1. Creating test users..."
for i in {1..200}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  if [ $((i % 20)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n2. Creating mega celebrity with 199 followers..."
curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"megastar\", \"email\": \"megastar@example.com\"}" > /dev/null

# Make 199 users follow the megastar
for i in {1..199}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 201}" > /dev/null
  if [ $((i % 20)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n3. Checking worker status..."
curl -s $API_URL/workers/status | jq .

echo -e "\n4. Testing parallel processing with multi-consumer..."
echo "Creating tweet from megastar (199 followers = 199 messages):"

start_time=$(date +%s%N)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 201" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Hello to all my 199 fans! This message will be processed by 4 workers in parallel.\"}" > /dev/null
end_time=$(date +%s%N)
echo "Tweet created in $(((end_time - start_time) / 1000000))ms"

echo -e "\n5. Monitoring queue distribution..."
sleep 2
echo "Queue sizes:"
for i in {0..3}; do
  queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep "feed_updates_worker_$i" | awk '{print $2}')
  echo "Worker $i queue: ${queue_size:-0} messages"
done

echo -e "\n6. Stress test - Creating many tweets rapidly..."
echo "Creating 50 tweets from megastar (50 x 199 = 9,950 messages!):"

for i in {1..50}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 201" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Burst tweet $i at $(date +%s%N)\"}" > /dev/null &
  
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo -n "."
  fi
done
wait
echo " Done!"

echo -e "\n7. Watching parallel processing..."
for j in {1..20}; do
  sleep 3
  total=0
  echo -e "\nAfter $((j*3))s:"
  for i in {0..3}; do
    queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep "feed_updates_worker_$i" | awk '{print $2}')
    queue_size=${queue_size:-0}
    echo "  Worker $i: $queue_size messages"
    total=$((total + queue_size))
  done
  echo "  Total: $total messages"
  
  if [ $total -eq 0 ]; then
    echo "All messages processed!"
    break
  fi
done

echo -e "\n8. Checking worker logs for distribution..."
echo "Worker processing counts:"
for i in {1..4}; do
  count=$(docker-compose logs worker$i 2>&1 | grep -c "successfully processed")
  echo "Worker$i processed: ~$count messages"
done

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "✅ Messages are distributed across 4 workers"
echo "✅ Each worker processes ~25% of messages"
echo "✅ Parallel processing handles high volume"
echo "✅ System scales horizontally"
echo "✅ Consistent hash ensures even distribution"

echo -e "\nView individual worker logs:"
echo "docker-compose logs worker1"
echo "docker-compose logs worker2"
echo "docker-compose logs worker3"
echo "docker-compose logs worker4"

echo -e "\nStop demo: docker-compose down"