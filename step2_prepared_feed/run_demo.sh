#!/bin/bash

echo "=== Step 2: Prepared Feed Architecture Demo ==="
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
API_URL="http://localhost:8002/api"

echo -e "\n1. Creating users..."
for i in {1..50}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n2. Creating follow relationships..."
# Create a popular user (user 1) with many followers
for i in {2..50}; do
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 1}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n3. Testing feed read performance (pre-computed feeds)..."
echo "Creating initial tweets to populate feeds:"
for i in {1..10}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Initial tweet $i from popular user\"}" > /dev/null
  echo -n "."
done
echo " Done!"

echo -e "\n4. Measuring feed read performance:"
for i in {1..5}; do
  echo -n "User $((i+1)) feed read: "
  time curl -s $API_URL/feed/ -H "X-User-ID: $((i+1))" > /dev/null
done

echo -e "\n5. Testing tweet creation performance (fan-out to 49 followers)..."
echo "Creating tweets from popular user and measuring time:"

for i in {1..5}; do
  echo -n "Tweet $i (49 followers): "
  start=$(date +%s%N)
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Performance test tweet $i at $(date +%s%N)\"}" > /dev/null
  end=$(date +%s%N)
  echo "$((($end - $start) / 1000000))ms"
done

echo -e "\n6. Stress test - User with MANY followers..."
echo "Creating user 51 and making 200 users follow them:"

curl -s -X POST $API_URL/users/ \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"celebrity\", \"email\": \"celebrity@example.com\"}" > /dev/null

# Create more users
for i in {52..251}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"fan$i\", \"email\": \"fan$i@example.com\"}" > /dev/null
  
  curl -s -X POST $API_URL/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 51}" > /dev/null
  
  if [ $((i % 10)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n7. Testing tweet creation with 200 followers (will be slow!):"
echo -n "Creating tweet for celebrity user: "
time curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 51" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Hello to my 200 fans! This will take a while...\"}" 

echo -e "\n=== Performance Analysis ==="
echo "Notice how:"
echo "✅ Feed reads are now very fast (pre-computed)"
echo "❌ Tweet creation is slower (synchronous fan-out)"
echo "❌ Tweet creation time increases with number of followers"
echo "❌ Can timeout with many followers"

echo -e "\nCheck database to see feed_items table:"
echo "docker-compose exec citus_master psql -U user -d twitter_db -c 'SELECT COUNT(*) FROM feed_items;'"

echo -e "\nView logs: docker-compose logs app"
echo "Stop demo: docker-compose down"