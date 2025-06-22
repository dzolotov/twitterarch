from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from common.database import get_async_session
from common.schemas import User, UserCreate
from ..services.user_service import UserService

router = APIRouter()


@router.post("/", response_model=User)
async def create_user(
    user_data: UserCreate,
    db: AsyncSession = Depends(get_async_session)
):
    service = UserService(db)
    
    # Check if username already exists
    existing = await service.get_user_by_username(user_data.username)
    if existing:
        raise HTTPException(status_code=400, detail="Username already exists")
    
    return await service.create_user(user_data)


@router.get("/{user_id}", response_model=User)
async def get_user(
    user_id: int,
    db: AsyncSession = Depends(get_async_session)
):
    service = UserService(db)
    user = await service.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.get("/", response_model=List[User])
async def list_users(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_async_session)
):
    service = UserService(db)
    return await service.get_users(skip=skip, limit=limit)


@router.delete("/{user_id}")
async def delete_user(
    user_id: int,
    db: AsyncSession = Depends(get_async_session)
):
    service = UserService(db)
    if not await service.delete_user(user_id):
        raise HTTPException(status_code=404, detail="User not found")
    return {"message": "User deleted successfully"}