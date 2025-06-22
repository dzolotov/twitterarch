from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from typing import List, Optional
from common.models import Tweet, User
from common.schemas import TweetCreate
from .rabbitmq_service import RabbitMQService


class TweetService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_tweet(self, user_id: int, tweet_data: TweetCreate) -> Tweet:
        """
        Step 3: Create tweet and publish to RabbitMQ for async processing.
        Non-blocking - returns immediately after publishing message.
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
        
        # Publish to RabbitMQ for async processing
        rabbitmq = RabbitMQService()
        await rabbitmq.publish_tweet_event({
            "tweet_id": tweet.id,
            "content": tweet.content,
            "author_id": tweet.author_id,
            "author_username": tweet.author.username,
            "created_at": tweet.created_at.isoformat()
        })
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
            # TODO: Publish delete event to remove from feeds
            return True
        return False