#!/usr/bin/env python
"""
Production-ready worker runner for Step 5.
Includes monitoring and graceful shutdown.
"""
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import asyncio
import logging
import signal
from app.workers.feed_worker import FeedWorker

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

worker = None

async def shutdown(signal, loop):
    """Graceful shutdown handler"""
    logging.info(f"Received exit signal {signal.name}...")
    if worker:
        await worker.stop()
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    loop.stop()

async def main():
    global worker
    
    if len(sys.argv) < 2:
        print("Usage: python worker.py <worker_id>")
        print("Example: python worker.py 0")
        sys.exit(1)
    
    worker_id = int(sys.argv[1])
    print(f"Starting production worker {worker_id}...")
    
    # Setup signal handlers
    loop = asyncio.get_event_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda s, f: asyncio.create_task(shutdown(s, loop)))
    
    worker = FeedWorker(worker_id)
    
    try:
        await worker.start()
    except Exception as e:
        logging.error(f"Worker {worker_id} failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())