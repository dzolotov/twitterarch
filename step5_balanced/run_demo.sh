#!/bin/bash

echo "=== Step 5: Production-Ready with Monitoring Demo ==="
echo "Starting services with monitoring stack..."

# Start services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start (this takes longer due to monitoring stack)..."
sleep 30

# Initialize Citus cluster
echo "Initializing Citus cluster..."
./init_citus.sh

# API URL
API_URL="http://localhost:8005/api"

echo -e "\n1. Creating test users for load testing..."
for i in {1..500}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  if [ $((i % 50)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n2. Creating influencers with varying follower counts..."
# Influencer 1: 100 followers
curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"influencer1\", \"email\": \"influencer1@example.com\"}" > /dev/null

for i in {1..100}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 501}" > /dev/null
done
echo "Influencer 1: 100 followers ✓"

# Influencer 2: 200 followers
curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"influencer2\", \"email\": \"influencer2@example.com\"}" > /dev/null

for i in {101..300}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 502}" > /dev/null
done
echo "Influencer 2: 200 followers ✓"

# Celebrity: 499 followers
curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"celebrity\", \"email\": \"celebrity@example.com\"}" > /dev/null

for i in {1..499}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 503}" > /dev/null
  if [ $((i % 100)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Celebrity: 499 followers ✓"

echo -e "\n3. Checking monitoring endpoints..."
echo "Prometheus metrics available:"
curl -s $API_URL/../metrics | grep -E "^(tweets_created_total|feed_updates_total|worker_messages_processed_total)" | head -5

echo -e "\n4. Starting sustained load test..."
echo "Generating continuous load for metrics collection:"

# Function to create tweets
create_tweets() {
  local user_id=$1
  local count=$2
  local delay=$3
  
  for i in $(seq 1 $count); do
    curl -s -X POST $API_URL/tweets/ \
      -H "X-User-ID: $user_id" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"Load test from user $user_id - tweet $i at $(date +%s)\"}" > /dev/null
    sleep $delay
  done
}

# Start background load
echo "Starting background load generators..."
create_tweets 501 100 0.5 &  # Influencer 1: 100 tweets, 0.5s delay
PID1=$!
create_tweets 502 100 1 &    # Influencer 2: 100 tweets, 1s delay
PID2=$!
create_tweets 503 50 2 &     # Celebrity: 50 tweets, 2s delay
PID3=$!

echo "Load generators running (PIDs: $PID1, $PID2, $PID3)"

echo -e "\n5. Monitoring system performance..."
echo "Collecting metrics for 30 seconds..."

for i in {1..6}; do
  sleep 5
  echo -e "\nAfter $((i*5))s:"
  
  # Get queue sizes
  total_queue=0
  for j in {0..3}; do
    queue_size=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues name messages 2>/dev/null | grep "feed_updates_balanced_$j" | awk '{print $2}')
    queue_size=${queue_size:-0}
    total_queue=$((total_queue + queue_size))
  done
  echo "  Total messages in queues: $total_queue"
  
  # Get metrics
  tweets_created=$(curl -s $API_URL/../metrics | grep "tweets_created_total" | grep -v "#" | awk '{print $2}')
  echo "  Total tweets created: ${tweets_created:-0}"
  
  feed_updates=$(curl -s $API_URL/../metrics | grep "feed_updates_total" | grep -v "#" | head -1 | awk '{print $2}')
  echo "  Total feed updates: ${feed_updates:-0}"
done

echo -e "\n6. Checking optimized routing distribution..."
echo "Worker message distribution:"
for i in {0..3}; do
  count=$(curl -s $API_URL/../metrics | grep "worker_messages_processed_total{" | grep "worker_id=\"$i\"" | grep "success" | awk '{print $2}')
  echo "  Worker $i: ${count:-0} messages processed"
done

echo -e "\n7. Performance metrics summary..."
# Kill background processes
kill $PID1 $PID2 $PID3 2>/dev/null
wait

# Final metrics
echo -e "\nFinal system metrics:"
curl -s $API_URL/../metrics | grep -E "(tweets_created_total|feed_updates_total|worker_processing_time_seconds_sum)" | grep -v "#"

echo -e "\n=== Monitoring Access ==="
echo "📊 Grafana Dashboard: http://localhost:3000 (admin/admin)"
echo "📈 Prometheus: http://localhost:9090"
echo "🐰 RabbitMQ Management: http://localhost:15672 (guest/guest)"
echo "📋 Application Metrics: http://localhost:8005/metrics"

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "✅ Full metrics visibility for all operations"
echo "✅ Optimized message routing (hash: 20)"
echo "✅ Batch processing for efficiency"
echo "✅ Worker performance tracking"
echo "✅ Production-ready monitoring"

echo -e "\nImport Grafana dashboard:"
echo "1. Open http://localhost:3000"
echo "2. Login with admin/admin"
echo "3. Import dashboard from grafana-dashboard.json"

echo -e "\nStop demo: docker-compose down -v"