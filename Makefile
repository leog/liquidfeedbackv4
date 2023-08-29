build:
	docker build -t lfv4 .

run:
	docker run --name lfv4 -p 8080:8080 -d lfv4

bash:
	docker exec -it lfv4 bash

clean:
	docker stop lfv4 && docker rm lfv4

findip:
	docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' lfv4