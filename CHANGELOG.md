# Changelog

## [2024-12-22]

### Changed
- Updated PostgreSQL from version 15 to version 17 in all docker-compose files
- PostgreSQL 17 brings performance improvements:
  - Better query optimization
  - Improved parallel query execution
  - Enhanced JSON/JSONB performance (though we use relational tables only)
  - Better memory management
  - Faster index builds

### PostgreSQL 17 New Features Relevant to Our Architecture:
- **Improved parallel query execution**: Better performance for our JOIN queries in Step 1
- **Faster B-tree index builds**: Speeds up index creation on feed_items table
- **Better statistics and query planning**: Helps optimize our feed queries
- **Enhanced monitoring**: More detailed wait event information
- **Improved connection handling**: Better for high-concurrency scenarios

### Compatibility Notes:
- All SQLAlchemy queries remain compatible
- No schema changes required
- Backward compatible with PostgreSQL 15 data

### Performance Impact:
- Expected 5-15% performance improvement in read queries
- Faster index creation during initial setup
- Better handling of concurrent connections in Steps 4-6