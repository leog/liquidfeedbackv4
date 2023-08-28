## make build

`docker build -t lfv4 .`

## make run

`docker run --name lfv4 -p 8080:8080 -d lfv4`

## make bash

`docker exec -it lfv4 bash`

## clean

`docker stop lfv4 && docker rm lfv4`

# make findip

`docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lfv4`
