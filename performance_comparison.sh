#!/bin/bash

echo "=== Performance Comparison Across All Steps ==="
echo "Using realistic follower model with popular users"
echo ""

# Test parameters
NUM_USERS=1000
POPULAR_USER_FOLLOWERS=500
MEGA_POPULAR_FOLLOWERS=2000
NORMAL_USER_FOLLOWS=100  # How many users a normal user follows
NUM_TWEETS=20

# Results file
RESULTS_FILE="performance_results.txt"
echo "Performance Test Results - $(date)" > $RESULTS_FILE
echo "Test params:" >> $RESULTS_FILE
echo "  - $NUM_USERS total users" >> $RESULTS_FILE
echo "  - Popular user: $POPULAR_USER_FOLLOWERS followers" >> $RESULTS_FILE
echo "  - Mega-popular user: $MEGA_POPULAR_FOLLOWERS followers" >> $RESULTS_FILE
echo "  - Normal users follow: ~$NORMAL_USER_FOLLOWS users" >> $RESULTS_FILE
echo "" >> $RESULTS_FILE

# Function to test a step
test_step() {
    local step=$1
    local name=$2
    local dir=$3
    local port=$4
    
    echo -e "\nTesting Step $step: $name"
    echo "Step $step: $name" >> $RESULTS_FILE
    
    cd $dir
    
    # Start services
    docker-compose up -d
    echo "Waiting for services to start..."
    sleep 20
    
    API_URL="http://localhost:$port/api"
    
    # Create users
    echo -n "Creating $NUM_USERS users..."
    for i in $(seq 1 $NUM_USERS); do
        curl -s -X POST $API_URL/users/ \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null &
        if [ $((i % 100)) -eq 0 ]; then
            wait
            echo -n " $i"
        fi
    done
    wait
    echo " Done"
    
    # Create popular user (user1) with 500 followers
    echo -n "Creating popular user with $POPULAR_USER_FOLLOWERS followers..."
    for i in $(seq 2 $((POPULAR_USER_FOLLOWERS + 1))); do
        curl -s -X POST $API_URL/subscriptions/follow \
            -H "X-User-ID: $i" \
            -H "Content-Type: application/json" \
            -d "{\"followed_id\": 1}" > /dev/null &
        if [ $((i % 50)) -eq 0 ]; then
            wait
        fi
    done
    wait
    echo " Done"
    
    # Create mega-popular user (user2) with 2000 followers
    echo -n "Creating mega-popular user with $MEGA_POPULAR_FOLLOWERS followers..."
    for i in $(seq 3 $((MEGA_POPULAR_FOLLOWERS + 2))); do
        curl -s -X POST $API_URL/subscriptions/follow \
            -H "X-User-ID: $i" \
            -H "Content-Type: application/json" \
            -d "{\"followed_id\": 2}" > /dev/null &
        if [ $((i % 100)) -eq 0 ]; then
            wait
        fi
    done
    wait
    echo " Done"
    
    # Create normal user follows (user100 follows ~100 random users)
    echo -n "Creating follows for normal users..."
    curl -s -X POST $API_URL/subscriptions/follow \
        -H "X-User-ID: 100" \
        -H "Content-Type: application/json" \
        -d "{\"followed_id\": 1}" > /dev/null
    curl -s -X POST $API_URL/subscriptions/follow \
        -H "X-User-ID: 100" \
        -H "Content-Type: application/json" \
        -d "{\"followed_id\": 2}" > /dev/null
    for i in $(seq 3 98); do
        curl -s -X POST $API_URL/subscriptions/follow \
            -H "X-User-ID: 100" \
            -H "Content-Type: application/json" \
            -d "{\"followed_id\": $i}" > /dev/null &
        if [ $((i % 20)) -eq 0 ]; then
            wait
        fi
    done
    wait
    echo " Done"
    
    # Test tweet creation performance for different user types
    echo "Testing tweet creation performance..."
    
    # Normal user (few followers)
    echo -n "  Normal user: "
    total_time=0
    for i in $(seq 1 5); do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 999" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Normal user tweet $i\"}" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
    done
    avg_normal=$((total_time / 5))
    echo "${avg_normal}ms avg" | tee -a ../$RESULTS_FILE
    
    # Popular user
    echo -n "  Popular user ($POPULAR_USER_FOLLOWERS followers): "
    total_time=0
    for i in $(seq 1 5); do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 1" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Popular user tweet $i\"}" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
    done
    avg_popular=$((total_time / 5))
    echo "${avg_popular}ms avg (${avg_popular}x slower)" | tee -a ../$RESULTS_FILE
    
    # Mega-popular user
    echo -n "  Mega-popular user ($MEGA_POPULAR_FOLLOWERS followers): "
    total_time=0
    for i in $(seq 1 5); do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: 2" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Mega-popular user tweet $i\"}" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
    done
    avg_mega=$((total_time / 5))
    echo "${avg_mega}ms avg (${avg_mega}x slower)" | tee -a ../$RESULTS_FILE
    
    # Wait for async processing to complete (for async steps)
    if [ $step -ge 3 ]; then
        echo "Waiting for async processing..."
        sleep 10
    fi
    
    # Test feed read performance
    echo "Testing feed read performance..."
    total_time=0
    for i in $(seq 1 10); do
        start=$(date +%s%N)
        curl -s $API_URL/feed/ -H "X-User-ID: 100" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
    done
    avg_feed_time=$((total_time / 10))
    echo "  Feed read (100 follows): ${avg_feed_time}ms avg" | tee -a ../$RESULTS_FILE
    
    # Check queue sizes for async steps
    if [ $step -ge 3 ] && [ $step -le 5 ]; then
        queue_info=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues 2>/dev/null | grep feed_updates | head -1)
        echo "  Queue status: $queue_info" | tee -a ../$RESULTS_FILE
    fi
    
    # Check cache stats for step 6
    if [ $step -eq 6 ]; then
        # Try to get cache stats if endpoint exists
        cache_stats=$(curl -s http://localhost:$port/cache/stats 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "  Cache stats: $cache_stats" | tee -a ../$RESULTS_FILE
        fi
    fi
    
    echo "" | tee -a ../$RESULTS_FILE
    
    # Clean up
    docker-compose down -v
    cd ..
    
    sleep 5
}

# Run tests
echo "Starting performance tests with realistic follower model..."

test_step 1 "Basic Synchronous" "step1_basic" 8001
test_step 2 "Prepared Feed" "step2_prepared_feed" 8002
test_step 3 "Async Feed" "step3_async_feed" 8003
test_step 4 "Multi-Consumer" "step4_multiconsumer" 8004
test_step 5 "Production Balanced" "step5_balanced" 8005
test_step 6 "Cached" "step6_cached" 8006

echo -e "\n=== Performance Summary ==="
cat $RESULTS_FILE

echo -e "\n=== Analysis ==="
echo "Key observations with realistic follower model:"
echo ""
echo "1. Popular User Problem:"
echo "   - Tweet creation time grows linearly with follower count"
echo "   - Mega-popular users (2000 followers) significantly impact system"
echo ""
echo "2. Architecture Evolution:"
echo "   - Step 1: Synchronous fanout blocks on popular users"
echo "   - Step 2: Still synchronous, but optimized storage"
echo "   - Step 3: Async processing helps, but single worker bottleneck"
echo "   - Step 4: Multiple workers distribute load"
echo "   - Step 5: Smart routing optimizes for popular users"
echo "   - Step 6: Caching reduces repeated computations"
echo ""
echo "3. Real-world implications:"
echo "   - Celebrity with millions of followers would be catastrophic"
echo "   - Need special handling for high-follower accounts"
echo "   - Consider hybrid push/pull approach for popular users"
echo ""
echo "Results saved to: $RESULTS_FILE"