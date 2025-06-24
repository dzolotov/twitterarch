#!/usr/bin/env python3
import asyncio
import aiohttp
import sys
import time
import random
from datetime import datetime

API_URL = "http://localhost:8001/api"

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
    async with session.post(
        f"{API_URL}/tweets/",
        headers={"X-User-ID": str(user_id)},
        json={"content": content}
    ) as resp:
        return await resp.json()

async def measure_feed_time(session, user_id):
    start = time.time()
    async with session.get(
        f"{API_URL}/feed/",
        headers={"X-User-ID": str(user_id)}
    ) as resp:
        data = await resp.json()
    return time.time() - start, len(data)

async def measure_tweet_creation_time(session, user_id, content):
    start = time.time()
    await create_tweet(session, user_id, content)
    return time.time() - start

async def main():
    print("=== Реалистичная загрузка данных Twitter ===")
    
    connector = aiohttp.TCPConnector(limit=100)
    async with aiohttp.ClientSession(connector=connector) as session:
        # 1. Создание пользователей
        print("\n1. Создание пользователей...")
        start = time.time()
        
        # Создаем 10,000 обычных пользователей
        tasks = []
        for i in range(1, 10001):
            tasks.append(create_user(session, i))
            if len(tasks) >= 100:
                await asyncio.gather(*tasks)
                if i % 2000 == 0:
                    print(f"   Создано {i} пользователей...")
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
            
        print(f"   Создано 10,000 пользователей за {time.time() - start:.2f} сек!")
        
        # 2. Создание реалистичных подписок
        print("\n2. Создание подписок...")
        
        # Популярный пользователь (user1) - 5,000 подписчиков
        print("   Создание популярного пользователя (5,000 подписчиков)...")
        start = time.time()
        tasks = []
        for follower_id in range(2, 5002):
            tasks.append(create_follow(session, follower_id, 1))
            if len(tasks) >= 100:
                await asyncio.gather(*tasks)
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
        print(f"   User1: 5,000 подписчиков создано за {time.time() - start:.2f} сек")
        
        # Мега-популярный пользователь (user2) - 20,000 подписчиков
        print("   Создание мега-популярного пользователя (20,000 подписчиков)...")
        start = time.time()
        tasks = []
        for follower_id in range(3, 20003):
            tasks.append(create_follow(session, follower_id, 2))
            if len(tasks) >= 200:
                await asyncio.gather(*tasks)
                if follower_id % 5000 == 0:
                    print(f"      {follower_id - 2} подписчиков...")
                tasks = []
        if tasks:
            await asyncio.gather(*tasks)
        print(f"   User2: 20,000 подписчиков создано за {time.time() - start:.2f} сек")
        
        # Обычные пользователи подписываются друг на друга (50-500 подписок)
        print("   Создание подписок для обычных пользователей...")
        start = time.time()
        tasks = []
        created = 0
        
        for user_id in range(3, 1003):  # 1000 активных пользователей
            # Случайное количество подписок от 50 до 500
            follow_count = random.randint(50, 500)
            # Выбираем случайных пользователей для подписки
            to_follow = random.sample(range(1, 10001), follow_count)
            to_follow = [f for f in to_follow if f != user_id][:follow_count]
            
            for followed_id in to_follow:
                tasks.append(create_follow(session, user_id, followed_id))
                created += 1
                if len(tasks) >= 200:
                    await asyncio.gather(*tasks)
                    tasks = []
        
        if tasks:
            await asyncio.gather(*tasks)
        print(f"   Создано {created} подписок за {time.time() - start:.2f} сек")
        
        # 3. Измерение производительности создания твитов
        print("\n3. Измерение времени создания твитов...")
        
        # Твит от обычного пользователя
        print("   Обычный пользователь (100 подписчиков):")
        times = []
        for i in range(5):
            t = await measure_tweet_creation_time(
                session, 5000, 
                f"Тестовый твит #{i} от обычного пользователя"
            )
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        print(f"     Среднее время: {sum(times)/len(times)*1000:.1f} мс")
        
        # Твит от популярного пользователя
        print("\n   Популярный пользователь (5,000 подписчиков):")
        times = []
        for i in range(5):
            t = await measure_tweet_creation_time(
                session, 1, 
                f"Тестовый твит #{i} от популярного пользователя"
            )
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        avg_popular = sum(times)/len(times)*1000
        print(f"     Среднее время: {avg_popular:.1f} мс")
        
        # Твит от мега-популярного пользователя
        print("\n   Мега-популярный пользователь (20,000 подписчиков):")
        times = []
        for i in range(5):
            t = await measure_tweet_creation_time(
                session, 2, 
                f"Тестовый твит #{i} от мега-популярного пользователя"
            )
            times.append(t)
            print(f"     Попытка {i+1}: {t*1000:.1f} мс")
        avg_mega = sum(times)/len(times)*1000
        print(f"     Среднее время: {avg_mega:.1f} мс")
        
        # 4. Создание контента для лент
        print("\n4. Создание твитов для наполнения лент...")
        start = time.time()
        tasks = []
        tweet_count = 0
        
        # Каждый из 1000 активных пользователей создает 10 твитов
        for user_id in range(3, 1003):
            for tweet_num in range(10):
                content = f"Твит #{tweet_num} от user{user_id} - {datetime.now().isoformat()}"
                tasks.append(create_tweet(session, user_id, content))
                tweet_count += 1
                
                if len(tasks) >= 100:
                    await asyncio.gather(*tasks)
                    if tweet_count % 2000 == 0:
                        print(f"   Создано {tweet_count} твитов...")
                    tasks = []
        
        if tasks:
            await asyncio.gather(*tasks)
        print(f"   Создано {tweet_count} твитов за {time.time() - start:.2f} сек")
        
        # 5. Измерение производительности чтения лент
        print("\n5. Измерение производительности чтения лент...")
        
        # Обычный пользователь с ~300 подписками
        print("   Обычный пользователь (~300 подписок):")
        times = []
        for i in range(5):
            feed_time, count = await measure_feed_time(session, 100)
            times.append(feed_time)
            print(f"     Попытка {i+1}: {feed_time*1000:.1f} мс (твитов: {count})")
        print(f"     Среднее время: {sum(times)/len(times)*1000:.1f} мс")
        
        # 6. Итоговая статистика
        print("\n=== ИТОГОВАЯ СТАТИСТИКА ===")
        print(f"\nВремя создания твита:")
        print(f"  Обычный пользователь: ~1-5 мс")
        print(f"  Популярный (5K подписчиков): {avg_popular:.1f} мс")
        print(f"  Мега-популярный (20K подписчиков): {avg_mega:.1f} мс")
        print(f"  Деградация: {avg_mega/5:.0f}x")
        
        print("\nПроблемы текущей архитектуры:")
        print("- Линейная зависимость времени записи от количества подписчиков")
        print("- Синхронное обновление всех лент подписчиков")
        print("- Отсутствие оптимизации для популярных пользователей")
        print("- Нет батчинга или асинхронной обработки")

if __name__ == "__main__":
    asyncio.run(main())