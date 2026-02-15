# Environment Configuration

This folder contains environment-specific configuration files for the Call Service.

## Available Environments

| File | Environment | Description |
|------|-------------|-------------|
| `dev.env` | Development | Local development with debug logging |
| `test.env` | Test | Automated testing with isolated databases |
| `staging.env` | Staging | Pre-production environment |
| `prod.env` | Production | Production environment with secrets from vault |
| `docker.env` | Docker | Docker Compose local development |

## Usage

### Local Development

```bash
cp envs/dev.env .env
mix phx.server
```

### Docker Development

```bash
docker-compose --env-file envs/docker.env up
```

## Service-Specific Variables

### WebRTC/TURN Configuration

- `STUN_SERVER_URL` - STUN server for NAT traversal
- `TURN_SERVER_URL` - TURN server for relay
- `TURN_USERNAME` - TURN authentication username
- `TURN_PASSWORD` - TURN authentication password
