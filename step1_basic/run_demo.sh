#!/bin/bash

echo "=== Step 1: Basic Architecture Demo ==="
echo "Starting services..."

# Start services
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 10

# Initialize Citus cluster
echo "Initializing Citus cluster..."
./init_citus.sh

# API URL
API_URL="http://localhost:8001/api"

echo -e "\n1. Creating users..."
for i in {1..20}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n2. Creating follow relationships..."
# User 1 follows everyone
for i in {2..20}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": $i}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n3. Creating tweets..."
for i in {2..20}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Hello from user$i! This is tweet at $(date +%s)\"}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n4. Testing feed performance (user with 19 subscriptions)..."
echo "Fetching feed 5 times and measuring response time:"

for i in {1..5}; do
  echo -n "Attempt $i: "
  time curl -s $API_URL/feed/ -H "X-User-ID: 1" > /dev/null
done

echo -e "\n5. Load test - Creating tweets rapidly..."
echo "Creating 50 tweets from popular user (followed by user 1):"

start_time=$(date +%s)
for i in {1..50}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Load test tweet $i at $(date +%s%N)\"}" > /dev/null &
  
  # Run 5 requests in parallel
  if [ $((i % 5)) -eq 0 ]; then
    wait
    echo -n "."
  fi
done
wait
end_time=$(date +%s)
echo -e "\nCompleted in $((end_time - start_time)) seconds"

echo -e "\n6. Checking final feed size..."
feed_count=$(curl -s $API_URL/feed/ -H "X-User-ID: 1" | grep -o "tweet_id" | wc -l)
echo "User 1's feed contains $feed_count tweets"

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "- Feed reading uses expensive JOIN queries"
echo "- Performance degrades with more followed users"
echo "- All operations are synchronous and blocking"
echo "- No caching or optimization"

echo -e "\nView logs: docker-compose logs app"
echo "Stop demo: docker-compose down"