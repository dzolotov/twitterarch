#!/bin/bash

# Wait for Citus master to be ready
until docker-compose -f docker-compose.citus.yml exec -T citus_master pg_isready -U user -d twitter_db > /dev/null 2>&1; do
  sleep 2
done

# Initialize Citus extension
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db << 'EOF' || true
CREATE EXTENSION IF NOT EXISTS citus;
EOF

# Add worker nodes
docker-compose -f docker-compose.citus.yml exec -T citus_master psql -U user -d twitter_db << 'EOF'
-- Add worker nodes
SELECT citus_add_node('citus_worker_1', 5432);
SELECT citus_add_node('citus_worker_2', 5432);

-- Set coordinator as data node
SELECT citus_set_coordinator_host('citus_master', 5432);
EOF