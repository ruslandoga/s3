.PHONY: help minio

help:
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

minio: ## Start a transient container with a recent version of minio
	docker run -d --rm -p 9000:9000 -p 9001:9001 --name minio minio/minio server /data --address ":9000" --console-address ":9001"
	while ! docker exec minio mc alias set local http://localhost:9000 minioadmin minioadmin; do sleep 1; done
	docker exec minio mc mb local/testbucket
