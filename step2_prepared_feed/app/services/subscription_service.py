from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from typing import List, Optional
from common.models import Subscription, User
from .feed_service import FeedService


class SubscriptionService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def follow(self, follower_id: int, followed_id: int) -> Optional[Subscription]:
        # Check if already following
        result = await self.db.execute(
            select(Subscription).filter(
                and_(
                    Subscription.follower_id == follower_id,
                    Subscription.followed_id == followed_id
                )
            )
        )
        existing = result.scalar_one_or_none()
        
        if existing or follower_id == followed_id:
            return None
        
        subscription = Subscription(
            follower_id=follower_id,
            followed_id=followed_id
        )
        self.db.add(subscription)
        await self.db.commit()
        await self.db.refresh(subscription)
        
        # Step 2: Rebuild follower's feed when they follow someone
        feed_service = FeedService(self.db)
        await feed_service.rebuild_user_feed(follower_id)
        
        return subscription

    async def unfollow(self, follower_id: int, followed_id: int) -> bool:
        result = await self.db.execute(
            select(Subscription).filter(
                and_(
                    Subscription.follower_id == follower_id,
                    Subscription.followed_id == followed_id
                )
            )
        )
        subscription = result.scalar_one_or_none()
        
        if subscription:
            await self.db.delete(subscription)
            await self.db.commit()
            
            # Step 2: Rebuild follower's feed when they unfollow someone
            feed_service = FeedService(self.db)
            await feed_service.rebuild_user_feed(follower_id)
            
            return True
        return False

    async def get_followers(self, user_id: int, skip: int = 0, limit: int = 100) -> List[User]:
        result = await self.db.execute(
            select(User)
            .join(Subscription, Subscription.follower_id == User.id)
            .filter(Subscription.followed_id == user_id)
            .offset(skip)
            .limit(limit)
        )
        return result.scalars().all()

    async def get_following(self, user_id: int, skip: int = 0, limit: int = 100) -> List[User]:
        result = await self.db.execute(
            select(User)
            .join(Subscription, Subscription.followed_id == User.id)
            .filter(Subscription.follower_id == user_id)
            .offset(skip)
            .limit(limit)
        )
        return result.scalars().all()

    async def is_following(self, follower_id: int, followed_id: int) -> bool:
        result = await self.db.execute(
            select(Subscription).filter(
                and_(
                    Subscription.follower_id == follower_id,
                    Subscription.followed_id == followed_id
                )
            )
        )
        return result.scalar_one_or_none() is not None