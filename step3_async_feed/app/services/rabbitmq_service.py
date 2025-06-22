import aio_pika
from aio_pika import ExchangeType
import json
from typing import Dict, Any, Optional
from common.config import get_settings

settings = get_settings()


class RabbitMQService:
    def __init__(self):
        self.connection: Optional[aio_pika.Connection] = None
        self.channel: Optional[aio_pika.Channel] = None
        self.exchange: Optional[aio_pika.Exchange] = None

    async def connect(self):
        """Connect to RabbitMQ"""
        self.connection = await aio_pika.connect_robust(settings.rabbitmq_url)
        self.channel = await self.connection.channel()
        await self.channel.set_qos(prefetch_count=10)

    async def setup_exchanges(self):
        """Set up exchanges and queues"""
        # Create exchange for tweet events
        self.exchange = await self.channel.declare_exchange(
            "tweet_events",
            ExchangeType.DIRECT,
            durable=True
        )
        
        # Create queue for feed updates
        queue = await self.channel.declare_queue(
            "feed_updates",
            durable=True
        )
        
        # Bind queue to exchange
        await queue.bind(self.exchange, routing_key="new_tweet")

    async def publish_tweet_event(self, tweet_data: Dict[str, Any]):
        """Publish a new tweet event to RabbitMQ"""
        if not self.exchange:
            await self.connect()
            await self.setup_exchanges()
        
        message = aio_pika.Message(
            body=json.dumps(tweet_data).encode(),
            delivery_mode=aio_pika.DeliveryMode.PERSISTENT
        )
        
        await self.exchange.publish(
            message,
            routing_key="new_tweet"
        )

    async def close(self):
        """Close RabbitMQ connection"""
        if self.connection:
            await self.connection.close()