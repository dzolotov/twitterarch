# Step 5: Production-Ready Multi-Consumer with Monitoring

The final implementation with full monitoring, metrics, and production optimizations.

## Features
- Prometheus metrics integration
- StatsD for custom application metrics
- Grafana dashboards for visualization
- Optimized message routing (hash: 20)
- Batch message publishing
- Graceful shutdown handling
- Queue size limits and TTL
- Comprehensive error tracking

## Architecture Improvements
- Full observability with metrics
- Optimized routing for better distribution
- Batch processing for efficiency
- Production-ready error handling
- Resource limits on queues
- Performance monitoring

## Running the Application

```bash
# From the python-twitter-arch directory
cd step5_balanced

# Install dependencies
pip install -r ../requirements.txt

# Start all services
docker-compose -f ../docker-compose.yml up -d

# Terminal 1: Run the API server
uvicorn main:app --reload --port 8005

# Terminal 2-5: Run workers with monitoring
python worker.py 0
python worker.py 1
python worker.py 2
python worker.py 3
```

## Monitoring

### Prometheus Metrics
- Available at: http://localhost:8005/metrics
- Tracks: tweets created, feed updates, worker performance

### Grafana Dashboards
- URL: http://localhost:3000
- Login: admin/admin
- Import dashboard from `grafana-dashboard.json`

### StatsD Metrics
- Custom application metrics
- Processing times, queue sizes, error rates

## Performance Testing

```bash
# Create test users
for i in {1..1000}; do
  curl -X POST http://localhost:8005/api/users/ \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"user$i\", \"email\": \"user$i@example.com\"}"
done

# Create followers
for i in {2..500}; do
  curl -X POST http://localhost:8005/api/subscriptions/follow \
    -H "X-User-ID: $i" \
    -H "Content-Type: application/json" \
    -d "{\"followed_id\": 1}"
done

# Load test with monitoring
while true; do
  curl -X POST http://localhost:8005/api/tweets/ \
    -H "X-User-ID: 1" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"Load test tweet $(date)\"}"
  sleep 0.1
done

# Monitor in Grafana
open http://localhost:3000
```

## Production Optimizations

1. **Batch Publishing**: Messages published in batches of 100
2. **Optimized Routing**: Hash key 20 for better distribution
3. **Queue Limits**: Max 100k messages, 1-hour TTL
4. **Prefetch Tuning**: Workers prefetch 50 messages
5. **Connection Naming**: Named connections for debugging
6. **Graceful Shutdown**: Proper signal handling

## Metrics Available

### Prometheus
- `tweets_created_total`: Tweet creation counter
- `feed_updates_total{status}`: Feed updates by status
- `worker_messages_processed_total{worker_id,status}`: Worker performance
- `worker_processing_time_seconds`: Processing time histogram
- `api_request_duration_seconds`: API latency
- `feed_size_items`: Feed size distribution

### StatsD
- `twitter_app.tweet.create.success/error`: Tweet creation
- `twitter_app.feed.update.*`: Feed operations
- `twitter_app.worker.*.queue_size`: Queue monitoring
- `twitter_app.rabbitmq.batch_published`: Publishing metrics

## Architecture Summary

This final implementation demonstrates:
- Horizontal scaling with multiple workers
- Full observability and monitoring
- Production-ready error handling
- Performance optimizations
- Resource management
- Graceful degradation

The system can handle thousands of tweets per minute with sub-second feed updates while providing complete visibility into system performance.