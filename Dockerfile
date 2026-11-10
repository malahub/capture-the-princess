# Capture The Princess — static web export (Godot 4, GL Compatibility).
# The wasm is ~38 MB, well past Cloudflare Pages' 25 MiB file cap, so the game
# is served from the Coolify origin next to every other 723 Studios site.
FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/health || exit 1
