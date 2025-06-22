# Step 4: Multi-Consumer Architecture

This implementation uses multiple workers with consistent hash routing for better scalability.

## Features
- Multiple feed workers for parallel processing
- Consistent hash exchange for load distribution
- Individual messages per follower for fine-grained parallelism
- Horizontal scaling capability

## Architecture Improvements
- Each follower feed update is a separate message
- Workers are assigned messages based on consistent hashing of user_id
- Better resource utilization with multiple workers
- Can handle users with many followers without blocking

## Running the Application

```bash
# From the python-twitter-arch directory
cd step4_multiconsumer

# Install dependencies
pip install -r ../requirements.txt

# Start services
docker-compose -f ../docker-compose.yml up -d postgres rabbitmq

# Terminal 1: Run the API server
uvicorn main:app --reload --port 8004

# Terminal 2-5: Run workers (4 workers)
python worker.py 0
python worker.py 1
python worker.py 2
python worker.py 3
```

## Testing Load Distribution

```bash
# Create users
for i in {1..100}; do
  curl -X POST http://localhost:8004/api/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}"
done

# Create many followers for user 1
for i in {2..100}; do
  curl -X POST http://localhost:8004/api/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 1}"
done

# Post a tweet (will create 99 messages, distributed across workers)
curl -X POST http://localhost:8004/api/tweets/ \
  -H "X-User-ID: 1" \
  -H "Content-Type: application/json" \
  -d '{"content": "This tweet fans out to 99 followers across 4 workers!"}'

# Check worker status
curl http://localhost:8004/workers/status
```

## Architecture Components

1. **Consistent Hash Exchange**: Distributes messages based on user_id
2. **Multiple Workers**: Each handles a subset of users
3. **Per-Follower Messages**: Fine-grained parallelism
4. **Worker Queues**: Each worker has its own queue

## Scaling

- Add more workers by running `python worker.py <new_id>`
- Workers automatically handle their share of messages
- Consistent hashing ensures even distribution