# Capture The Princess — static web export (Godot 4, GL Compatibility).
# The wasm is ~38 MB, well past Cloudflare Pages' 25 MiB file cap, so the game
# is served from the Coolify origin next to every other 723 Studios site.
FROM nginx:stable-alpine
# 1.27-alpine builds on Alpine 3.21, whose brotli-libs/libcrypto3/libssl3 carry critical
# advisories with no fix in that release; stable-alpine tracks Alpine 3.24.
RUN apk upgrade --no-cache
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/health || exit 1
