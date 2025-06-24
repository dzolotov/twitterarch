#!/bin/bash

echo "=== Initializing Citus for Step 1 ==="
echo ""

# Wait for Citus master to be ready
until docker-compose exec -T citus_master pg_isready -U user -d twitter_db > /dev/null 2>&1; do
  echo "Waiting for Citus master to be ready..."
  sleep 2
done

# Initialize Citus extension
echo "Creating Citus extension..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF' || true
CREATE EXTENSION IF NOT EXISTS citus;
EOF

# Add worker nodes
echo "Adding worker nodes..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Remove existing nodes if any
DELETE FROM pg_dist_node WHERE nodename LIKE 'citus_worker_%';

-- Add worker nodes
SELECT citus_add_node('citus_worker_1', 5432);
SELECT citus_add_node('citus_worker_2', 5432);
SELECT citus_add_node('citus_worker_3', 5432);

-- Set coordinator as data node (allows storing data on coordinator too)
SELECT citus_set_coordinator_host('citus_master', 5432);

-- Verify cluster
SELECT * FROM citus_get_active_worker_nodes();
EOF

# Create distributed tables
echo "Creating distributed tables..."
docker-compose exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Drop existing tables if they exist
DROP TABLE IF EXISTS feed_items CASCADE;
DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS tweets CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Create users table
CREATE TABLE users (
    id SERIAL,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);

-- Create tweets table  
CREATE TABLE tweets (
    id SERIAL,
    content VARCHAR(280) NOT NULL,
    author_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, author_id)
);

-- Create subscriptions table
CREATE TABLE subscriptions (
    id SERIAL,
    follower_id INTEGER NOT NULL,
    followed_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, follower_id),
    UNIQUE (follower_id, followed_id)
);

-- Create feed_items table (without foreign keys for now)
CREATE TABLE feed_items (
    id SERIAL,
    user_id INTEGER NOT NULL,
    tweet_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, user_id),
    UNIQUE (user_id, tweet_id)
);

-- Distribute tables
SELECT create_distributed_table('users', 'id', shard_count => 32);
SELECT create_distributed_table('tweets', 'author_id', colocate_with => 'users');
SELECT create_distributed_table('subscriptions', 'follower_id', colocate_with => 'users');
SELECT create_distributed_table('feed_items', 'user_id', colocate_with => 'users');

-- Create indexes after distribution
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_tweets_author_created ON tweets(author_id, created_at DESC);
CREATE INDEX idx_subs_follower ON subscriptions(follower_id);
CREATE INDEX idx_subs_followed ON subscriptions(followed_id);
CREATE INDEX idx_feed_user_created ON feed_items(user_id, created_at DESC);

-- Show distribution info
SELECT 
    logicalrelid::regclass AS table_name,
    column_to_column_name(logicalrelid, partkey) AS dist_column,
    colocationid
FROM pg_dist_partition
ORDER BY logicalrelid;
EOF

echo ""
echo "=== Citus Cluster Ready for Step 1 ==="