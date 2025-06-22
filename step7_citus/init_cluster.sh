#!/bin/bash

echo "=== Initializing Citus Cluster for Step 7 ==="
echo ""

# Start services
docker-compose up -d

# Wait for services
echo "Waiting for all services to start..."
sleep 20

# Initialize Citus
echo "Setting up Citus cluster..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Enable Citus
CREATE EXTENSION IF NOT EXISTS citus;

-- Add worker nodes
SELECT citus_add_node('citus_worker_1', 5432);
SELECT citus_add_node('citus_worker_2', 5432);
SELECT citus_add_node('citus_worker_3', 5432);

-- Verify cluster
SELECT * FROM citus_get_active_worker_nodes();
EOF

# Create distributed schema
echo "Creating distributed tables..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tweets table with composite key for distribution
CREATE TABLE IF NOT EXISTS tweets (
    id SERIAL,
    content VARCHAR(280) NOT NULL,
    author_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, author_id)
);

-- Subscriptions with composite key
CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL,
    follower_id INTEGER NOT NULL,
    followed_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, follower_id),
    UNIQUE (follower_id, followed_id)
);

-- Feed items with composite key
CREATE TABLE IF NOT EXISTS feed_items (
    id SERIAL,
    user_id INTEGER NOT NULL,
    tweet_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, user_id),
    UNIQUE (user_id, tweet_id)
);

-- Create indexes before distribution
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_tweets_author_created ON tweets(author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_subs_follower ON subscriptions(follower_id);
CREATE INDEX IF NOT EXISTS idx_subs_followed ON subscriptions(followed_id);
CREATE INDEX IF NOT EXISTS idx_feed_user_created ON feed_items(user_id, created_at DESC);

-- Distribute tables with colocation
SELECT create_distributed_table('users', 'id', shard_count => 32);
SELECT create_distributed_table('tweets', 'author_id', colocate_with => 'users');
SELECT create_distributed_table('subscriptions', 'follower_id', colocate_with => 'users');
SELECT create_distributed_table('feed_items', 'user_id', colocate_with => 'users');

-- Create reference table for common lookups (optional)
CREATE TABLE IF NOT EXISTS trending_hashtags (
    id SERIAL PRIMARY KEY,
    hashtag VARCHAR(100) UNIQUE NOT NULL,
    count INTEGER DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SELECT create_reference_table('trending_hashtags');

-- Show distribution info
SELECT 
    logicalrelid::regclass AS table_name,
    column_to_column_name(logicalrelid, partkey) AS dist_column,
    colocationid,
    replicationmodel
FROM pg_dist_partition
ORDER BY logicalrelid;

-- Show shard placement
SELECT 
    shard.logicalrelid::regclass AS table_name,
    placement.shardid,
    node.nodename,
    node.nodeport
FROM pg_dist_shard_placement placement
JOIN pg_dist_shard shard ON placement.shardid = shard.shardid
JOIN pg_dist_node node ON placement.placementid = node.nodeid
WHERE node.noderole = 'primary'
ORDER BY table_name, shardid
LIMIT 20;
EOF

echo -e "\n=== Citus Cluster Ready ==="
echo "Distributed architecture with:"
echo "- 1 Coordinator node"
echo "- 3 Worker nodes"
echo "- 32 shards per table"
echo "- Colocated tables for optimal JOIN performance"
echo ""
echo "Benefits:"
echo "- Linear scalability"
echo "- Distributed query execution"
echo "- Data locality for related tables"
echo "- Automatic shard rebalancing"