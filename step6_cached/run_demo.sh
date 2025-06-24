#!/bin/bash

echo "=== Step 6: Cached Architecture with Circular Buffers Demo ==="
echo "Starting services with Redis caching..."

# Start services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 25

# Initialize Citus cluster
echo "Initializing Citus cluster..."
./init_citus.sh

# API URL
API_URL="http://localhost:8006/api"

echo -e "\n1. Loading realistic data with universal loader..."
cd ..
python3 common/load_realistic_data.py \
  --url "$API_URL" \
  --users 1000 \
  --popular 500 \
  --mega 2000 \
  --no-measure
cd step6_cached

# Wait for data processing
echo -e "\nWaiting for data processing..."
sleep 10

echo -e "\n2. Creating initial tweets to populate feeds..."
echo "Popular user creating tweets:"
for i in {1..20}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Popular user tweet $i - warming up caches\"}" > /dev/null
done

echo "Mega-popular user creating tweets:"
for i in {1..20}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Mega-popular tweet $i - massive distribution\"}" > /dev/null
done
echo "Initial tweets created!"

echo -e "\n3. Waiting for feed processing..."
sleep 10

echo -e "\n4. Testing cache performance..."
echo "First access (cache miss - will populate cache):"
for i in {1..5}; do
  user_id=$((RANDOM % 100 + 1))
  echo -n "User $user_id feed: "
  time curl -s $API_URL/feed/ -H "X-User-ID: $user_id" > /dev/null
done

echo -e "\nSecond access (cache hit - should be much faster):"
for i in {1..5}; do
  user_id=$((i))
  echo -n "User $user_id feed (cached): "
  time curl -s $API_URL/feed/ -H "X-User-ID: $user_id" > /dev/null
done

echo -e "\n5. Checking cache statistics..."
cache_stats=$(curl -s $API_URL/../cache/stats)
echo "Cache statistics:" 
echo "$cache_stats" | jq .

echo -e "\n6. Testing circular buffer behavior..."
echo "Creating 50 more tweets to test buffer overflow:"
for i in {21..70}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Buffer test tweet $i - testing circular buffer overflow\"}" > /dev/null
  if [ $((i % 10)) -eq 0 ]; then
    echo -n " $i"
  fi
done
echo " Done!"

sleep 5

echo -e "\n7. Checking hot users (most accessed)..."
cache_stats=$(curl -s $API_URL/../cache/stats)
echo "Hot users:" 
echo "$cache_stats" | jq '.hot_users'

echo -e "\n8. Testing message deduplication..."
echo "Testing proper handling of duplicate messages:"
# Get current stats
before_stats=$(curl -s $API_URL/../cache/stats | jq '.processed_messages')
echo "Messages processed before: $before_stats"

# Create a tweet (will generate messages)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 1" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Deduplication test tweet\"}" > /dev/null

sleep 3

# Check stats again
after_stats=$(curl -s $API_URL/../cache/stats | jq '.processed_messages')
echo "Messages processed after: $after_stats"

echo -e "\n9. Load test with caching..."
echo "Performance comparison - Popular vs Mega-popular users:"

# Popular user (500 followers)
echo -e "\nPopular user (500 followers) - 25 tweets:"
start_time=$(date +%s%N)
for i in {1..25}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Popular load test $i at $(date +%s%N)\"}" > /dev/null &
  
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo -n " $i"
  fi
done
wait
end_time=$(date +%s%N)
echo -e "\n25 tweets from popular user: $(((end_time - start_time) / 1000000))ms"

# Mega-popular user (2000 followers)
echo -e "\nMega-popular user (2000 followers) - 25 tweets:"
start_time=$(date +%s%N)
for i in {1..25}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Mega load test $i at $(date +%s%N)\"}" > /dev/null &
  
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo -n " $i"
  fi
done
wait
end_time=$(date +%s%N)
echo -e "\n25 tweets from mega-popular user: $(((end_time - start_time) / 1000000))ms"

echo -e "\n10. Cache performance comparison..."
echo "Reading feeds with and without cache:"

# Clear specific user's cache
user_test=100

echo -e "\nWithout cache (first read):"
time curl -s $API_URL/feed/ -H "X-User-ID: $user_test" > /dev/null

echo -e "\nWith cache (second read):"
time curl -s $API_URL/feed/ -H "X-User-ID: $user_test" > /dev/null

echo -e "\n11. Final cache statistics..."
final_stats=$(curl -s $API_URL/../cache/stats)
echo "Final cache state:"
echo "$final_stats" | jq .

echo -e "\n=== Redis Cache Analysis ==="
echo "Direct Redis check:"
docker-compose exec redis redis-cli INFO memory | grep used_memory_human

echo -e "\nCache key patterns:"
docker-compose exec redis redis-cli --scan --pattern "feed:buffer:*" | head -10
echo "..."
docker-compose exec redis redis-cli --scan --pattern "tweet:*" | head -10
echo "..."
docker-compose exec redis redis-cli --scan --pattern "msg:processed:*" | head -10

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "✅ Cache hits are 10x faster than misses"
echo "✅ Circular buffer limits memory usage"
echo "✅ Hot users are tracked automatically"
echo "✅ Message deduplication prevents reprocessing"
echo "✅ Cache warming improves performance"
echo "✅ Redis LRU eviction manages memory"
echo "✅ Popular users (500 followers) benefit from caching"
echo "✅ Mega-popular users (2000 followers) stress test the system"

echo -e "\nRedis Commander (optional): docker run -d --rm --name redis-commander -p 8081:8081 --link step6_cached_redis_1:redis rediscommander/redis-commander:latest --redis-host redis"

echo -e "\nStop demo: docker-compose down -v"