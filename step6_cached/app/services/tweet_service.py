from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from typing import List, Optional
from common.models import Tweet, User, Subscription
from common.schemas import TweetCreate
from .rabbitmq_service import RabbitMQService
from .cache_service import CacheService


class TweetService:
    def __init__(self, db: AsyncSession, cache: Optional[CacheService] = None):
        self.db = db
        self.cache = cache

    async def create_tweet(self, user_id: int, tweet_data: TweetCreate) -> Tweet:
        """
        Step 6: Create tweet with caching support
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
        
        # Get followers count for metrics
        result = await self.db.execute(
            select(Subscription.follower_id)
            .filter(Subscription.followed_id == user_id)
        )
        follower_ids = [row[0] for row in result]
        follower_ids.append(user_id)
        
        # Cache the tweet if cache available
        if self.cache:
            await self.cache.cache_tweet(tweet.id, {
                "tweet_id": tweet.id,
                "content": tweet.content,
                "author_id": tweet.author_id,
                "author_username": tweet.author.username,
                "created_at": tweet.created_at.isoformat()
            })
        
        # Publish to RabbitMQ
        rabbitmq = RabbitMQService()
        await rabbitmq.publish_tweet_event_batch(
            {
                "tweet_id": tweet.id,
                "content": tweet.content,
                "author_id": tweet.author_id,
                "author_username": tweet.author.username,
                "created_at": tweet.created_at.isoformat()
            },
            follower_ids
        )
        await rabbitmq.close()
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
            return True
        return False