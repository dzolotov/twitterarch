import asyncio
import aio_pika
import json
import logging
import sys
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from common.database import async_session_maker
from common.config import get_settings
from ..services.feed_service import FeedService
from ..services.metrics_service import MetricsService
from prometheus_client import Counter, Histogram
import time

logger = logging.getLogger(__name__)
settings = get_settings()

# Worker metrics
messages_processed = Counter('worker_messages_processed_total', 'Messages processed by workers', ['worker_id', 'status'])
processing_time = Histogram('worker_processing_time_seconds', 'Time to process messages', ['worker_id'])


class FeedWorker:
    def __init__(self, worker_id: int):
        self.worker_id = worker_id
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.queue: Optional[aio_pika.Queue] = None
        self.running = False
        self.metrics = MetricsService()
        self.processed_count = 0

    async def start(self):
        """Start optimized feed worker with monitoring"""
        self.running = True
        logger.info(f"Starting optimized feed worker {self.worker_id}...")
        
        # Track worker start
        self.metrics.increment(f"worker.{self.worker_id}.started")
        
        try:
            # Connect to RabbitMQ with optimized settings
            self.connection = await aio_pika.connect_robust(
                settings.rabbitmq_url,
                client_properties={
                    'connection_name': f'feed_worker_{self.worker_id}'
                }
            )
            self.channel = await self.connection.channel()
            
            # Optimized prefetch for better throughput
            await self.channel.set_qos(prefetch_count=50)
            
            # Connect to specific worker queue
            self.queue = await self.channel.declare_queue(
                f"feed_updates_balanced_{self.worker_id}",
                durable=True
            )
            
            # Start consuming with error handling
            await self.queue.consume(self.process_message)
            
            logger.info(f"Feed worker {self.worker_id} started successfully")
            
            # Report metrics periodically
            metric_task = asyncio.create_task(self._report_metrics())
            
            # Keep running
            while self.running:
                await asyncio.sleep(1)
            
            metric_task.cancel()
                
        except Exception as e:
            logger.error(f"Feed worker {self.worker_id} error: {e}")
            self.metrics.increment(f"worker.{self.worker_id}.error")
            raise
        finally:
            await self.cleanup()

    async def process_message(self, message: aio_pika.IncomingMessage):
        """Process message with full monitoring"""
        start_time = time.time()
        
        async with message.process():
            try:
                # Parse message
                data = json.loads(message.body.decode())
                user_id = data["user_id"]
                
                # Track processing
                self.metrics.increment(f"worker.{self.worker_id}.message.received")
                
                # Process feed update
                async with async_session_maker() as db:
                    feed_service = FeedService(db)
                    await feed_service.add_tweet_to_user_feed(data)
                
                # Track success
                duration = time.time() - start_time
                processing_time.labels(worker_id=self.worker_id).observe(duration)
                messages_processed.labels(worker_id=self.worker_id, status='success').inc()
                self.metrics.timing(f"worker.{self.worker_id}.processing_time", duration)
                
                self.processed_count += 1
                
                # Log progress every 100 messages
                if self.processed_count % 100 == 0:
                    logger.info(f"Worker {self.worker_id} processed {self.processed_count} messages")
                
            except Exception as e:
                # Track error
                duration = time.time() - start_time
                messages_processed.labels(worker_id=self.worker_id, status='error').inc()
                self.metrics.increment(f"worker.{self.worker_id}.message.error")
                logger.error(f"Worker {self.worker_id} error processing message: {e}")
                raise

    async def _report_metrics(self):
        """Report worker metrics periodically"""
        while self.running:
            try:
                # Report queue size if available
                if self.queue:
                    queue_info = await self.queue.channel.queue_declare(
                        queue=self.queue.name,
                        passive=True
                    )
                    self.metrics.gauge(
                        f"worker.{self.worker_id}.queue_size", 
                        queue_info.message_count
                    )
                
                # Report processed count
                self.metrics.gauge(
                    f"worker.{self.worker_id}.total_processed",
                    self.processed_count
                )
                
                await asyncio.sleep(10)  # Report every 10 seconds
                
            except Exception as e:
                logger.error(f"Error reporting metrics: {e}")

    async def stop(self):
        """Stop worker gracefully"""
        logger.info(f"Stopping feed worker {self.worker_id}...")
        self.running = False
        self.metrics.increment(f"worker.{self.worker_id}.stopped")
        await self.cleanup()

    async def cleanup(self):
        """Clean up resources"""
        if self.queue:
            await self.queue.cancel_consumer()
        if self.channel:
            await self.channel.close()
        if self.connection:
            await self.connection.close()


async def main():
    """Run worker as standalone process"""
    if len(sys.argv) < 2:
        print("Usage: python -m app.workers.feed_worker <worker_id>")
        sys.exit(1)
    
    worker_id = int(sys.argv[1])
    worker = FeedWorker(worker_id)
    
    try:
        await worker.start()
    except KeyboardInterrupt:
        await worker.stop()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    asyncio.run(main())