# Step 1: Basic Synchronous Architecture

This is the simplest implementation of a Twitter-like API with synchronous processing.

## Features
- User management (CRUD)
- Tweet posting
- Follow/Unfollow functionality
- Real-time feed generation

## Architecture Issues
- Feed generation uses JOIN queries that become slow with many followed users
- No caching or pre-computation
- All operations are synchronous
- Poor scalability

## Running the Application

```bash
# From the python-twitter-arch directory
cd step1_basic

# Install dependencies
pip install -r ../requirements.txt

# Start the database
docker-compose -f ../docker-compose.yml up -d postgres

# Run the application
uvicorn main:app --reload --port 8001
```

## API Endpoints

- `POST /api/users/` - Create user
- `GET /api/users/{id}` - Get user
- `POST /api/tweets/` - Create tweet (requires X-User-ID header)
- `GET /api/feed/` - Get user feed (requires X-User-ID header)
- `POST /api/subscriptions/follow` - Follow user
- `DELETE /api/subscriptions/unfollow/{id}` - Unfollow user

## Performance Test

```bash
# Create users
for i in {1..100}; do
  curl -X POST http://localhost:8001/api/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}"
done

# Follow many users (this will make feed generation slow)
for i in {2..50}; do
  curl -X POST http://localhost:8001/api/subscriptions/follow \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": $i}"
done

# Test feed performance (will be slow)
time curl http://localhost:8001/api/feed/ -H "X-User-ID: 1"
```

## Running the Demo

The included `run_demo.sh` script creates 2000 users with user1 following 1999 users to demonstrate the performance impact:

```bash
./run_demo.sh
```

This will:
- Create 2000 users
- Make user1 follow all other 1999 users
- Create tweets from 200 users
- Test feed performance with 1999 subscriptions
- Run load tests to show the system under stress