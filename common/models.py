from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Boolean, Index, UniqueConstraint
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(50), unique=True, index=True, nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    tweets = relationship("Tweet", back_populates="author")
    subscriptions = relationship("Subscription", foreign_keys="Subscription.follower_id", back_populates="follower")
    followers = relationship("Subscription", foreign_keys="Subscription.followed_id", back_populates="followed")
    feed_items = relationship("FeedItem", back_populates="user", cascade="all, delete-orphan")


class Tweet(Base):
    __tablename__ = "tweets"

    id = Column(Integer, primary_key=True, index=True)
    content = Column(String(280), nullable=False)  # Updated to 280 chars like modern Twitter
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    author = relationship("User", back_populates="tweets")
    feed_items = relationship("FeedItem", back_populates="tweet", cascade="all, delete-orphan")
    
    __table_args__ = (
        Index('idx_author_created', 'author_id', 'created_at'),
    )


class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    follower_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    followed_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    follower = relationship("User", foreign_keys=[follower_id], back_populates="subscriptions")
    followed = relationship("User", foreign_keys=[followed_id], back_populates="followers")
    
    __table_args__ = (
        Index('idx_follower_followed', 'follower_id', 'followed_id', unique=True),
        Index('idx_followed_follower', 'followed_id', 'follower_id'),
    )


class FeedItem(Base):
    """
    Relational feed storage - each row represents one tweet in a user's feed.
    This replaces the JSON-based Feed table.
    """
    __tablename__ = "feed_items"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    tweet_id = Column(Integer, ForeignKey("tweets.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    user = relationship("User", back_populates="feed_items")
    tweet = relationship("Tweet", back_populates="feed_items")
    
    __table_args__ = (
        # Ensure a tweet appears only once in a user's feed
        UniqueConstraint('user_id', 'tweet_id', name='uq_user_tweet'),
        # Index for fast feed retrieval
        Index('idx_user_created', 'user_id', 'created_at'),
    )