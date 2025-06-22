from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from common.database import get_async_session
from common.schemas import Tweet, TweetCreate
from ..services.tweet_service import TweetService
from ..services.user_service import UserService

router = APIRouter()


async def get_current_user_id(x_user_id: Optional[int] = Header(None)) -> int:
    """Simple auth simulation - in real app, use proper authentication"""
    if not x_user_id:
        raise HTTPException(status_code=401, detail="X-User-ID header required")
    return x_user_id


@router.post("/", response_model=Tweet)
async def create_tweet(
    tweet_data: TweetCreate,
    user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_async_session)
):
    # Verify user exists
    user_service = UserService(db)
    user = await user_service.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    tweet_service = TweetService(db)
    return await tweet_service.create_tweet(user_id, tweet_data)


@router.get("/{tweet_id}", response_model=Tweet)
async def get_tweet(
    tweet_id: int,
    db: AsyncSession = Depends(get_async_session)
):
    service = TweetService(db)
    tweet = await service.get_tweet(tweet_id)
    if not tweet:
        raise HTTPException(status_code=404, detail="Tweet not found")
    return tweet


@router.get("/user/{user_id}", response_model=List[Tweet])
async def get_user_tweets(
    user_id: int,
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_async_session)
):
    service = TweetService(db)
    return await service.get_user_tweets(user_id, skip=skip, limit=limit)


@router.delete("/{tweet_id}")
async def delete_tweet(
    tweet_id: int,
    user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_async_session)
):
    service = TweetService(db)
    if not await service.delete_tweet(tweet_id, user_id):
        raise HTTPException(status_code=404, detail="Tweet not found or unauthorized")
    return {"message": "Tweet deleted successfully"}