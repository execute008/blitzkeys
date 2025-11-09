#!/bin/bash
# Docker entrypoint script

# Assign a default for the database_user
DB_USER=${DATABASE_USER:-postgres}

# Wait until Postgres is ready
while ! pg_isready -q -h $DATABASE_HOST -p 5432 -U $DB_USER
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

bin="/app/bin/blitzkeys"
eval "$bin eval \"Blitzkeys.Release.migrate\""

# Start the Elixir application
exec "$bin" "start"
