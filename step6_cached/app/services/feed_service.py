from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, desc
from sqlalchemy.orm import selectinload, joinedload
from typing import List, Dict, Any, Optional
from datetime import datetime
from common.models import FeedItem as FeedItemModel, Tweet, Subscription, User
from common.schemas import FeedItem
from .cache_service import CacheService
import logging

logger = logging.getLogger(__name__)


class FeedService:
    def __init__(self, db: AsyncSession, cache: Optional[CacheService] = None):
        self.db = db
        self.cache = cache
        self.max_feed_size = 1000

    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """Get user feed - try cache first, then database"""
        # Try cache first
        if self.cache:
            cached_items = await self.cache.get_feed_cache(user_id, limit, skip)
            if cached_items:
                logger.info(f"Feed cache hit for user {user_id}")
                # Convert cached items to FeedItem objects
                return [
                    FeedItem(
                        tweet_id=item["tweet_id"],
                        content=item["content"],
                        author_id=item["author_id"],
                        author_username=item["author_username"],
                        created_at=datetime.fromisoformat(item["created_at"])
                    )
                    for item in cached_items
                ]
        
        logger.info(f"Feed cache miss for user {user_id}")
        
        # Fallback to database
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
        
        # Convert to schema
        items = [
            FeedItem(
                tweet_id=item.tweet.id,
                content=item.tweet.content,
                author_id=item.tweet.author.id,
                author_username=item.tweet.author.username,
                created_at=item.tweet.created_at
            )
            for item in feed_items
        ]
        
        # Warm cache if this is a hot user (getting the full feed)
        if self.cache and skip == 0 and len(items) > 0:
            # Get more items for cache warming
            full_result = await self.db.execute(
                select(FeedItemModel)
                .options(
                    joinedload(FeedItemModel.tweet).joinedload(Tweet.author)
                )
                .filter(FeedItemModel.user_id == user_id)
                .order_by(desc(FeedItemModel.created_at))
                .limit(100)  # Cache more items
            )
            full_items = full_result.scalars().all()
            
            # Add to cache
            for item in full_items:
                tweet_data = {
                    "tweet_id": item.tweet.id,
                    "content": item.tweet.content,
                    "author_id": item.tweet.author.id,
                    "author_username": item.tweet.author.username,
                    "created_at": item.tweet.created_at.isoformat()
                }
                await self.cache.add_to_feed_cache(user_id, tweet_data)
        
        return items

    async def add_tweet_to_user_feed(self, tweet_data: Dict[str, Any], message_id: str = None):
        """Add tweet to user's feed with caching and deduplication"""
        user_id = tweet_data["user_id"]
        tweet_id = tweet_data["tweet_id"]
        created_at = datetime.fromisoformat(tweet_data["created_at"])
        
        # Check message deduplication if cache available
        if self.cache and message_id:
            if await self.cache.is_message_processed(message_id):
                logger.info(f"Message {message_id} already processed, skipping")
                return
            await self.cache.mark_message_processed(message_id)
        
        # Check if already exists in DB
        result = await self.db.execute(
            select(FeedItemModel).filter(
                FeedItemModel.user_id == user_id,
                FeedItemModel.tweet_id == tweet_id
            )
        )
        if result.scalar_one_or_none():
            return
        
        # Add to database
        feed_item = FeedItemModel(
            user_id=user_id,
            tweet_id=tweet_id,
            created_at=created_at
        )
        self.db.add(feed_item)
        await self.db.commit()
        
        # Add to cache if available
        if self.cache:
            cache_data = {
                "tweet_id": tweet_id,
                "content": tweet_data.get("content", ""),
                "author_id": tweet_data.get("author_id"),
                "author_username": tweet_data.get("author_username", ""),
                "created_at": created_at.isoformat()
            }
            await self.cache.add_to_feed_cache(user_id, cache_data)
            
            # Also cache the tweet itself
            await self.cache.cache_tweet(tweet_id, cache_data)
        
        # Clean up old items
        await self._cleanup_old_feed_items(user_id)

    async def _cleanup_old_feed_items(self, user_id: int):
        """Remove old feed items beyond max_feed_size"""
        # Get the count of items
        count_result = await self.db.execute(
            select(FeedItemModel.id)
            .filter(FeedItemModel.user_id == user_id)
            .order_by(desc(FeedItemModel.created_at))
            .offset(self.max_feed_size)
            .limit(1)
        )
        oldest_to_keep_id = count_result.scalar_one_or_none()
        
        if oldest_to_keep_id:
            await self.db.execute(
                delete(FeedItemModel)
                .filter(
                    FeedItemModel.user_id == user_id,
                    FeedItemModel.id < oldest_to_keep_id
                )
            )
            await self.db.commit()

    async def rebuild_user_feed(self, user_id: int):
        """Rebuild user's feed and invalidate cache"""
        # Invalidate cache first
        if self.cache:
            await self.cache.invalidate_user_cache(user_id)
        
        # Delete existing feed items
        await self.db.execute(
            delete(FeedItemModel).filter(FeedItemModel.user_id == user_id)
        )
        
        # Get users that this user follows
        result = await self.db.execute(
            select(Subscription.followed_id)
            .filter(Subscription.follower_id == user_id)
        )
        followed_ids = [row[0] for row in result]
        followed_ids.append(user_id)
        
        # Get recent tweets from followed users
        result = await self.db.execute(
            select(Tweet)
            .options(selectinload(Tweet.author))
            .filter(Tweet.author_id.in_(followed_ids))
            .order_by(desc(Tweet.created_at))
            .limit(self.max_feed_size)
        )
        tweets = result.scalars().all()
        
        # Create new feed items
        feed_items = []
        cache_items = []
        
        for tweet in tweets:
            feed_item = FeedItemModel(
                user_id=user_id,
                tweet_id=tweet.id,
                created_at=tweet.created_at
            )
            feed_items.append(feed_item)
            
            # Prepare cache data
            if self.cache:
                cache_items.append({
                    "tweet_id": tweet.id,
                    "content": tweet.content,
                    "author_id": tweet.author.id,
                    "author_username": tweet.author.username,
                    "created_at": tweet.created_at.isoformat()
                })
        
        # Bulk insert
        if feed_items:
            self.db.add_all(feed_items)
        
        await self.db.commit()
        
        # Warm cache with rebuilt feed
        if self.cache and cache_items:
            for item in cache_items[:100]:  # Cache top 100 items
                await self.cache.add_to_feed_cache(user_id, item)