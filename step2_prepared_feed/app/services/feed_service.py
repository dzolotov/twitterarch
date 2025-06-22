from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, desc
from sqlalchemy.orm import selectinload, joinedload
from typing import List
from datetime import datetime
from common.models import FeedItem as FeedItemModel, Tweet, Subscription, User
from common.schemas import FeedItem


class FeedService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.max_feed_size = 1000  # Maximum tweets to store in feed

    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """
        Step 2: Get pre-computed feed from the feed_items table.
        Much faster than JOIN queries in Step 1.
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

    async def add_tweet_to_followers_feeds(self, tweet: Tweet):
        """
        Fan-out: Add tweet to all followers' feeds.
        This is called synchronously after tweet creation in Step 2.
        """
        # Get all followers of the tweet author
        result = await self.db.execute(
            select(Subscription.follower_id)
            .filter(Subscription.followed_id == tweet.author_id)
        )
        follower_ids = [row[0] for row in result]
        
        # Add the author's own ID to update their feed too
        follower_ids.append(tweet.author_id)
        
        # Create feed items for all followers
        feed_items = []
        for user_id in follower_ids:
            feed_item = FeedItemModel(
                user_id=user_id,
                tweet_id=tweet.id,
                created_at=tweet.created_at
            )
            feed_items.append(feed_item)
        
        # Bulk insert all feed items
        self.db.add_all(feed_items)
        await self.db.commit()
        
        # Clean up old feed items if needed
        for user_id in follower_ids:
            await self._cleanup_old_feed_items(user_id)

    async def _cleanup_old_feed_items(self, user_id: int):
        """Remove old feed items beyond max_feed_size"""
        # Get the ID of the nth newest item
        subquery = (
            select(FeedItemModel.id)
            .filter(FeedItemModel.user_id == user_id)
            .order_by(desc(FeedItemModel.created_at))
            .offset(self.max_feed_size)
            .limit(1)
            .scalar_subquery()
        )
        
        # Delete items older than the nth item
        await self.db.execute(
            delete(FeedItemModel)
            .filter(
                FeedItemModel.user_id == user_id,
                FeedItemModel.created_at < select(FeedItemModel.created_at).filter(FeedItemModel.id == subquery).scalar_subquery()
            )
        )
        await self.db.commit()

    async def rebuild_user_feed(self, user_id: int):
        """
        Rebuild a user's feed from scratch.
        Useful when following/unfollowing users.
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