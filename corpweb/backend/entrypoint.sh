#!/bin/bash
set -e

echo "=== CorpWeb Backend Startup ==="

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
while ! pg_isready -h postgres -p 5432 -U "$DB_USER" -q 2>/dev/null; do
    sleep 1
done
echo "PostgreSQL is ready"

# Run database migrations
echo "Running database migrations..."
alembic upgrade head

# Start the application
echo "Starting backend..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 "$@"
