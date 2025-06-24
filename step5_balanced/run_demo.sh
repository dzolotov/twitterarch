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

echo -e "\n1. Loading realistic data with universal loader..."
cd ..
python3 common/load_realistic_data.py \
  --url "$API_URL" \
  --users 1000 \
  --popular 500 \
  --mega 2000 \
  --no-measure
cd step5_balanced

# Wait for data processing
echo -e "\nWaiting for data processing..."
sleep 10

echo -e "\n2. Checking monitoring endpoints..."
echo "Prometheus metrics available:"
curl -s $API_URL/../metrics | grep -E "^(tweets_created_total|feed_updates_total|worker_messages_processed_total)" | head -5

echo -e "\n3. Performance testing with popular users..."
echo "Testing tweet creation performance degradation:"

# Normal user tweet
echo -e "\nNormal user (few followers):"
time curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 999" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Normal user tweet - minimal feed updates\"}"

# Popular user tweet (500 followers) 
echo -e "\nPopular user (500 followers):"
time curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 1" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Popular user tweet - 500 feed updates\"}"

# Mega-popular user tweet (2000 followers)
echo -e "\nMega-popular user (2000 followers):"
time curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 2" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Mega-popular tweet - 2000 feed updates\"}"

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
create_tweets 1 50 0.5 &    # Popular user: 50 tweets, 0.5s delay
PID1=$!
create_tweets 2 25 1 &      # Mega-popular user: 25 tweets, 1s delay
PID2=$!
create_tweets 100 50 0.2 &  # Normal user: 50 tweets, 0.2s delay
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
echo "✅ Popular users (500 followers) create moderate load"
echo "✅ Mega-popular users (2000 followers) create significant load"
echo "✅ Balanced routing distributes work evenly across workers"

echo -e "\nImport Grafana dashboard:"
echo "1. Open http://localhost:3000"
echo "2. Login with admin/admin"
echo "3. Import dashboard from grafana-dashboard.json"

echo -e "\nStop demo: docker-compose down -v"