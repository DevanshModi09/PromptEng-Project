# CampusCrew – Full-stack Docker image
# Frontend: nginx serving campuscrew_demo.html as /
# Backend:  Node.js (Express + SQLite) on internal port 3001
# nginx reverse-proxies /api/* to the backend
#
# Build:  docker build -t campuscrew .
# Run:    docker run -d -p 80:80 -v campuscrew_data:/data --name campuscrew campuscrew
# Logs:   docker logs -f campuscrew

# ── Stage 1: install backend dependencies ────────────────────
FROM node:20-alpine AS backend-deps
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: final runtime image ─────────────────────────────
FROM node:20-alpine

# nginx and supervisor (runs both nginx and node in one container)
RUN apk add --no-cache nginx supervisor

# ── Backend ───────────────────────────────────────────────────
WORKDIR /app/backend
COPY --from=backend-deps /app/backend/node_modules ./node_modules
COPY backend/ ./
# /data is a named volume; SQLite DB lives here for persistence
RUN mkdir -p /data

# ── Frontend ──────────────────────────────────────────────────
RUN mkdir -p /var/www/campuscrew
COPY campuscrew_demo.html /var/www/campuscrew/index.html

# ── nginx config ──────────────────────────────────────────────
RUN rm -f /etc/nginx/conf.d/default.conf
COPY docker/nginx.conf /etc/nginx/conf.d/campuscrew.conf

# ── supervisor config ─────────────────────────────────────────
COPY docker/supervisord.conf /etc/supervisord.conf

EXPOSE 80

VOLUME ["/data"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
