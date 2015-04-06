#!/bin/bash

docker run --name backbeat-postgres-$DOCKER_SHA -e POSTGRES_DB=backbeat_ci -e POSTGRES_USER=backbeat -e POSTGRES_PASSWORD=fed -d postgres:9.4
docker run --name backbeat-mongo-$DOCKER_SHA -d mongo:2.2
docker run --name backbeat-redis-$DOCKER_SHA -d redis:latest

docker build -t $DOCKER_IMAGE:latest .
docker run -e RACK_ENV=docker -i --link backbeat-postgres-$DOCKER_SHA:db --link backbeat-mongo-$DOCKER_SHA:mongo --link backbeat-redis-$DOCKER_SHA:redis $DOCKER_IMAGE:latest /app/run-tests.sh
TEST_EXIT=$?

docker stop backbeat-redis-$DOCKER_SHA
docker rm backbeat-redis-$DOCKER_SHA
docker stop backbeat-mongo-$DOCKER_SHA
docker rm backbeat-mongo-$DOCKER_SHA
docker stop backbeat-postgres-$DOCKER_SHA
docker rm backbeat-postgres-$DOCKER_SHA

exit $TEST_EXIT
