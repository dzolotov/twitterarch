from pydantic import BaseModel, EmailStr, Field
from datetime import datetime
from typing import List, Optional


class UserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=50)
    email: EmailStr


class UserCreate(UserBase):
    pass


class User(UserBase):
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


class TweetBase(BaseModel):
    content: str = Field(..., min_length=1, max_length=280)


class TweetCreate(TweetBase):
    pass


class Tweet(TweetBase):
    id: int
    author_id: int
    created_at: datetime
    author: Optional[User] = None

    class Config:
        from_attributes = True


class SubscriptionCreate(BaseModel):
    followed_id: int


class Subscription(BaseModel):
    id: int
    follower_id: int
    followed_id: int
    created_at: datetime

    class Config:
        from_attributes = True


class FeedItem(BaseModel):
    tweet_id: int
    content: str
    author_id: int
    author_username: str
    created_at: datetime