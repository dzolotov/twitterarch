#!/bin/bash

echo "=== PostgreSQL Version Check ==="
echo "Checking PostgreSQL 17 compatibility..."
echo ""

# Start only PostgreSQL service
docker-compose up -d postgres

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to start..."
sleep 10

# Check version
echo "PostgreSQL version:"
docker-compose exec postgres psql -U user -d twitter_db -c "SELECT version();" | grep PostgreSQL

# Check extensions available
echo -e "\nAvailable extensions:"
docker-compose exec postgres psql -U user -d twitter_db -c "SELECT name, comment FROM pg_available_extensions WHERE name IN ('pg_stat_statements', 'pg_trgm', 'btree_gin', 'btree_gist');"

# Create test schema to verify compatibility
echo -e "\nTesting schema creation..."
docker-compose exec postgres psql -U user -d twitter_db << EOF
-- Test table creation with various PostgreSQL 17 features
CREATE TABLE IF NOT EXISTS test_pg17 (
    id SERIAL PRIMARY KEY,
    data JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[]
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_test_created ON test_pg17(created_at);
CREATE INDEX IF NOT EXISTS idx_test_gin ON test_pg17 USING GIN(tags);

-- Test parallel query capabilities
EXPLAIN (ANALYZE, BUFFERS) 
SELECT COUNT(*) FROM generate_series(1, 1000000) s;

-- Clean up
DROP TABLE IF EXISTS test_pg17;

-- Show configuration relevant to performance
SHOW max_parallel_workers_per_gather;
SHOW work_mem;
SHOW shared_buffers;
EOF

echo -e "\nPostgreSQL 17 compatibility check completed!"
echo "Stopping PostgreSQL..."
docker-compose down

echo -e "\n=== Summary ==="
echo "PostgreSQL 17 includes these improvements for our architecture:"
echo "- Better parallel query execution (important for Step 1 JOINs)"
echo "- Improved B-tree performance (helps our feed_items indexes)"
echo "- Enhanced statistics collector (better query planning)"
echo "- Faster bulk inserts (helps Steps 2-6 feed updates)"
echo "- Better connection pooling (important for Steps 4-6 with multiple workers)"