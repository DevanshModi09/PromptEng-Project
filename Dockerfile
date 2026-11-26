# CampusCrew – single Node.js container for Render
# Express serves the frontend HTML + all /api/* routes
# No nginx, no supervisord

FROM node:20-alpine

# better-sqlite3 needs native build tools
RUN apk add --no-cache python3 make g++

WORKDIR /app

# Install backend dependencies
COPY backend/package*.json ./backend/
RUN cd backend && npm install --omit=dev

# Copy app files
COPY backend/ ./backend/
COPY campuscrew_demo.html ./campuscrew_demo.html

# Render injects PORT automatically; fallback to 3001 for local dev
ENV NODE_ENV=production

EXPOSE 3001

CMD ["node", "backend/server.js"]
