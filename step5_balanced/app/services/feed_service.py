from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, desc
from sqlalchemy.orm import selectinload, joinedload
from typing import List, Dict, Any
from datetime import datetime
from common.models import FeedItem as FeedItemModel, Tweet, Subscription, User
from common.schemas import FeedItem
from .metrics_service import MetricsService, track_time
from prometheus_client import Counter, Histogram

# Prometheus metrics
feed_update_counter = Counter('feed_updates_total', 'Total number of feed updates', ['status'])
feed_size_histogram = Histogram('feed_size_items', 'Size of user feeds')


class FeedService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.max_feed_size = 1000
        self.metrics = MetricsService()

    @track_time("feed.get_user_feed")
    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """Get pre-computed feed with metrics tracking"""
        self.metrics.increment("feed.read.attempt")
        
        result = await self.db.execute(
            select(FeedItemModel)
            .options(
                joinedload(FeedItemModel.tweet).joinedload(Tweet.author)
            )
            .filter(FeedItemModel.user_id == user_id)
            .order_by(desc(FeedItemModel.created_at))
            .offset(skip)
            .limit(limit)
        )
        feed_items = result.scalars().all()
        
        self.metrics.increment("feed.read.success")
        self.metrics.gauge("feed.items_returned", len(feed_items))
        
        return [
            FeedItem(
                tweet_id=item.tweet.id,
                content=item.tweet.content,
                author_id=item.tweet.author.id,
                author_username=item.tweet.author.username,
                created_at=item.tweet.created_at
            )
            for item in feed_items
        ]

    @track_time("feed.add_tweet_to_user")
    async def add_tweet_to_user_feed(self, tweet_data: Dict[str, Any]):
        """
        Step 5: Optimized feed update with monitoring
        """
        user_id = tweet_data["user_id"]
        tweet_id = tweet_data["tweet_id"]
        created_at = datetime.fromisoformat(tweet_data["created_at"])
        
        # Track attempt
        self.metrics.increment("feed.update.attempt", tags={"user_id": user_id})
        
        # Check for duplicate (idempotency)
        result = await self.db.execute(
            select(FeedItemModel).filter(
                FeedItemModel.user_id == user_id,
                FeedItemModel.tweet_id == tweet_id
            )
        )
        if result.scalar_one_or_none():
            self.metrics.increment("feed.update.duplicate")
            feed_update_counter.labels(status='duplicate').inc()
            return
        
        # Add to feed
        feed_item = FeedItemModel(
            user_id=user_id,
            tweet_id=tweet_id,
            created_at=created_at
        )
        self.db.add(feed_item)
        await self.db.commit()
        
        # Track success
        self.metrics.increment("feed.update.success")
        feed_update_counter.labels(status='success').inc()
        
        # Clean up old items
        await self._cleanup_old_feed_items(user_id)

    async def _cleanup_old_feed_items(self, user_id: int):
        """Remove old feed items with metrics"""
        # Count current items
        count_result = await self.db.execute(
            select(FeedItemModel.id)
            .filter(FeedItemModel.user_id == user_id)
        )
        total_items = len(count_result.all())
        
        # Track feed size
        feed_size_histogram.observe(total_items)
        self.metrics.gauge("feed.size", total_items, {"user_id": user_id})
        
        if total_items > self.max_feed_size:
            # Get oldest item to keep
            oldest_result = await self.db.execute(
                select(FeedItemModel.id)
                .filter(FeedItemModel.user_id == user_id)
                .order_by(desc(FeedItemModel.created_at))
                .offset(self.max_feed_size)
                .limit(1)
            )
            oldest_to_keep_id = oldest_result.scalar_one_or_none()
            
            if oldest_to_keep_id:
                # Delete old items
                deleted = await self.db.execute(
                    delete(FeedItemModel)
                    .filter(
                        FeedItemModel.user_id == user_id,
                        FeedItemModel.id < oldest_to_keep_id
                    )
                )
                await self.db.commit()
                
                self.metrics.increment("feed.cleanup.items_removed", deleted.rowcount)

    @track_time("feed.rebuild")
    async def rebuild_user_feed(self, user_id: int):
        """Rebuild feed with full metrics"""
        self.metrics.increment("feed.rebuild.attempt")
        
        # Delete existing items
        await self.db.execute(
            delete(FeedItemModel).filter(FeedItemModel.user_id == user_id)
        )
        
        # Get followed users
        result = await self.db.execute(
            select(Subscription.followed_id)
            .filter(Subscription.follower_id == user_id)
        )
        followed_ids = [row[0] for row in result]
        followed_ids.append(user_id)
        
        # Get recent tweets
        result = await self.db.execute(
            select(Tweet)
            .filter(Tweet.author_id.in_(followed_ids))
            .order_by(desc(Tweet.created_at))
            .limit(self.max_feed_size)
        )
        tweets = result.scalars().all()
        
        # Create new feed items
        feed_items = [
            FeedItemModel(
                user_id=user_id,
                tweet_id=tweet.id,
                created_at=tweet.created_at
            )
            for tweet in tweets
        ]
        
        if feed_items:
            self.db.add_all(feed_items)
        
        await self.db.commit()
        
        self.metrics.increment("feed.rebuild.success")
        self.metrics.gauge("feed.rebuild.items", len(feed_items))