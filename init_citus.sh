#!/bin/bash

echo "=== Initializing Citus Cluster ==="
echo "Setting up distributed PostgreSQL for all steps"
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

echo -e "\n=== Citus Cluster Initialized ==="
echo "Ready for distributed table creation"