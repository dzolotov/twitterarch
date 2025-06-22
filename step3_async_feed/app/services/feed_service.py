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
        self.max_feed_size = 1000  # Maximum tweets to store in feed

    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """
        Step 3: Get pre-computed feed from the feed_items table.
        Same as Step 2, but feed updates happen asynchronously.
        """
        # Get feed items for the user with tweet and author data
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

    async def add_tweet_to_followers_feeds_async(self, tweet_data: Dict[str, Any]):
        """
        Step 3: Process tweet from RabbitMQ message.
        This runs in the background worker, not blocking tweet creation.
        """
        tweet_id = tweet_data["tweet_id"]
        author_id = tweet_data["author_id"]
        created_at = datetime.fromisoformat(tweet_data["created_at"])
        
        # Get all followers of the tweet author
        result = await self.db.execute(
            select(Subscription.follower_id)
            .filter(Subscription.followed_id == author_id)
        )
        follower_ids = [row[0] for row in result]
        
        # Add the author's own ID
        follower_ids.append(author_id)
        
        # Create feed items for all followers
        feed_items = []
        for user_id in follower_ids:
            feed_item = FeedItemModel(
                user_id=user_id,
                tweet_id=tweet_id,
                created_at=created_at
            )
            feed_items.append(feed_item)
        
        # Bulk insert all feed items
        if feed_items:
            self.db.add_all(feed_items)
            await self.db.commit()
        
        # Clean up old feed items
        for user_id in follower_ids:
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
            # Delete items older than the max_feed_size-th item
            await self.db.execute(
                delete(FeedItemModel)
                .filter(
                    FeedItemModel.user_id == user_id,
                    FeedItemModel.id < oldest_to_keep_id
                )
            )
            await self.db.commit()

    async def rebuild_user_feed(self, user_id: int):
        """
        Rebuild a user's feed from scratch.
        Used when following/unfollowing users.
        """
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
        followed_ids.append(user_id)  # Include own tweets
        
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
        
        # Bulk insert
        if feed_items:
            self.db.add_all(feed_items)
        
        await self.db.commit()