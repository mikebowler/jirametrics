FROM ruby:4.0-slim

ENV APP_HOME=/app
ENV BUNDLE_PATH=/usr/local/bundle
ENV RUBYLIB=/app/lib

WORKDIR ${APP_HOME}

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    ca-certificates \
    libyaml-dev \
    pkg-config \
    graphviz \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile jirametrics.gemspec ./
COPY lib ./lib
COPY bin ./bin

RUN chmod +x ./bin/jirametrics ./bin/jirametrics-mcp \
  && bundle install

ENTRYPOINT ["bundle", "exec", "ruby", "-I/app/lib", "/app/bin/jirametrics"]
CMD ["--help"]
