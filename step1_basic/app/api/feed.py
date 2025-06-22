from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from common.database import get_async_session
from common.schemas import FeedItem
from ..services.feed_service import FeedService
from .tweets import get_current_user_id

router = APIRouter()


@router.get("/", response_model=List[FeedItem])
async def get_feed(
    skip: int = 0,
    limit: int = 20,
    user_id: int = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_async_session)
):
    """
    Get user's feed - tweets from followed users and own tweets.
    In Step 1, this is generated in real-time with a JOIN query.
    Performance degrades with many followed users.
    """
    service = FeedService(db)
    return await service.get_user_feed(user_id, skip=skip, limit=limit)