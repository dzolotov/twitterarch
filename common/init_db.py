import os
from sqlalchemy import text
from .database import sync_engine, Base
from .models import User, Tweet, Subscription


def init_regular_postgres():
    """Initialize regular PostgreSQL database"""
    print("Initializing regular PostgreSQL...")
    
    # Create tables
    Base.metadata.create_all(bind=sync_engine)
    
    # Create indexes
    with sync_engine.connect() as conn:
        conn.execute(text("CREATE INDEX IF NOT EXISTS idx_tweets_created ON tweets(created_at DESC)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS idx_tweets_author ON tweets(author_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS idx_subs_follower ON subscriptions(follower_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS idx_subs_followed ON subscriptions(followed_id)"))
        conn.commit()


def init_citus():
    """Initialize Citus distributed database"""
    print("Initializing Citus distributed database...")
    
    with sync_engine.connect() as conn:
        # Drop existing tables if they exist (for clean start)
        conn.execute(text("DROP TABLE IF EXISTS feed_items CASCADE"))
        conn.execute(text("DROP TABLE IF EXISTS subscriptions CASCADE"))
        conn.execute(text("DROP TABLE IF EXISTS tweets CASCADE"))
        conn.execute(text("DROP TABLE IF EXISTS users CASCADE"))
        conn.commit()
    
    # Create tables
    Base.metadata.create_all(bind=sync_engine)
    
    with sync_engine.connect() as conn:
        print("Distributing tables across Citus cluster...")
        
        # Distribute users table by id
        # This is our main distribution key - user data will be sharded by user_id
        conn.execute(text("SELECT create_distributed_table('users', 'id', shard_count => 32)"))
        
        # Distribute tweets by author_id and colocate with users
        # This ensures user's tweets are on the same shard as the user
        conn.execute(text("SELECT create_distributed_table('tweets', 'author_id', colocate_with => 'users')"))
        
        # Distribute subscriptions by follower_id and colocate with users
        # This ensures a user's follows are on the same shard as the user
        conn.execute(text("SELECT create_distributed_table('subscriptions', 'follower_id', colocate_with => 'users')"))
        
        # Distribute feed_items by user_id and colocate with users
        # This ensures a user's feed is on the same shard as the user
        conn.execute(text("SELECT create_distributed_table('feed_items', 'user_id', colocate_with => 'users')"))
        
        # Create distributed indexes
        conn.execute(text("CREATE INDEX idx_users_username ON users(username)"))
        conn.execute(text("CREATE INDEX idx_tweets_created ON tweets(created_at DESC)"))
        conn.execute(text("CREATE INDEX idx_tweets_author_created ON tweets(author_id, created_at DESC)"))
        conn.execute(text("CREATE INDEX idx_subs_follower ON subscriptions(follower_id)"))
        conn.execute(text("CREATE INDEX idx_subs_followed ON subscriptions(followed_id)"))
        conn.execute(text("CREATE INDEX idx_feed_user_created ON feed_items(user_id, created_at DESC)"))
        
        # Create reference table for small lookups (if needed in future)
        # conn.execute(text("SELECT create_reference_table('some_lookup_table')"))
        
        conn.commit()
        
        # Show distribution info
        result = conn.execute(text("""
            SELECT 
                logicalrelid::regclass AS table_name,
                column_to_column_name(logicalrelid, partkey) AS dist_column,
                colocationid,
                repmodel
            FROM pg_dist_partition
            ORDER BY logicalrelid
        """))
        
        print("\nTable distribution:")
        for row in result:
            print(f"  {row[0]}: distributed by {row[1]} (colocation group: {row[2]})")
        
        # Show shard placement
        result = conn.execute(text("""
            SELECT 
                nodename,
                COUNT(*) as shard_count
            FROM pg_dist_placement p
            JOIN pg_dist_node n ON p.groupid = n.groupid
            GROUP BY nodename
            ORDER BY nodename
        """))
        
        print("\nShard distribution across nodes:")
        for row in result:
            print(f"  {row[0]}: {row[1]} shards")


def init_database():
    """Initialize database based on DB_TYPE environment variable"""
    db_type = os.getenv('DB_TYPE', 'postgres').lower()
    
    if db_type == 'citus':
        init_citus()
    else:
        init_regular_postgres()
    
    print(f"\nDatabase initialized in {db_type} mode")


if __name__ == "__main__":
    init_database()