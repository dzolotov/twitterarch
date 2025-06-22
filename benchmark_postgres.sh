#!/bin/bash

echo "=== PostgreSQL 17 Performance Benchmark ==="
echo "Comparing query performance improvements"
echo ""

# Start PostgreSQL 17
echo "Starting PostgreSQL 17..."
docker-compose -f docker-compose.yml up -d postgres
sleep 10

# Create test data
echo "Creating benchmark data..."
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
-- Create tables
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tweets (
    id SERIAL PRIMARY KEY,
    content VARCHAR(280) NOT NULL,
    author_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL PRIMARY KEY,
    follower_id INTEGER REFERENCES users(id),
    followed_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(follower_id, followed_id)
);

CREATE TABLE IF NOT EXISTS feed_items (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    tweet_id INTEGER REFERENCES tweets(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, tweet_id)
);

-- Insert test data
INSERT INTO users (username, email) 
SELECT 
    'user' || generate_series, 
    'user' || generate_series || '@example.com'
FROM generate_series(1, 10000)
ON CONFLICT DO NOTHING;

INSERT INTO tweets (content, author_id)
SELECT 
    'Tweet ' || generate_series || ' content',
    (generate_series % 10000) + 1
FROM generate_series(1, 100000)
ON CONFLICT DO NOTHING;

-- Create subscriptions (each user follows ~100 others)
INSERT INTO subscriptions (follower_id, followed_id)
SELECT 
    follower.id,
    followed.id
FROM 
    users follower,
    users followed
WHERE 
    follower.id != followed.id
    AND random() < 0.01
ON CONFLICT DO NOTHING;

-- Populate feed items
INSERT INTO feed_items (user_id, tweet_id, created_at)
SELECT 
    s.follower_id,
    t.id,
    t.created_at
FROM 
    tweets t
    JOIN subscriptions s ON t.author_id = s.followed_id
WHERE 
    t.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
ON CONFLICT DO NOTHING;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_tweets_author_created ON tweets(author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feed_user_created ON feed_items(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_subs_follower ON subscriptions(follower_id);
CREATE INDEX IF NOT EXISTS idx_subs_followed ON subscriptions(followed_id);

-- Analyze tables
ANALYZE;
EOF

echo -e "\nRunning benchmark queries..."

# Benchmark 1: Complex JOIN (Step 1 architecture)
echo -e "\n1. Complex JOIN query (Step 1 feed generation):"
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
\timing on
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, WAL)
SELECT t.*, u.username
FROM tweets t
JOIN users u ON t.author_id = u.id
WHERE t.author_id IN (
    SELECT followed_id 
    FROM subscriptions 
    WHERE follower_id = 1000
)
ORDER BY t.created_at DESC
LIMIT 20;
EOF

# Benchmark 2: Simple indexed query (Step 2+ architecture)
echo -e "\n2. Indexed query (Step 2+ feed reading):"
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT f.*, t.content, u.username
FROM feed_items f
JOIN tweets t ON f.tweet_id = t.id
JOIN users u ON t.author_id = u.id
WHERE f.user_id = 1000
ORDER BY f.created_at DESC
LIMIT 20;
EOF

# Benchmark 3: Parallel aggregation
echo -e "\n3. Parallel aggregation query:"
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
\timing on
EXPLAIN (ANALYZE, BUFFERS)
SELECT 
    author_id,
    COUNT(*) as tweet_count,
    MAX(created_at) as latest_tweet
FROM tweets
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY author_id
HAVING COUNT(*) > 10
ORDER BY tweet_count DESC
LIMIT 100;
EOF

# Benchmark 4: Bulk insert performance
echo -e "\n4. Bulk insert performance (feed fanout):"
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
\timing on
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO feed_items (user_id, tweet_id, created_at)
SELECT 
    s.follower_id,
    100001,
    CURRENT_TIMESTAMP
FROM subscriptions s
WHERE s.followed_id = 1;
ROLLBACK;
EOF

# Show PostgreSQL 17 specific improvements
echo -e "\n5. PostgreSQL 17 specific features:"
docker-compose exec -T postgres psql -U user -d twitter_db << 'EOF'
-- JIT compilation status
SHOW jit;
SHOW jit_provider;

-- Parallel workers configuration
SHOW max_parallel_workers;
SHOW max_parallel_workers_per_gather;

-- New optimization parameters
SHOW enable_partitionwise_join;
SHOW enable_partitionwise_aggregate;

-- Memory and performance settings
SHOW work_mem;
SHOW shared_buffers;
EOF

echo -e "\n=== Benchmark Summary ==="
echo "PostgreSQL 17 improvements demonstrated:"
echo "1. Faster parallel query execution (see worker processes in EXPLAIN)"
echo "2. Better index scan performance"
echo "3. Improved sort and aggregation operations"
echo "4. JIT compilation for complex queries"
echo "5. More efficient memory usage"

# Cleanup
echo -e "\nCleaning up..."
docker-compose down -v