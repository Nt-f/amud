# syntax=docker/dockerfile:1
# Builds the Flutter web app from source, then serves it with nginx.
#   docker build -t flutter-siddur .
#   docker run -d -p 8088:8088 flutter-siddur   → http://localhost:8088
# Options:
#   --build-arg SYNC_SEFARIA=1       re-download texts from Sefaria first
#   --build-arg BASE_HREF=/siddur/   when served from a sub-path
# To deploy the precompiled web-dist/ without the Flutter SDK, use Dockerfile.prebuilt.
ARG FLUTTER_VERSION=3.41.2

FROM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY packages/hebcal/pubspec.yaml packages/hebcal/pubspec.yaml
COPY packages/siddur_engine/pubspec.yaml packages/siddur_engine/pubspec.yaml
RUN flutter pub get
COPY . .
ARG SYNC_SEFARIA=0
RUN if [ "$SYNC_SEFARIA" = "1" ]; then dart run tool/sefaria_sync.dart; fi
ARG BASE_HREF=/
RUN BASE_HREF="$BASE_HREF" bash tool/build_web.sh

# Export target: refresh web-dist/ on the host from the same build.
#   docker build --target web-dist --output web-dist .
FROM scratch AS web-dist
COPY --from=build /app/web-dist/ /

FROM nginx:1.29-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/web-dist/ /usr/share/nginx/html/
EXPOSE 8088
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8088/ >/dev/null || exit 1
