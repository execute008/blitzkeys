# Blitzkeys

To start your Phoenix server:

* Start PostgreSQL with `docker compose up -d`
* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Development Database

The project uses Docker Compose to run PostgreSQL for local development:

```bash
# Start PostgreSQL
docker compose up -d

# Stop PostgreSQL
docker compose down

# View logs
docker compose logs -f postgres

# Reset database (removes all data)
docker compose down -v
```

## Docker Deployment

The project includes Docker support for easy deployment:

### Building and Running with Docker

```bash
# Build the Docker image
docker build -t blitzkeys:0.1.0 .

# Or use docker-compose to build and run everything
docker-compose up --build

# Run in detached mode
docker-compose up -d

# View logs
docker-compose logs -f app

# Stop the containers
docker-compose down
```

### Environment Configuration

1. Copy the example environment file:
   ```bash
   cp config/docker.env.example config/docker.env
   ```

2. Generate a new SECRET_KEY_BASE:
   ```bash
   mix phx.gen.secret
   ```

3. Update `config/docker.env` with your production values:
   - Set `PHX_HOST` to your production domain
   - Keep `PORT=4000` (internal container port)
   - External port is configured in `docker-compose.yml` (default: 36927)

### Production Deployment

The Docker setup creates a production-ready release that:
- Runs database migrations automatically on startup
- Waits for PostgreSQL to be ready before starting
- Uses multi-stage builds for smaller image sizes
- Runs as a non-root user for security

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
