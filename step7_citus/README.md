# Step 7: Horizontally Scaled with Citus

Ultimate scalability with distributed PostgreSQL using Citus.

## Features
- Distributed tables across multiple nodes
- Automatic sharding of data
- Colocated tables for efficient JOINs
- Linear scalability with more nodes
- All previous optimizations (caching, monitoring, etc.)

## Architecture

```
                    ┌─────────────────┐
                    │   Application   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Citus Master    │
                    │  (Coordinator)  │
                    └────────┬────────┘
                             │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
    ┌─────▼─────┐    ┌─────▼─────┐    ┌─────▼─────┐
    │  Worker 1  │    │  Worker 2  │    │  Worker 3  │
    │  Shards    │    │  Shards    │    │  Shards    │
    │   1-10     │    │   11-20    │    │   21-32    │
    └────────────┘    └────────────┘    └────────────┘
```

## Sharding Strategy

### Distribution Columns:
- **users**: `id` - Each user's data on one shard
- **tweets**: `author_id` - Colocated with user
- **subscriptions**: `follower_id` - Colocated with follower
- **feed_items**: `user_id` - Colocated with user

### Benefits of Colocation:
1. User + their tweets on same shard = fast profile queries
2. User + their feed on same shard = fast feed reads
3. User + their subscriptions on same shard = efficient follows

## Running the Demo

```bash
cd step7_citus

# Initialize Citus cluster
./init_cluster.sh

# Run the application
./run_demo.sh
```

## Performance at Scale

With Citus, the system can handle:
- Millions of users
- Billions of tweets
- Linear scaling by adding nodes
- Geographic distribution possible

## Citus-Specific Optimizations

1. **Distributed Queries**: Automatically parallelized across shards
2. **Local JOINs**: Colocated data means no network overhead
3. **Reference Tables**: Small tables replicated to all nodes
4. **Columnar Storage**: Optional for analytics workloads