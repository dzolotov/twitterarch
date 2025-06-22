from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    app_name: str = "Twitter Architecture Demo"
    database_url: str = "postgresql+asyncpg://user:password@localhost/twitter_db"
    database_url_sync: str = "postgresql://user:password@localhost/twitter_db"
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    secret_key: str = "your-secret-key-here"
    debug: bool = True
    statsd_host: str = "localhost"
    statsd_port: int = 8125

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings():
    return Settings()