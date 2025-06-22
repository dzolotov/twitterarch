import redis.asyncio as redis
import json
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timedelta
import asyncio
from common.config import get_settings

settings = get_settings()


class CircularBuffer:
    """Circular buffer implementation for feed storage"""
    def __init__(self, size: int = 1000):
        self.size = size
        self.buffer = [None] * size
        self.head = 0  # Points to next write position
        self.tail = 0  # Points to oldest item
        self.count = 0  # Number of items in buffer
    
    def add(self, item: Dict[str, Any]):
        """Add item to buffer, overwriting oldest if full"""
        self.buffer[self.head] = item
        self.head = (self.head + 1) % self.size
        
        if self.count < self.size:
            self.count += 1
        else:
            # Buffer is full, move tail
            self.tail = (self.tail + 1) % self.size
    
    def get_items(self, limit: int = 20, offset: int = 0) -> List[Dict[str, Any]]:
        """Get items from buffer with pagination"""
        if self.count == 0:
            return []
        
        items = []
        # Start from newest (head - 1) and go backwards
        start_pos = (self.head - 1 - offset) % self.size
        
        for i in range(min(limit, self.count - offset)):
            if i + offset >= self.count:
                break
            pos = (start_pos - i) % self.size
            if self.buffer[pos] is not None:
                items.append(self.buffer[pos])
        
        return items
    
    def to_dict(self) -> Dict[str, Any]:
        """Serialize buffer state"""
        return {
            "buffer": self.buffer,
            "head": self.head,
            "tail": self.tail,
            "count": self.count,
            "size": self.size
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'CircularBuffer':
        """Deserialize buffer state"""
        cb = cls(data["size"])
        cb.buffer = data["buffer"]
        cb.head = data["head"]
        cb.tail = data["tail"]
        cb.count = data["count"]
        return cb


class CacheService:
    def __init__(self):
        self.redis: Optional[redis.Redis] = None
        self.feed_ttl = 3600  # 1 hour
        self.tweet_ttl = 7200  # 2 hours
        self.message_ttl = 300  # 5 minutes for dedup
        self.buffer_size = 1000  # Circular buffer size
    
    async def initialize(self):
        """Initialize Redis connection"""
        self.redis = await redis.from_url(
            "redis://localhost:6379",
            encoding="utf-8",
            decode_responses=True
        )
        # Test connection
        await self.redis.ping()
    
    async def get_feed_cache(self, user_id: int, limit: int = 20, offset: int = 0) -> Optional[List[Dict[str, Any]]]:
        """Get cached feed using circular buffer"""
        key = f"feed:buffer:{user_id}"
        
        # Get serialized buffer
        buffer_data = await self.redis.get(key)
        if not buffer_data:
            return None
        
        # Deserialize and get items
        cb = CircularBuffer.from_dict(json.loads(buffer_data))
        items = cb.get_items(limit, offset)
        
        # Update access time for LRU
        await self.redis.zadd("feed:access", {str(user_id): datetime.now().timestamp()})
        
        return items
    
    async def add_to_feed_cache(self, user_id: int, tweet_data: Dict[str, Any]):
        """Add tweet to user's circular buffer feed cache"""
        key = f"feed:buffer:{user_id}"
        
        # Get or create buffer
        buffer_data = await self.redis.get(key)
        if buffer_data:
            cb = CircularBuffer.from_dict(json.loads(buffer_data))
        else:
            cb = CircularBuffer(self.buffer_size)
        
        # Add tweet to buffer
        cb.add(tweet_data)
        
        # Save updated buffer
        await self.redis.setex(
            key,
            self.feed_ttl,
            json.dumps(cb.to_dict())
        )
        
        # Mark as hot user if frequently accessed
        await self._mark_hot_user(user_id)
    
    async def cache_tweet(self, tweet_id: int, tweet_data: Dict[str, Any]):
        """Cache individual tweet"""
        key = f"tweet:{tweet_id}"
        await self.redis.setex(
            key,
            self.tweet_ttl,
            json.dumps(tweet_data)
        )
    
    async def get_cached_tweet(self, tweet_id: int) -> Optional[Dict[str, Any]]:
        """Get cached tweet"""
        key = f"tweet:{tweet_id}"
        data = await self.redis.get(key)
        return json.loads(data) if data else None
    
    async def is_message_processed(self, message_id: str) -> bool:
        """Check if message was already processed (deduplication)"""
        key = f"msg:processed:{message_id}"
        result = await self.redis.get(key)
        return result is not None
    
    async def mark_message_processed(self, message_id: str):
        """Mark message as processed"""
        key = f"msg:processed:{message_id}"
        await self.redis.setex(key, self.message_ttl, "1")
    
    async def warm_cache(self, user_ids: List[int], tweets: List[Dict[str, Any]]):
        """Warm cache for specific users (e.g., celebrities)"""
        for user_id in user_ids:
            cb = CircularBuffer(self.buffer_size)
            for tweet in tweets:
                cb.add(tweet)
            
            key = f"feed:buffer:{user_id}"
            await self.redis.setex(
                key,
                self.feed_ttl,
                json.dumps(cb.to_dict())
            )
    
    async def invalidate_user_cache(self, user_id: int):
        """Invalidate user's feed cache"""
        key = f"feed:buffer:{user_id}"
        await self.redis.delete(key)
    
    async def _mark_hot_user(self, user_id: int):
        """Track hot users for cache warming"""
        await self.redis.zincrby("users:hot", 1, str(user_id))
    
    async def get_hot_users(self, limit: int = 100) -> List[int]:
        """Get most accessed users"""
        hot_users = await self.redis.zrevrange("users:hot", 0, limit - 1)
        return [int(uid) for uid in hot_users]
    
    async def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        # Count cached feeds
        feed_keys = await self.redis.keys("feed:buffer:*")
        tweet_keys = await self.redis.keys("tweet:*")
        msg_keys = await self.redis.keys("msg:processed:*")
        
        # Get hot users
        hot_users = await self.get_hot_users(10)
        
        # Memory usage approximation
        info = await self.redis.info("memory")
        
        return {
            "cached_feeds": len(feed_keys),
            "cached_tweets": len(tweet_keys),
            "processed_messages": len(msg_keys),
            "hot_users": hot_users,
            "memory_used_mb": round(info.get("used_memory", 0) / 1024 / 1024, 2),
            "buffer_size": self.buffer_size
        }
    
    async def close(self):
        """Close Redis connection"""
        if self.redis:
            await self.redis.close()