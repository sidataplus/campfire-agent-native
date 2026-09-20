# syntax = docker/dockerfile:1

# Preserve the audited upstream dependency set; do not upgrade Rails in WP01.
ARG RUBY_VERSION=3.4.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libsqlite3-0 libvips libjemalloc2 ffmpeg redis util-linux && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archive
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build
RUN apt-get update -qq && \
    apt-get install -y build-essential git pkg-config libyaml-dev libssl-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY Gemfile Gemfile.lock vendor ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git
COPY . .
# Only this exact asset task may boot with a dummy build-time secret.
RUN SECRET_KEY_BASE_DUMMY=1 SKIP_TELEMETRY=true ./bin/rails assets:precompile

FROM base
ARG OCI_DESCRIPTION="Agent Campfire WP01 qualification candidate"
LABEL org.opencontainers.image.description="${OCI_DESCRIPTION}"
ARG OCI_SOURCE="https://github.com/sidataplus/campfire-agent-native"
LABEL org.opencontainers.image.source="${OCI_SOURCE}"
LABEL org.opencontainers.image.licenses="MIT"
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
ENV HTTP_IDLE_TIMEOUT=60 HTTP_READ_TIMEOUT=300 HTTP_WRITE_TIMEOUT=300 \
    PORT=8080 CAMPFIRE_PUMA_PORT=3001 WEB_CONCURRENCY=1 JOB_CONCURRENCY=1 \
    CAMPFIRE_AGENT_ENABLED=false CAMPFIRE_AGENT_DISPATCH_ENABLED=false SKIP_TELEMETRY=true
COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails
COPY --chmod=755 hooks /hooks
ARG APP_VERSION="agent-wp01"
ENV APP_VERSION=$APP_VERSION
ARG GIT_REVISION
ENV GIT_REVISION=$GIT_REVISION
EXPOSE 8080
# Root exists only to initialize a root-owned mounted volume. The entrypoint
# immediately drops to UID/GID 1000 before preflight, migrations or any service.
USER 0:0
ENTRYPOINT ["bin/container-entrypoint"]
CMD ["bin/boot"]
