# Step 2: Prepared Feed Architecture

This implementation introduces pre-computed feeds stored in the database for fast read operations.

## Features
- Pre-computed feeds stored as JSON in the database
- Fast feed reads (no JOIN queries)
- Synchronous fan-out on tweet creation
- Feed rebuilding on follow/unfollow

## Architecture Improvements
- Feed reads are now O(1) instead of O(n) where n is the number of followed users
- Feeds are stored as JSON arrays in the `feeds` table
- Trade-off: Slower tweet creation due to synchronous fan-out

## Architecture Issues
- Tweet creation blocks until all follower feeds are updated
- Can timeout with users who have many followers
- Still synchronous processing

## Running the Application

```bash
# From the python-twitter-arch directory
cd step2_prepared_feed

# Install dependencies
pip install -r ../requirements.txt

# Start the database
docker-compose -f ../docker-compose.yml up -d postgres

# Run the application
uvicorn main:app --reload --port 8002
```

## API Endpoints

Same as Step 1, but with different internal implementations:
- `GET /api/feed/` - Now reads from pre-computed feed (much faster)
- `POST /api/tweets/` - Now updates all follower feeds (slower)

## Running the Demo

A demo script is provided that creates a realistic test scenario:

```bash
# Run the demo script
./run_demo.sh
```

The demo creates:
- 2000 regular users
- 1 celebrity user (ID: 2001) with 500 followers
- Sample tweets from various users
- Performance measurements for different operations

## Performance Test

The demo script tests the performance characteristics of this architecture:
- Fast feed reads (pre-computed feeds)
- Slower tweet creation for users with many followers (synchronous fan-out)
- Celebrity user with 500 followers to demonstrate the fan-out bottleneck

```bash
# Manual performance testing
# Test feed performance (now fast regardless of followers)
time curl http://localhost:8002/api/feed/ -H "X-User-ID: 1"

# Test tweet creation (now slower with many followers)
time curl -X POST http://localhost:8002/api/tweets/ \
  -H "X-User-ID: 2001" \
  -H "Content-Type: application/json" \
  -d '{"content": "This will update all my followers feeds synchronously!"}'
```

## Database Schema Changes

Added `feeds` table:
- `user_id`: Foreign key to users
- `tweets`: JSON array of tweet data
- `updated_at`: Last update timestamp