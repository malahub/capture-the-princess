# Capture The Princess — room relay (WebSocket, 20 Hz, 100 players/room).
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund
COPY index.js ./
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1
USER node
CMD ["node", "index.js"]
