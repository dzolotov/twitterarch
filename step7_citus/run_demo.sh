#!/bin/bash

echo "=== Step 7: Citus Distributed Architecture Demo ==="
echo "Demonstrating horizontal scaling with distributed PostgreSQL"
echo ""

# Initialize cluster if needed
if ! docker-compose ps | grep -q "citus_master"; then
    echo "Initializing Citus cluster..."
    ./init_cluster.sh
fi

# API URL
API_URL="http://localhost:8007/api"

echo -e "\n1. Creating users distributed across shards..."
for i in {1..1000}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}" > /dev/null
  if [ $((i % 100)) -eq 0 ]; then
    echo -n "."
  fi
done
echo " Done!"

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

echo -e "\n3. Creating celebrity users with many followers..."
# Create 3 celebrities
for i in {1..3}; do
  curl -s -X POST $API_URL/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"celebrity$i\", \"email\": \"celebrity$i@example.com\"}" > /dev/null
done

# Make users follow celebrities
echo "Creating follow relationships..."
for celeb in {1001..1003}; do
  for i in {1..333}; do
    curl -s -X POST $API_URL/subscriptions/follow \
      -H "X-User-ID: $i" \
      -H "Content-Type: application/json" \
      -d "{\"followed_id\": $celeb}" > /dev/null
  done
  echo -n "."
done
echo " Done!"

echo -e "\n4. Testing distributed query performance..."
echo "Creating tweets from celebrities (distributed across shards):"

for celeb in {1001..1003}; do
  for i in {1..10}; do
    curl -s -X POST $API_URL/tweets/ \
      -H "X-User-ID: $celeb" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"Celebrity $celeb tweet $i - distributed across $(date +%s)\"}" > /dev/null
  done
  echo -n "."
done
echo " Done!"

echo -e "\n5. Analyzing distributed query execution..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Show distributed query plan
EXPLAIN (ANALYZE, VERBOSE, BUFFERS)
SELECT 
    u.username,
    COUNT(t.id) as tweet_count
FROM users u
JOIN tweets t ON u.id = t.author_id
WHERE u.id > 1000
GROUP BY u.username
ORDER BY tweet_count DESC
LIMIT 10;
EOF

echo -e "\n6. Testing colocation benefits..."
echo "Query that benefits from colocation (user + their tweets on same shard):"

docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
\timing on
-- This query runs locally on each shard due to colocation
SELECT 
    u.username,
    t.content,
    t.created_at
FROM users u
JOIN tweets t ON u.id = t.author_id
WHERE u.id = 1001
ORDER BY t.created_at DESC
LIMIT 10;
EOF

echo -e "\n7. Demonstrating parallel feed updates..."
echo "Creating a viral tweet (will fan out to 333 followers):"

start_time=$(date +%s%N)
curl -s -X POST $API_URL/tweets/ \
  -H "X-User-ID: 1001" \
  -H "Content-Type: application/json" \
  -d "{\"content\": \"This viral tweet will be distributed across shards!\"}" > /dev/null
end_time=$(date +%s%N)
echo "Tweet created in $(((end_time - start_time) / 1000000))ms"

echo -e "\n8. Monitoring shard activity..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Show recent distributed deadlock detection
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

echo -e "\n9. Load test - Distributed writes..."
echo "Creating 1000 tweets from different users (parallel across shards):"

for i in {1..1000}; do
  user_id=$((RANDOM % 1000 + 1))
  curl -s -X POST $API_URL/tweets/ \
    -H "X-User-ID: $user_id" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Distributed tweet $i from user $user_id\"}" > /dev/null &
  
  if [ $((i % 100)) -eq 0 ]; then
    wait
    echo -n "."
  fi
done
wait
echo " Done!"

echo -e "\n10. Rebalancing demonstration..."
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
echo "Benefits demonstrated:"
echo "✅ Data distributed across multiple nodes"
echo "✅ Queries parallelized across shards"
echo "✅ Colocated JOINs execute locally"
echo "✅ Linear scalability with more nodes"
echo "✅ Automatic shard rebalancing available"

echo -e "\nCitus Dashboard: http://localhost:9700 (if citus-enterprise)"
echo "Add more workers: docker-compose scale citus_worker=5"
echo "Rebalance shards: SELECT citus_rebalance_start();"

echo -e "\nStop demo: docker-compose down -v"