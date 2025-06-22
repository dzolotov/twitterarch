import statsd
from typing import Optional
from common.config import get_settings
import time
from functools import wraps
import asyncio

settings = get_settings()


class MetricsService:
    _instance: Optional['MetricsService'] = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        if not hasattr(self, 'client'):
            self.client = statsd.StatsClient(
                host=settings.statsd_host,
                port=settings.statsd_port,
                prefix='twitter_app'
            )
    
    async def initialize(self):
        """Initialize metrics service"""
        # Test connection
        self.client.incr('app.started')
    
    def increment(self, metric: str, value: int = 1, tags: dict = None):
        """Increment a counter"""
        metric_name = self._format_metric(metric, tags)
        self.client.incr(metric_name, value)
    
    def gauge(self, metric: str, value: float, tags: dict = None):
        """Set a gauge value"""
        metric_name = self._format_metric(metric, tags)
        self.client.gauge(metric_name, value)
    
    def timing(self, metric: str, value: float, tags: dict = None):
        """Record a timing"""
        metric_name = self._format_metric(metric, tags)
        self.client.timing(metric_name, value * 1000)  # Convert to ms
    
    def timer(self, metric: str, tags: dict = None):
        """Context manager for timing"""
        return self.client.timer(self._format_metric(metric, tags))
    
    def _format_metric(self, metric: str, tags: dict = None) -> str:
        """Format metric name with tags"""
        if tags:
            tag_str = '.'.join([f"{k}_{v}" for k, v in tags.items()])
            return f"{metric}.{tag_str}"
        return metric


def track_time(metric_name: str):
    """Decorator to track execution time"""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            metrics = MetricsService()
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = time.time() - start_time
                metrics.timing(f"{metric_name}.success", duration)
                return result
            except Exception as e:
                duration = time.time() - start_time
                metrics.timing(f"{metric_name}.error", duration)
                metrics.increment(f"{metric_name}.error_count")
                raise
        
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            metrics = MetricsService()
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                duration = time.time() - start_time
                metrics.timing(f"{metric_name}.success", duration)
                return result
            except Exception as e:
                duration = time.time() - start_time
                metrics.timing(f"{metric_name}.error", duration)
                metrics.increment(f"{metric_name}.error_count")
                raise
        
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        return sync_wrapper
    
    return decorator