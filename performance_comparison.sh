#!/bin/bash

echo "=== Performance Comparison Across All Steps ==="
echo "This script runs the same workload on each architecture version"
echo ""

# Test parameters
NUM_USERS=100
NUM_FOLLOWERS=50
NUM_TWEETS=20

# Results file
RESULTS_FILE="performance_results.txt"
echo "Performance Test Results - $(date)" > $RESULTS_FILE
echo "Test params: $NUM_USERS users, $NUM_FOLLOWERS followers, $NUM_TWEETS tweets" >> $RESULTS_FILE
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
    echo -n "Creating users..."
    for i in $(seq 1 $NUM_USERS); do
        curl -s -X POST $API_URL/users/ \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
    done
    echo " Done"
    
    # Create celebrity
    curl -s -X POST $API_URL/users/ \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"celebrity\", \"email\": \"celebrity@example.com\"}" > /dev/null
    
    # Create followers
    echo -n "Creating followers..."
    for i in $(seq 1 $NUM_FOLLOWERS); do
        curl -s -X POST $API_URL/subscriptions/follow \
            -H "X-User-ID: $i" \
            -H "Content-Type: application/json" \
            -d "{\"followed_id\": $((NUM_USERS + 1))}" > /dev/null
    done
    echo " Done"
    
    # Test tweet creation performance
    echo "Testing tweet creation..."
    total_time=0
    for i in $(seq 1 $NUM_TWEETS); do
        start=$(date +%s%N)
        curl -s -X POST $API_URL/tweets/ \
            -H "X-User-ID: $((NUM_USERS + 1))" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"Performance test tweet $i\"}" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
        echo -n "."
    done
    echo ""
    avg_tweet_time=$((total_time / NUM_TWEETS))
    echo "Average tweet creation time: ${avg_tweet_time}ms" | tee -a ../$RESULTS_FILE
    
    # Wait for async processing to complete (for async steps)
    if [ $step -ge 3 ]; then
        echo "Waiting for async processing..."
        sleep 10
    fi
    
    # Test feed read performance
    echo "Testing feed reads..."
    total_time=0
    for i in $(seq 1 10); do
        user_id=$((RANDOM % NUM_FOLLOWERS + 1))
        start=$(date +%s%N)
        curl -s $API_URL/feed/ -H "X-User-ID: $user_id" > /dev/null
        end=$(date +%s%N)
        time_ms=$(((end - start) / 1000000))
        total_time=$((total_time + time_ms))
    done
    avg_feed_time=$((total_time / 10))
    echo "Average feed read time: ${avg_feed_time}ms" | tee -a ../$RESULTS_FILE
    
    # Check queue sizes for async steps
    if [ $step -ge 3 ] && [ $step -le 5 ]; then
        queue_info=$(docker-compose exec -T rabbitmq rabbitmqctl list_queues 2>/dev/null | grep feed_updates | head -1)
        echo "Queue status: $queue_info" | tee -a ../$RESULTS_FILE
    fi
    
    # Check cache stats for step 6
    if [ $step -eq 6 ]; then
        cache_stats=$(curl -s http://localhost:$port/cache/stats | jq -r '.cached_feeds')
        echo "Cached feeds: $cache_stats" | tee -a ../$RESULTS_FILE
    fi
    
    echo "" | tee -a ../$RESULTS_FILE
    
    # Clean up
    docker-compose down -v
    cd ..
    
    sleep 5
}

# Run tests
echo "Starting performance tests..."

test_step 1 "Basic Synchronous" "step1_basic" 8001
test_step 2 "Prepared Feed" "step2_prepared_feed" 8002
test_step 3 "Async Feed" "step3_async_feed" 8003
test_step 4 "Multi-Consumer" "step4_multiconsumer" 8004
test_step 5 "Production Balanced" "step5_balanced" 8005
test_step 6 "Cached" "step6_cached" 8006

echo -e "\n=== Performance Summary ==="
cat $RESULTS_FILE

echo -e "\n=== Analysis ==="
echo "Expected results:"
echo "- Step 1: Fast writes, slow reads (JOIN queries)"
echo "- Step 2: Slow writes (sync fanout), fast reads"
echo "- Step 3: Fast writes (async), fast reads, single worker bottleneck"
echo "- Step 4: Fast writes, fast reads, better throughput"
echo "- Step 5: Optimized routing, with metrics"
echo "- Step 6: Fastest reads (cache hits), efficient memory usage"

echo -e "\nResults saved to: $RESULTS_FILE"