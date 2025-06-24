#!/usr/bin/env python3
"""
Universal data loader with realistic follower model for all architecture steps.
Can be imported or run standalone.
"""
import asyncio
import aiohttp
import sys
import time
import random
from datetime import datetime

async def create_user(session, api_url, user_id):
    async with session.post(
        f"{api_url}/users/",
        json={
            "username": f"user{user_id}",
            "email": f"user{user_id}@example.com"
        }
    ) as resp:
        return await resp.json()

async def create_follow(session, api_url, follower_id, followed_id):
    async with session.post(
        f"{api_url}/subscriptions/follow",
        headers={"X-User-ID": str(follower_id)},
        json={"followed_id": followed_id}
    ) as resp:
        return await resp.json()

async def create_tweet(session, api_url, user_id, content):
    start = time.time()
    async with session.post(
        f"{api_url}/tweets/",
        headers={"X-User-ID": str(user_id)},
        json={"content": content}
    ) as resp:
        result = await resp.json()
    return time.time() - start, result

async def measure_feed_time(session, api_url, user_id):
    start = time.time()
    async with session.get(
        f"{api_url}/feed/",
        headers={"X-User-ID": str(user_id)}
    ) as resp:
        data = await resp.json()
    return time.time() - start, len(data)

async def load_realistic_data(api_url="http://localhost:8001/api", 
                            num_users=1000,
                            popular_followers=500, 
                            mega_followers=2000,
                            measure_performance=True):
    """
    Load realistic Twitter-like data with popular users.
    
    Args:
        api_url: API endpoint URL
        num_users: Total number of users to create
        popular_followers: Number of followers for popular user
        mega_followers: Number of followers for mega-popular user
        measure_performance: Whether to measure and report performance
    
    Returns:
        Dictionary with performance metrics
    """
    print(f"\n=== Loading Realistic Data ===")
    print(f"API URL: {api_url}")
    print(f"Total users: {num_users}")
    print(f"Popular user followers: {popular_followers}")
    print(f"Mega-popular user followers: {mega_followers}")
    
    metrics = {}
    
    connector = aiohttp.TCPConnector(limit=100)
    async with aiohttp.ClientSession(connector=connector) as session:
        # 1. Create users
        print(f"\n1. Creating {num_users} users...")
        start = time.time()
        
        tasks = []
        for i in range(1, num_users + 1):
            tasks.append(create_user(session, api_url, i))
            if len(tasks) >= 100:
                await asyncio.gather(*tasks)
                if i % (num_users // 5) == 0:
                    print(f"   Created {i} users...")
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
            
        user_creation_time = time.time() - start
        print(f"   ✓ Created {num_users} users in {user_creation_time:.2f} sec")
        metrics['user_creation_time'] = user_creation_time
        
        # 2. Create popular user (user1)
        if popular_followers > 0 and popular_followers < num_users:
            print(f"\n2. Creating popular user with {popular_followers} followers...")
            start = time.time()
            tasks = []
            
            for follower_id in range(2, min(popular_followers + 2, num_users + 1)):
                tasks.append(create_follow(session, api_url, follower_id, 1))
                if len(tasks) >= 100:
                    await asyncio.gather(*tasks)
                    tasks = []
            if tasks:
                await asyncio.gather(*tasks)
                
            popular_time = time.time() - start
            print(f"   ✓ User1: {popular_followers} followers in {popular_time:.2f} sec")
            metrics['popular_follow_time'] = popular_time
        
        # 3. Create mega-popular user (user2)
        if mega_followers > 0 and mega_followers < num_users:
            print(f"\n3. Creating mega-popular user with {mega_followers} followers...")
            start = time.time()
            tasks = []
            
            for follower_id in range(3, min(mega_followers + 3, num_users + 1)):
                tasks.append(create_follow(session, api_url, follower_id, 2))
                if len(tasks) >= 200:
                    await asyncio.gather(*tasks)
                    if follower_id % (mega_followers // 4) == 0:
                        print(f"      {follower_id - 2} followers...")
                    tasks = []
            if tasks:
                await asyncio.gather(*tasks)
                
            mega_time = time.time() - start
            print(f"   ✓ User2: {mega_followers} followers in {mega_time:.2f} sec")
            metrics['mega_follow_time'] = mega_time
        
        # 4. Create normal user follows
        print("\n4. Creating follows for normal users...")
        start = time.time()
        tasks = []
        created = 0
        
        # Sample of active users follow random users
        active_users = min(200, num_users // 5)
        for user_id in range(100, min(100 + active_users, num_users)):
            follow_count = random.randint(50, min(200, num_users // 10))
            to_follow = random.sample(range(1, num_users + 1), follow_count)
            to_follow = [f for f in to_follow if f != user_id][:follow_count]
            
            for followed_id in to_follow:
                tasks.append(create_follow(session, api_url, user_id, followed_id))
                created += 1
                if len(tasks) >= 200:
                    await asyncio.gather(*tasks)
                    tasks = []
        
        if tasks:
            await asyncio.gather(*tasks)
            
        normal_follow_time = time.time() - start
        print(f"   ✓ Created {created} follows in {normal_follow_time:.2f} sec")
        metrics['normal_follow_time'] = normal_follow_time
        
        if measure_performance:
            # 5. Measure tweet creation performance
            print("\n5. Measuring tweet creation performance...")
            
            # Normal user
            print("   Normal user (few followers):")
            times = []
            for i in range(3):
                t, _ = await create_tweet(session, api_url, num_users - 1, f"Normal tweet #{i}")
                times.append(t)
                print(f"     Attempt {i+1}: {t*1000:.1f} ms")
            avg_normal = sum(times)/len(times)*1000
            metrics['tweet_normal_ms'] = avg_normal
            
            # Popular user
            print(f"\n   Popular user ({popular_followers} followers):")
            times = []
            for i in range(3):
                t, _ = await create_tweet(session, api_url, 1, f"Popular tweet #{i}")
                times.append(t)
                print(f"     Attempt {i+1}: {t*1000:.1f} ms")
            avg_popular = sum(times)/len(times)*1000
            metrics['tweet_popular_ms'] = avg_popular
            
            # Mega-popular user
            print(f"\n   Mega-popular user ({mega_followers} followers):")
            times = []
            for i in range(3):
                t, _ = await create_tweet(session, api_url, 2, f"Mega tweet #{i}")
                times.append(t)
                print(f"     Attempt {i+1}: {t*1000:.1f} ms")
            avg_mega = sum(times)/len(times)*1000
            metrics['tweet_mega_ms'] = avg_mega
            
            # 6. Create content
            print("\n6. Creating content tweets...")
            start = time.time()
            tasks = []
            tweet_count = 0
            
            # Active users create tweets
            for user_id in range(100, min(100 + active_users, num_users)):
                for tweet_num in range(5):
                    content = f"Tweet #{tweet_num} from user{user_id}"
                    tasks.append(create_tweet(session, api_url, user_id, content))
                    tweet_count += 1
                    
                    if len(tasks) >= 100:
                        await asyncio.gather(*tasks)
                        tasks = []
            
            if tasks:
                await asyncio.gather(*tasks)
                
            content_time = time.time() - start
            print(f"   ✓ Created {tweet_count} tweets in {content_time:.2f} sec")
            metrics['content_creation_time'] = content_time
            
            # 7. Measure feed performance
            print("\n7. Measuring feed read performance...")
            feed_time, tweet_count = await measure_feed_time(session, api_url, 100)
            print(f"   Feed read time: {feed_time*1000:.1f} ms ({tweet_count} tweets)")
            metrics['feed_read_ms'] = feed_time * 1000
            
            # Summary
            print("\n=== Performance Summary ===")
            print(f"Tweet creation degradation:")
            print(f"  Normal user: {avg_normal:.1f} ms")
            print(f"  Popular user: {avg_popular:.1f} ms ({avg_popular/avg_normal:.1f}x slower)")
            print(f"  Mega-popular: {avg_mega:.1f} ms ({avg_mega/avg_normal:.1f}x slower)")
    
    return metrics

async def main():
    """Standalone execution with command line arguments."""
    import argparse
    parser = argparse.ArgumentParser(description='Load realistic Twitter data')
    parser.add_argument('--url', default='http://localhost:8001/api', help='API URL')
    parser.add_argument('--users', type=int, default=1000, help='Number of users')
    parser.add_argument('--popular', type=int, default=500, help='Popular user followers')
    parser.add_argument('--mega', type=int, default=2000, help='Mega-popular followers')
    parser.add_argument('--no-measure', action='store_true', help='Skip performance measurement')
    
    args = parser.parse_args()
    
    await load_realistic_data(
        api_url=args.url,
        num_users=args.users,
        popular_followers=args.popular,
        mega_followers=args.mega,
        measure_performance=not args.no_measure
    )

if __name__ == "__main__":
    asyncio.run(main())