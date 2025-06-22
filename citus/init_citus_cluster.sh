#!/bin/bash

echo "=== Initializing Citus Cluster ==="
echo "Setting up distributed PostgreSQL with Citus"
echo ""

# Start the cluster
echo "Starting Citus cluster..."
docker-compose -f docker-compose.citus.yml up -d

# Wait for all nodes to be ready
echo "Waiting for all nodes to be ready..."
sleep 20

# Initialize Citus on master
echo "Initializing Citus extension on master..."
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db << 'EOF'
CREATE EXTENSION IF NOT EXISTS citus;
EOF

# Add worker nodes to the cluster
echo "Adding worker nodes to cluster..."
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Add worker nodes
SELECT citus_add_node('citus_worker_1', 5432);
SELECT citus_add_node('citus_worker_2', 5432);
SELECT citus_add_node('citus_worker_3', 5432);

-- Verify cluster status
SELECT nodename, nodeport, isactive FROM pg_dist_node;
EOF

# Create distributed tables
echo "Creating distributed tables..."
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Create tables
CREATE TABLE IF NOT EXISTS users (
    id SERIAL,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS tweets (
    id SERIAL,
    content VARCHAR(280) NOT NULL,
    author_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, author_id)
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id SERIAL,
    follower_id INTEGER NOT NULL,
    followed_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, follower_id)
);

CREATE TABLE IF NOT EXISTS feed_items (
    id SERIAL,
    user_id INTEGER NOT NULL,
    tweet_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, user_id)
);

-- Create indexes before distribution
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_tweets_author_created ON tweets(author_id, created_at DESC);
CREATE INDEX idx_subs_follower ON subscriptions(follower_id);
CREATE INDEX idx_subs_followed ON subscriptions(followed_id);
CREATE INDEX idx_feed_user_created ON feed_items(user_id, created_at DESC);

-- Distribute tables
SELECT create_distributed_table('users', 'id');
SELECT create_distributed_table('tweets', 'author_id', colocate_with => 'users');
SELECT create_distributed_table('subscriptions', 'follower_id', colocate_with => 'users');
SELECT create_distributed_table('feed_items', 'user_id', colocate_with => 'users');

-- Verify distribution
SELECT 
    logicalrelid::regclass AS table_name,
    column_to_column_name(logicalrelid, partkey) AS distribution_column,
    colocationid
FROM pg_dist_partition
ORDER BY logicalrelid;

-- Show shard distribution
SELECT 
    logicalrelid::regclass AS table_name,
    count(*) AS shard_count,
    avg(shard_size)::bigint AS avg_shard_size
FROM pg_dist_shard
JOIN pg_dist_shard_placement USING (shardid)
JOIN (
    SELECT shardid, pg_relation_size(shard_name::regclass) AS shard_size
    FROM pg_dist_shard_placement
    JOIN pg_dist_shard USING (shardid)
) sizes USING (shardid)
GROUP BY logicalrelid
ORDER BY logicalrelid;
EOF

echo -e "\n=== Citus Cluster Initialized Successfully ==="
echo "Cluster topology:"
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db -c "SELECT * FROM citus_get_active_worker_nodes();"

echo -e "\nDistributed tables created with sharding on:"
echo "- users: sharded by id"
echo "- tweets: sharded by author_id (colocated with users)"
echo "- subscriptions: sharded by follower_id (colocated with users)"
echo "- feed_items: sharded by user_id (colocated with users)"

echo -e "\nBenefits of colocation:"
echo "- JOIN queries between user and their tweets are local"
echo "- Feed operations for a user are on the same shard"
echo "- Reduced network traffic for common queries"