# Step 3: Asynchronous Feed with RabbitMQ

This implementation introduces asynchronous feed processing using RabbitMQ.

## Features
- Non-blocking tweet creation
- RabbitMQ for message queuing
- Background worker for feed updates
- Better write performance
- Eventual consistency for feeds

## Architecture Improvements
- Tweet creation returns immediately after publishing to RabbitMQ
- Feed updates happen in background worker
- System can handle spikes in tweet volume
- Decoupled tweet creation from feed fanout

## Running the Application

```bash
# From the python-twitter-arch directory
cd step3_async_feed

# Install dependencies
pip install -r ../requirements.txt

# Start services
docker-compose -f ../docker-compose.yml up -d postgres rabbitmq

# Run the application (includes background worker)
uvicorn main:app --reload --port 8003
```

## Testing

```bash
# Create a tweet (returns immediately)
time curl -X POST http://localhost:8003/api/tweets/ \
  -H "X-User-ID: 1" \
  -H "Content-Type: application/json" \
  -d '{"content": "This tweet is processed asynchronously!"}'

# Check RabbitMQ management UI
open http://localhost:15672
# Login: guest/guest

# Monitor logs to see async processing
# Feed updates happen in the background
```

## Architecture Components

1. **API Server**: Handles HTTP requests, publishes to RabbitMQ
2. **RabbitMQ**: Message broker for tweet events
3. **Feed Worker**: Consumes messages and updates feeds
4. **PostgreSQL**: Stores all data with relational feed_items table

## Message Flow

1. User creates tweet → Saved to DB
2. Tweet event published to RabbitMQ
3. API returns success immediately
4. Feed worker picks up message
5. Worker updates all follower feeds
6. Feeds are eventually consistent