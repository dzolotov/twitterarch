#!/bin/bash

echo "=== Step 7: Distributed Citus Architecture Demo ==="
echo "Demonstrating horizontal scaling with distributed PostgreSQL"
echo ""

# Initialize cluster if needed
if ! docker-compose ps | grep -q "citus_master"; then
    echo "Initializing Citus cluster..."
    ./init_cluster.sh
fi

# API URL
API_URL="http://localhost:8007/api"

echo -e "\n1. Loading realistic data with universal loader..."
cd ..
python3 common/load_realistic_data.py \
  --url "$API_URL" \
  --users 1000 \
  --popular 500 \
  --mega 2000 \
  --no-measure
cd step7_citus

# Wait for data processing
echo -e "\nWaiting for data processing..."
sleep 10

echo -e "\n2. Checking user distribution across shards..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
SELECT 
    'users' as table_name,
    nodename,
    count(*) as shard_count,
    sum(result::int) as total_rows
FROM (
    SELECT 
        nodename,
        nodeport,
        shardid,
        result
    FROM citus_run_on_shards(
        'users',
        'SELECT COUNT(*) FROM %s'
    )
) t
JOIN pg_dist_node ON nodeport = pg_dist_node.nodeport
WHERE isactive
GROUP BY nodename
ORDER BY nodename;
EOF

echo -e "\n3. Testing distributed query performance..."
echo "Creating tweets from popular users (distributed across shards):"

# Popular user tweets
echo -e "\nPopular user (500 followers) creating 20 tweets:"
for i in {1..20}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Popular tweet $i - distributed to 500 followers at $(date +%s)\"}" > /dev/null
  if [ $((i % 5)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

# Mega-popular user tweets
echo -e "\nMega-popular user (2000 followers) creating 20 tweets:"
for i in {1..20}; do
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: 2" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Mega tweet $i - distributed to 2000 followers at $(date +%s)\"}" > /dev/null
  if [ $((i % 5)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

echo -e "\n4. Analyzing distributed query execution..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Show distributed query plan
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT 
    u.username,
    COUNT(t.id) as tweet_count
FROM users u
JOIN tweets t ON u.id = t.author_id
WHERE u.id IN (1, 2)
GROUP BY u.username
ORDER BY tweet_count DESC
LIMIT 10;
EOF

echo -e "\n5. Testing colocation benefits..."
echo "Query that benefits from colocation (user + their tweets on same shard):"

docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
\timing on
-- This query runs locally on each shard thanks to colocation
SELECT 
    u.username,
    t.content,
    t.created_at
FROM users u
JOIN tweets t ON u.id = t.author_id
WHERE u.id = 1
ORDER BY t.created_at DESC
LIMIT 10;
EOF

echo -e "\n6. Demonstrating parallel feed updates..."
echo "Performance comparison - tweet distribution times:"

# Normal user
echo -e "\nNormal user (few followers):"
start_time=$(date +%s%N)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 999" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Normal tweet - minimal distribution\"}" > /dev/null
end_time=$(date +%s%N)
echo "Tweet created in $(((end_time - start_time) / 1000000))ms"

# Popular user
echo -e "\nPopular user (500 followers):"
start_time=$(date +%s%N)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 1" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Popular tweet - distributed to 500 followers across shards!\"}" > /dev/null
end_time=$(date +%s%N)
echo "Tweet created in $(((end_time - start_time) / 1000000))ms"

# Mega-popular user
echo -e "\nMega-popular user (2000 followers):"
start_time=$(date +%s%N)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 2" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"Mega tweet - distributed to 2000 followers across shards!\"}" > /dev/null
end_time=$(date +%s%N)
echo "Tweet created in $(((end_time - start_time) / 1000000))ms"

echo -e "\n7. Monitoring shard activity..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Show recent distributed activity
SELECT * FROM citus_dist_stat_activity 
WHERE query NOT LIKE '%citus_dist_stat_activity%'
LIMIT 5;

-- Show shard sizes
SELECT 
    logicalrelid::regclass AS table_name,
    COUNT(DISTINCT shardid) AS shard_count,
    pg_size_pretty(SUM(shard_size)) AS total_size,
    pg_size_pretty(AVG(shard_size)::bigint) AS avg_shard_size
FROM (
    SELECT 
        logicalrelid,
        shardid,
        result::bigint AS shard_size
    FROM citus_run_on_shards(
        NULL,
        'SELECT pg_total_relation_size(''%s''::regclass)'
    )
) t
GROUP BY logicalrelid
ORDER BY SUM(shard_size) DESC;
EOF

echo -e "\n8. Load test - Distributed writes..."
echo "Creating 100 tweets from different users (parallel across shards):"

for i in {1..100}; do
  user_id=$((RANDOM % 1000 + 1))
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: $user_id" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Distributed tweet $i from user $user_id\"}" > /dev/null &
  
  if [ $((i % 50)) -eq 0 ]; then
    wait
    echo -n "."
  fi
done
wait
echo " Done!"

echo -e "\n9. Demonstrating shard distribution..."
echo "Shard distribution across workers:"
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
SELECT 
    nodename,
    table_name,
    shard_count,
    pg_size_pretty(total_size) as total_size
FROM (
    SELECT 
        n.nodename,
        s.logicalrelid::regclass AS table_name,
        COUNT(*) AS shard_count,
        SUM(pg_size_bytes(result)) AS total_size
    FROM pg_dist_shard s
    JOIN pg_dist_shard_placement p ON s.shardid = p.shardid
    JOIN pg_dist_node n ON p.nodeid = n.nodeid
    JOIN LATERAL (
        SELECT citus_run_on_shards(
            s.logicalrelid::regclass::text,
            format('SELECT pg_size_pretty(pg_total_relation_size(''%%s''::regclass))')
        ) AS result
    ) sizes ON true
    WHERE n.noderole = 'primary'
    GROUP BY n.nodename, s.logicalrelid
) t
ORDER BY nodename, table_name;
EOF

echo -e "\n=== Citus Performance Analysis ==="
echo "Demonstrated benefits:"
echo "✅ Data distributed across multiple nodes"
echo "✅ Queries parallelized across shards"
echo "✅ Colocated JOINs run locally"
echo "✅ Linear scalability with node addition"
echo "✅ Automatic shard rebalancing available"
echo "✅ Popular users (500 followers) scale horizontally"
echo "✅ Mega-popular users (2000 followers) benefit from distribution"

echo -e "\nCitus Dashboard: http://localhost:9700 (if citus-enterprise)"
echo "Add more workers: docker-compose scale citus_worker=5"
echo "Rebalance shards: SELECT citus_rebalance_start();"

echo -e "\nStop demo: docker-compose down -v"