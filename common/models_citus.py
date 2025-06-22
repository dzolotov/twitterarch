from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Boolean, Index, UniqueConstraint, PrimaryKeyConstraint
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    username = Column(String(50), nullable=False, unique=True)
    email = Column(String(100), nullable=False, unique=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    tweets = relationship("Tweet", back_populates="author")
    subscriptions = relationship("Subscription", foreign_keys="Subscription.follower_id", back_populates="follower")
    followers = relationship("Subscription", foreign_keys="Subscription.followed_id", back_populates="followed")
    feed_items = relationship("FeedItem", back_populates="user", cascade="all, delete-orphan")


class Tweet(Base):
    """
    Distributed by author_id for colocation with users table.
    This ensures all tweets by a user are on the same shard.
    """
    __tablename__ = "tweets"

    id = Column(Integer)
    content = Column(String(280), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    author = relationship("User", back_populates="tweets")
    feed_items = relationship("FeedItem", back_populates="tweet", cascade="all, delete-orphan")
    
    __table_args__ = (
        # Composite primary key required for Citus distribution
        PrimaryKeyConstraint('id', 'author_id'),
        Index('idx_tweets_author_created', 'author_id', 'created_at'),
    )


class Subscription(Base):
    """
    Distributed by follower_id for colocation with users table.
    This keeps a user's subscriptions on the same shard as the user.
    """
    __tablename__ = "subscriptions"

    id = Column(Integer)
    follower_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    followed_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    follower = relationship("User", foreign_keys=[follower_id], back_populates="subscriptions")
    followed = relationship("User", foreign_keys=[followed_id], back_populates="followers")
    
    __table_args__ = (
        # Composite primary key for Citus
        PrimaryKeyConstraint('id', 'follower_id'),
        UniqueConstraint('follower_id', 'followed_id', name='uq_follower_followed'),
        Index('idx_subs_follower', 'follower_id'),
        Index('idx_subs_followed', 'followed_id'),
    )


class FeedItem(Base):
    """
    Distributed by user_id for colocation with users table.
    This ensures a user's entire feed is on the same shard.
    """
    __tablename__ = "feed_items"

    id = Column(Integer)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    tweet_id = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    user = relationship("User", back_populates="feed_items")
    # Note: Can't have foreign key to tweets due to cross-shard constraints
    
    __table_args__ = (
        # Composite primary key for Citus
        PrimaryKeyConstraint('id', 'user_id'),
        UniqueConstraint('user_id', 'tweet_id', name='uq_user_tweet'),
        Index('idx_feed_user_created', 'user_id', 'created_at'),
    )