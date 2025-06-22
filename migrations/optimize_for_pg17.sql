-- Optimizations for PostgreSQL 17

-- Enable parallel index builds (new in PG17)
SET max_parallel_maintenance_workers = 4;

-- Optimize feed_items table for better performance
-- Add INCLUDE columns to avoid extra lookups (PG11+ feature, optimized in PG17)
DROP INDEX IF EXISTS idx_user_created;
CREATE INDEX CONCURRENTLY idx_user_created_include 
ON feed_items(user_id, created_at DESC) 
INCLUDE (tweet_id);

-- Partial index for active users (last 30 days)
CREATE INDEX CONCURRENTLY idx_feed_items_active_users 
ON feed_items(user_id, created_at DESC) 
WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '30 days';

-- Optimize tweets table
-- Better index for feed generation queries
DROP INDEX IF EXISTS idx_author_created;
CREATE INDEX CONCURRENTLY idx_author_created_include 
ON tweets(author_id, created_at DESC) 
INCLUDE (content);

-- Index for popular tweets (high engagement)
CREATE INDEX CONCURRENTLY idx_tweets_popular 
ON tweets(created_at DESC) 
WHERE author_id IN (
    SELECT followed_id 
    FROM subscriptions 
    GROUP BY followed_id 
    HAVING COUNT(*) > 100
);

-- Optimize subscriptions table
-- Covering index for feed rebuild queries
CREATE INDEX CONCURRENTLY idx_subscription_covering 
ON subscriptions(follower_id) 
INCLUDE (followed_id);

-- Statistics for better query planning in PG17
ALTER TABLE feed_items SET STATISTICS 1000;
ALTER TABLE tweets SET STATISTICS 1000;
ALTER TABLE subscriptions SET STATISTICS 500;

-- Enable parallel queries for specific tables
ALTER TABLE feed_items SET (parallel_workers = 4);
ALTER TABLE tweets SET (parallel_workers = 4);

-- Table partitioning for very large deployments (PG17 improvements)
-- Partition feed_items by month for easier maintenance
/*
-- Uncomment for production with millions of users
CREATE TABLE feed_items_partitioned (
    LIKE feed_items INCLUDING ALL
) PARTITION BY RANGE (created_at);

-- Create partitions for recent months
CREATE TABLE feed_items_y2024m01 PARTITION OF feed_items_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
    
CREATE TABLE feed_items_y2024m02 PARTITION OF feed_items_partitioned
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
-- etc...
*/

-- Analyze tables for query planner
ANALYZE feed_items;
ANALYZE tweets;
ANALYZE subscriptions;
ANALYZE users;

-- Show new PG17 settings
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE name IN (
    'max_parallel_workers_per_gather',
    'enable_partitionwise_join',
    'enable_partitionwise_aggregate',
    'jit',
    'parallel_leader_participation'
);