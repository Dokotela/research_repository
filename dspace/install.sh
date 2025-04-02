#!/bin/bash

sudo apt update && sudo apt upgrade -y
sudo apt-get install openjdk-17-jdk

git clone https://github.com/DSpace/dspace-angular.git
cd dspace-angular
git checkout main

docker compose -f docker/docker-compose.yml -f docker/docker-compose-rest.yml pull

docker compose -p d8 \
    -f docker/docker-compose.yml \
    -f docker/docker-compose-rest.yml \
    up -d
