from pydantic_settings import BaseSettings
from functools import lru_cache


class CitusSettings(BaseSettings):
    app_name: str = "Twitter Architecture Demo - Citus"
    
    # Citus coordinator connection
    database_url: str = "postgresql+asyncpg://user:password@localhost/twitter_db"
    database_url_sync: str = "postgresql://user:password@localhost/twitter_db"
    
    # Citus-specific settings
    citus_shard_count: int = 32  # Number of shards per distributed table
    citus_shard_replication_factor: int = 1  # Replication factor
    citus_coordinator_host: str = "localhost"
    citus_coordinator_port: int = 5432
    
    # Worker nodes (for direct connections if needed)
    citus_workers: list = [
        {"host": "localhost", "port": 5433},
        {"host": "localhost", "port": 5434},
        {"host": "localhost", "port": 5435},
    ]
    
    # Other services
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    redis_url: str = "redis://localhost:6379"
    
    secret_key: str = "your-secret-key-here"
    debug: bool = True
    
    class Config:
        env_file = ".env.citus"


@lru_cache()
def get_citus_settings():
    return CitusSettings()