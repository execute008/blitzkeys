#!/bin/bash
# Docker entrypoint script

set -e

# Assign a default for the database_user
DB_USER=${DATABASE_USER:-postgres}

echo "Waiting for database to be ready..."

# Wait until Postgres is ready
while ! pg_isready -q -h $DATABASE_HOST -p 5432 -U $DB_USER
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

echo "Database is ready!"

bin="/app/bin/blitzkeys"

# Create database if it doesn't exist
echo "Creating database..."
eval "$bin eval \"Blitzkeys.Release.create\""

# Run migrations
echo "Running migrations..."
eval "$bin eval \"Blitzkeys.Release.migrate\""

echo "Starting application..."

# Start the Elixir application
exec "$bin" "start"
