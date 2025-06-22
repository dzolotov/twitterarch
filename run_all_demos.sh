#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Twitter Architecture Evolution Demo ===${NC}"
echo "This script will demonstrate all 6 steps of the architecture evolution"
echo ""

# Function to run a demo
run_demo() {
    local step=$1
    local name=$2
    local dir=$3
    
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Step $step: $name${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    cd $dir
    
    # Clean up any existing containers
    docker-compose down -v 2>/dev/null
    
    # Run the demo
    ./run_demo.sh
    
    echo -e "\n${BLUE}Press ENTER to stop this demo and continue to the next one...${NC}"
    read
    
    # Stop the demo
    docker-compose down -v
    
    cd ..
}

# Check if specific step requested
if [ "$1" ]; then
    case $1 in
        1) run_demo 1 "Basic Synchronous Architecture" "step1_basic" ;;
        2) run_demo 2 "Prepared Feed with Pre-computed Storage" "step2_prepared_feed" ;;
        3) run_demo 3 "Asynchronous Processing with RabbitMQ" "step3_async_feed" ;;
        4) run_demo 4 "Multi-Consumer Architecture" "step4_multiconsumer" ;;
        5) run_demo 5 "Production-Ready with Monitoring" "step5_balanced" ;;
        6) run_demo 6 "Cached with Circular Buffers" "step6_cached" ;;
        *) echo "Invalid step. Use 1-6 or no argument for all demos." ;;
    esac
else
    # Run all demos
    echo "Running all demos in sequence..."
    echo "You can also run a specific demo with: ./run_all_demos.sh <step_number>"
    echo ""
    echo -e "${RED}Warning: This will take considerable time and resources!${NC}"
    echo "Press ENTER to continue or Ctrl+C to cancel..."
    read
    
    run_demo 1 "Basic Synchronous Architecture" "step1_basic"
    run_demo 2 "Prepared Feed with Pre-computed Storage" "step2_prepared_feed"
    run_demo 3 "Asynchronous Processing with RabbitMQ" "step3_async_feed"
    run_demo 4 "Multi-Consumer Architecture" "step4_multiconsumer"
    run_demo 5 "Production-Ready with Monitoring" "step5_balanced"
    run_demo 6 "Cached with Circular Buffers" "step6_cached"
    
    echo -e "\n${GREEN}All demos completed!${NC}"
fi

echo -e "\n${BLUE}=== Summary ===${NC}"
echo "Each step demonstrated how to solve specific scalability problems:"
echo "1. Basic: Simple but slow with many followers"
echo "2. Prepared Feed: Fast reads, slow writes"
echo "3. Async: Non-blocking writes with RabbitMQ"
echo "4. Multi-Consumer: Horizontal scaling with multiple workers"
echo "5. Production: Full monitoring and optimizations"
echo "6. Cached: Redis caching with circular buffers"

echo -e "\n${YELLOW}Clean up all Docker resources:${NC}"
echo "docker system prune -a"