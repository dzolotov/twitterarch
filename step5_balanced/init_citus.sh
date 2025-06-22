#!/bin/bash

echo "=== Initializing Citus for Step 5: Balanced Architecture ==="
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
-- Create users table if not exists
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create tweets table if not exists  
CREATE TABLE IF NOT EXISTS tweets (
    id SERIAL,
    content VARCHAR(280) NOT NULL,
    author_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, author_id)
);

-- Create subscriptions table if not exists
CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL,
    follower_id INTEGER NOT NULL,
    followed_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, follower_id),
    UNIQUE (follower_id, followed_id)
);

-- Create feed_items table if not exists
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

-- Distribute tables only if not already distributed
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_dist_partition WHERE logicalrelid = 'users'::regclass) THEN
        PERFORM create_distributed_table('users', 'id', shard_count => 32);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_dist_partition WHERE logicalrelid = 'tweets'::regclass) THEN
        PERFORM create_distributed_table('tweets', 'author_id', colocate_with => 'users');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_dist_partition WHERE logicalrelid = 'subscriptions'::regclass) THEN
        PERFORM create_distributed_table('subscriptions', 'follower_id', colocate_with => 'users');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_dist_partition WHERE logicalrelid = 'feed_items'::regclass) THEN
        PERFORM create_distributed_table('feed_items', 'user_id', colocate_with => 'users');
    END IF;
END $$;

-- Show distribution info
SELECT 
    logicalrelid::regclass AS table_name,
    column_to_column_name(logicalrelid, partkey) AS dist_column,
    colocationid
FROM pg_dist_partition
ORDER BY logicalrelid;
EOF

echo ""
echo "=== Citus Cluster Ready for Step 5 ==="