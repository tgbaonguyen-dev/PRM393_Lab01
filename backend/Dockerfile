FROM dart:stable AS build

WORKDIR /app

# Copy dependency specifications
COPY pubspec.* ./
RUN dart pub get

# Copy source code and data
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Final production stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/bin/server /app/server
COPY --from=build /app/data /app/data

ENV PORT=8080
EXPOSE 8080

CMD ["/app/server"]
