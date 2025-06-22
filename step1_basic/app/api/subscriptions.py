from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from common.database import get_async_session
from common.schemas import User, SubscriptionCreate
from ..services.subscription_service import SubscriptionService
from ..services.user_service import UserService
from .tweets import get_current_user_id

router = APIRouter()


@router.post("/follow")
async def follow_user(
    data: SubscriptionCreate,
    follower_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_async_session)
):
    # Verify both users exist
    user_service = UserService(db)
    follower = await user_service.get_user(follower_id)
    followed = await user_service.get_user(data.followed_id)
    
    if not follower or not followed:
        raise HTTPException(status_code=404, detail="User not found")
    
    service = SubscriptionService(db)
    subscription = await service.follow(follower_id, data.followed_id)
    
    if not subscription:
        raise HTTPException(status_code=400, detail="Already following or invalid request")
    
    return {"message": f"Now following user {data.followed_id}"}


@router.delete("/unfollow/{followed_id}")
async def unfollow_user(
    followed_id: int,
    follower_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_async_session)
):
    service = SubscriptionService(db)
    if not await service.unfollow(follower_id, followed_id):
        raise HTTPException(status_code=404, detail="Subscription not found")
    
    return {"message": f"Unfollowed user {followed_id}"}


@router.get("/{user_id}/followers", response_model=List[User])
async def get_followers(
    user_id: int,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_async_session)
):
    service = SubscriptionService(db)
    return await service.get_followers(user_id, skip=skip, limit=limit)


@router.get("/{user_id}/following", response_model=List[User])
async def get_following(
    user_id: int,
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_async_session)
):
    service = SubscriptionService(db)
    return await service.get_following(user_id, skip=skip, limit=limit)