from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from typing import List, Optional
from common.models import Tweet, User
from common.schemas import TweetCreate
from .feed_service import FeedService


class TweetService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_tweet(self, user_id: int, tweet_data: TweetCreate) -> Tweet:
        """
        Step 2: Create tweet and update followers' feeds synchronously.
        This blocks until all feeds are updated.
        """
        tweet = Tweet(
            content=tweet_data.content,
            author_id=user_id
        )
        self.db.add(tweet)
        await self.db.commit()
        await self.db.refresh(tweet)
        
        # Load author relationship
        result = await self.db.execute(
            select(Tweet)
            .options(selectinload(Tweet.author))
            .filter(Tweet.id == tweet.id)
        )
        tweet = result.scalar_one()
        
        # Fan-out: Update all followers' feeds (synchronous in Step 2)
        feed_service = FeedService(self.db)
        await feed_service.add_tweet_to_followers_feeds(tweet)
        
        return tweet

    async def get_tweet(self, tweet_id: int) -> Optional[Tweet]:
        result = await self.db.execute(
            select(Tweet)
            .options(selectinload(Tweet.author))
            .filter(Tweet.id == tweet_id)
        )
        return result.scalar_one_or_none()

    async def get_user_tweets(self, user_id: int, skip: int = 0, limit: int = 20) -> List[Tweet]:
        result = await self.db.execute(
            select(Tweet)
            .options(selectinload(Tweet.author))
            .filter(Tweet.author_id == user_id)
            .order_by(desc(Tweet.created_at))
            .offset(skip)
            .limit(limit)
        )
        return result.scalars().all()

    async def delete_tweet(self, tweet_id: int, user_id: int) -> bool:
        result = await self.db.execute(
            select(Tweet).filter(Tweet.id == tweet_id, Tweet.author_id == user_id)
        )
        tweet = result.scalar_one_or_none()
        
        if tweet:
            await self.db.delete(tweet)
            await self.db.commit()
            # TODO: Remove from feeds (not implemented for simplicity)
            return True
        return False