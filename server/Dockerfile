# Capture The Princess — room relay (WebSocket, 20 Hz, 100 players/room).
FROM node:24.22.3-alpine
# Alpine base images freeze their packages at release time; the floating node:*-alpine tag
# can resolve to an older Alpine minor, leaving brotli-libs/libcrypto3/libssl3 critical
# advisories behind. Refresh them before the app is added.
RUN apk upgrade --no-cache
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
