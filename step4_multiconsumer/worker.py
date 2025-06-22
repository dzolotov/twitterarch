#!/usr/bin/env python
"""
Standalone worker runner for Step 4.
Run multiple instances with different IDs:
  python worker.py 0
  python worker.py 1
  python worker.py 2
  python worker.py 3
"""
import sys
from pathlib import Path
sys.path.append(str(Path(__file__).parent.parent))

import asyncio
import logging
from app.workers.feed_worker import FeedWorker

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

async def main():
    if len(sys.argv) < 2:
        print("Usage: python worker.py <worker_id>")
        print("Example: python worker.py 0")
        sys.exit(1)
    
    worker_id = int(sys.argv[1])
    print(f"Starting worker {worker_id}...")
    
    worker = FeedWorker(worker_id)
    
    try:
        await worker.start()
    except KeyboardInterrupt:
        print(f"\nShutting down worker {worker_id}...")
        await worker.stop()

if __name__ == "__main__":
    asyncio.run(main())