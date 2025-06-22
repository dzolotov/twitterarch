from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, desc
from sqlalchemy.orm import selectinload, joinedload
from typing import List, Dict, Any
from datetime import datetime
from common.models import FeedItem as FeedItemModel, Tweet, Subscription, User
from common.schemas import FeedItem


class FeedService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.max_feed_size = 1000

    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """Get pre-computed feed from the feed_items table"""
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

    async def add_tweet_to_user_feed(self, tweet_data: Dict[str, Any]):
        """
        Step 4: Process individual user feed update.
        Each worker processes messages for specific users based on consistent hash.
        """
        user_id = tweet_data["user_id"]
        tweet_id = tweet_data["tweet_id"]
        created_at = datetime.fromisoformat(tweet_data["created_at"])
        
        # Check if already exists (idempotency)
        result = await self.db.execute(
            select(FeedItemModel).filter(
                FeedItemModel.user_id == user_id,
                FeedItemModel.tweet_id == tweet_id
            )
        )
        if result.scalar_one_or_none():
            return  # Already processed
        
        # Add to user's feed
        feed_item = FeedItemModel(
            user_id=user_id,
            tweet_id=tweet_id,
            created_at=created_at
        )
        self.db.add(feed_item)
        await self.db.commit()
        
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
        """Rebuild a user's feed from scratch"""
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