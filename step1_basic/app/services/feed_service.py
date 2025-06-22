from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, or_
from sqlalchemy.orm import selectinload
from typing import List
from common.models import Tweet, Subscription
from common.schemas import FeedItem


class FeedService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_user_feed(self, user_id: int, skip: int = 0, limit: int = 20) -> List[FeedItem]:
        """
        Step 1: Basic synchronous feed generation.
        This performs a JOIN query to get tweets from followed users.
        Performance degrades with many followed users.
        """
        # Get IDs of users that the current user follows
        following_subquery = select(Subscription.followed_id).filter(
            Subscription.follower_id == user_id
        ).subquery()
        
        # Get tweets from followed users and own tweets
        result = await self.db.execute(
            select(Tweet)
            .options(selectinload(Tweet.author))
            .filter(
                or_(
                    Tweet.author_id.in_(following_subquery),
                    Tweet.author_id == user_id
                )
            )
            .order_by(desc(Tweet.created_at))
            .offset(skip)
            .limit(limit)
        )
        
        tweets = result.scalars().all()
        
        # Convert to FeedItem schema
        feed_items = []
        for tweet in tweets:
            feed_items.append(FeedItem(
                tweet_id=tweet.id,
                content=tweet.content,
                author_id=tweet.author.id,
                author_username=tweet.author.username,
                created_at=tweet.created_at
            ))
        
        return feed_items