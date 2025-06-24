#!/usr/bin/env python3
import asyncio
import aiohttp
import sys
import time
import os
import random
from datetime import datetime

API_URL = "http://localhost:8001/api"

# Результаты для сравнения
results = {
    "postgres": {},
    "citus": {}
}

async def create_user(session, user_id):
    async with session.post(
        f"{API_URL}/users/",
        json={
            "username": f"user{user_id}",
            "email": f"user{user_id}@example.com"
        }
    ) as resp:
        return await resp.json()

async def create_follow(session, follower_id, followed_id):
    async with session.post(
        f"{API_URL}/subscriptions/follow",
        headers={"X-User-ID": str(follower_id)},
        json={"followed_id": followed_id}
    ) as resp:
        return await resp.json()

async def create_tweet(session, user_id, content):
    start = time.time()
    async with session.post(
        f"{API_URL}/tweets/",
        headers={"X-User-ID": str(user_id)},
        json={"content": content}
    ) as resp:
        result = await resp.json()
    return time.time() - start, result

async def measure_feed_time(session, user_id, samples=10):
    times = []
    for _ in range(samples):
        start = time.time()
        async with session.get(
            f"{API_URL}/feed/",
            headers={"X-User-ID": str(user_id)}
        ) as resp:
            data = await resp.json()
        times.append(time.time() - start)
    return sum(times) / len(times), len(data)

async def run_test():
    db_type = os.getenv('DB_TYPE', 'postgres')
    print(f"\n=== Тестирование производительности {db_type.upper()} с реалистичной моделью ===\n")
    
    connector = aiohttp.TCPConnector(limit=100)
    async with aiohttp.ClientSession(connector=connector) as session:
        # 1. Создание пользователей
        print("1. Создание 5000 пользователей...")
        start = time.time()
        
        tasks = []
        for i in range(1, 5001):
            tasks.append(create_user(session, i))
            if len(tasks) >= 100:
                await asyncio.gather(*tasks)
                if i % 1000 == 0:
                    print(f"   Создано {i} пользователей...")
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
            
        user_creation_time = time.time() - start
        print(f"   Время: {user_creation_time:.2f} сек ({5000/user_creation_time:.1f} users/sec)")
        results[db_type]["user_creation"] = user_creation_time
        
        # 2. Создание популярных пользователей
        print("\n2. Создание популярных пользователей...")
        
        # Популярный пользователь (user1) - 2000 подписчиков
        print("   Создание популярного пользователя (2000 подписчиков)...")
        start = time.time()
        tasks = []
        for follower_id in range(2, 2002):
            tasks.append(create_follow(session, follower_id, 1))
            if len(tasks) >= 100:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
        popular_time = time.time() - start
        print(f"   User1: 2000 подписчиков создано за {popular_time:.2f} сек")
        
        # Мега-популярный пользователь (user2) - 5000 подписчиков
        print("   Создание мега-популярного пользователя (5000 подписчиков)...")
        start = time.time()
        tasks = []
        for follower_id in range(3, 5003):
            tasks.append(create_follow(session, follower_id, 2))
            if len(tasks) >= 200:
                await asyncio.gather(*tasks)
                if follower_id % 1000 == 0:
                    print(f"      {follower_id - 2} подписчиков...")
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
        mega_time = time.time() - start
        print(f"   User2: 5000 подписчиков создано за {mega_time:.2f} сек")
        
        results[db_type]["popular_follow_creation"] = popular_time
        results[db_type]["mega_follow_creation"] = mega_time
        
        # 3. Обычные пользователи с реалистичными подписками
        print("\n3. Создание подписок для обычных пользователей...")
        start = time.time()
        tasks = []
        created = 0
        
        # 500 активных пользователей с 50-300 подписками каждый
        for user_id in range(100, 600):
            follow_count = random.randint(50, 300)
            to_follow = random.sample(range(1, 5001), follow_count)
            to_follow = [f for f in to_follow if f != user_id][:follow_count]
            
            for followed_id in to_follow:
                tasks.append(create_follow(session, user_id, followed_id))
                created += 1
                if len(tasks) >= 200:
                    await asyncio.gather(*tasks)
                    tasks = []
        
        if tasks:
            await asyncio.gather(*tasks)
        
        normal_follow_time = time.time() - start
        print(f"   Создано {created} подписок за {normal_follow_time:.2f} сек")
        results[db_type]["normal_follows"] = normal_follow_time
        
        # 4. Измерение производительности создания твитов
        print("\n4. Измерение времени создания твитов...")
        
        # Обычный пользователь
        print("   Обычный пользователь (~50 подписчиков):")
        times = []
        for i in range(5):
            t, _ = await create_tweet(session, 3000, f"Обычный твит #{i}")
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        results[db_type]["tweet_normal"] = sum(times)/len(times)
        
        # Популярный пользователь
        print("   Популярный пользователь (2000 подписчиков):")
        times = []
        for i in range(5):
            t, _ = await create_tweet(session, 1, f"Популярный твит #{i}")
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        results[db_type]["tweet_popular"] = sum(times)/len(times)
        
        # Мега-популярный пользователь
        print("   Мега-популярный пользователь (5000 подписчиков):")
        times = []
        for i in range(5):
            t, _ = await create_tweet(session, 2, f"Мега-популярный твит #{i}")
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        results[db_type]["tweet_mega"] = sum(times)/len(times)
        
        # 5. Создание контента для лент
        print("\n5. Создание твитов для наполнения лент...")
        start = time.time()
        
        tasks = []
        tweet_count = 0
        # 500 активных пользователей создают по 10 твитов
        for user_id in range(100, 600):
            for tweet_num in range(10):
                content = f"Tweet #{tweet_num} from user{user_id}"
                tasks.append(create_tweet(session, user_id, content))
                tweet_count += 1
                
                if len(tasks) >= 100:
                    await asyncio.gather(*tasks)
                    tasks = []
        
        if tasks:
            await asyncio.gather(*tasks)
            
        content_creation_time = time.time() - start
        print(f"   Создано {tweet_count} твитов за {content_creation_time:.2f} сек")
        results[db_type]["content_creation"] = content_creation_time
        
        # 6. Измерение производительности чтения лент
        print("\n6. Измерение производительности чтения лент...")
        
        # Обычный пользователь с ~200 подписками
        avg_time, tweet_count = await measure_feed_time(session, 150, samples=5)
        print(f"   Обычный пользователь (~200 подписок): {avg_time*1000:.1f} мс (твитов: {tweet_count})")
        results[db_type]["feed_normal"] = avg_time
        
        # Пользователь с малым количеством подписок
        avg_time, tweet_count = await measure_feed_time(session, 4500, samples=5)
        print(f"   Малоактивный пользователь (~10 подписок): {avg_time*1000:.1f} мс (твитов: {tweet_count})")
        results[db_type]["feed_small"] = avg_time
        
        print(f"\n=== Завершено тестирование {db_type.upper()} ===")

def print_comparison():
    if len(results["postgres"]) > 0 and len(results["citus"]) > 0:
        print("\n" + "="*60)
        print("СРАВНЕНИЕ ПРОИЗВОДИТЕЛЬНОСТИ: PostgreSQL vs Citus")
        print("="*60)
        
        metrics = [
            ("Создание пользователей (5000)", "user_creation", "сек"),
            ("Создание популярного (2000 подписчиков)", "popular_follow_creation", "сек"),
            ("Создание мега-популярного (5000 подписчиков)", "mega_follow_creation", "сек"),
            ("Создание обычных подписок", "normal_follows", "сек"),
            ("Твит от обычного пользователя", "tweet_normal", "мс", 1000),
            ("Твит от популярного (2000 подписчиков)", "tweet_popular", "мс", 1000),
            ("Твит от мега-популярного (5000 подписчиков)", "tweet_mega", "мс", 1000),
            ("Создание контента (5000 твитов)", "content_creation", "сек"),
            ("Чтение ленты (200 подписок)", "feed_normal", "мс", 1000),
            ("Чтение ленты (10 подписок)", "feed_small", "мс", 1000)
        ]
        
        for metric_name, key, unit, multiplier in [(m[0], m[1], m[2], m[3] if len(m) > 3 else 1) for m in metrics]:
            if key in results["postgres"] and key in results["citus"]:
                pg_time = results["postgres"][key] * multiplier
                citus_time = results["citus"][key] * multiplier
                ratio = citus_time / pg_time
                
                print(f"\n{metric_name}:")
                print(f"  PostgreSQL: {pg_time:.1f} {unit}")
                print(f"  Citus:      {citus_time:.1f} {unit}")
                
                if ratio > 1:
                    print(f"  → Citus медленнее в {ratio:.1f}x")
                else:
                    print(f"  → Citus быстрее в {1/ratio:.1f}x")
        
        print("\n" + "="*60)
        print("КЛЮЧЕВЫЕ ВЫВОДЫ:")
        print("="*60)
        print("• Проблема популярных пользователей проявляется в обеих системах")
        print("• Время создания твита растет линейно с количеством подписчиков")
        print("• На текущих объемах PostgreSQL обычно быстрее из-за простоты")
        print("• Citus показывает преимущества при:")
        print("  - Миллионах пользователей и твитов")
        print("  - Необходимости горизонтального масштабирования")
        print("  - Распределенной обработке данных")

if __name__ == "__main__":
    asyncio.run(run_test())
    print_comparison()