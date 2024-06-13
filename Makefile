NAME?=mongodb-tools
PLATFORM?=linux
BASE_DIR?=$(shell readlink -f $(CURDIR))
VERSION?=$(shell grep -oP '"\d+\.\d+\.\d+(-\S+)?"' version.go | tr -d \")
GIT_COMMIT?=$(shell git rev-parse HEAD)
GIT_BRANCH?=$(shell git rev-parse --abbrev-ref HEAD)
GITHUB_REPO?=vtomasr5/$(NAME)
RELEASE_CACHE_DIR?=/tmp/$(NAME)_release.cache

TARGETPLATFORM ?= $(shell arch)
DOCKER_PROGRESS ?= plain
DOCKER_USER?=vtomasr5
MONGOD_DOCKERHUB_REPO?=${DOCKER_USER}/$(NAME)
MONGOD_DOCKERHUB_TAG?=$(VERSION)-mongod
ifneq ($(GIT_BRANCH), master)
	MONGOD_DOCKERHUB_TAG=$(VERSION)-mongod_$(GIT_BRANCH)
endif

GOARCH?=amd64
GO_VERSION?=1.22
GO_VERSION_MAJ_MIN=$(shell echo $(GO_VERSION) | cut -d. -f1-2)
GO_LDFLAGS?=-s -w
GO_LDFLAGS_FULL="${GO_LDFLAGS} -X main.GitCommit=${GIT_COMMIT} -X main.GitBranch=${GIT_BRANCH}"
GO_TEST_PATH?=./...
GOCACHE?=

ENABLE_MONGODB_TESTS?=false
TEST_PSMDB_VERSION?=5.0-multi
TEST_RS_NAME?=rs
TEST_MONGODB_DOCKER_UID?=1001
TEST_ADMIN_USER?=admin
TEST_ADMIN_PASSWORD?=123456
TEST_PRIMARY_PORT?=65217
TEST_SECONDARY1_PORT?=65218
TEST_SECONDARY2_PORT?=65219

TEST_CODECOV?=false
TEST_GO_EXTRA?=
ifeq ($(TEST_CODECOV), true)
	TEST_GO_EXTRA=-coverprofile=cover.out -covermode=atomic
endif

all: k8s

k8s: bin/mongodb-healthcheck

vendor:
	go mod vendor

bin/mongodb-healthcheck: vendor cmd/mongodb-healthcheck/main.go healthcheck/*.go internal/*.go internal/*/*.go internal/*/*/*.go pkg/*.go
	CGO_ENABLED=0 GOCACHE=$(GOCACHE) GOOS=$(PLATFORM) GOARCH=$(GOARCH) go build -ldflags=$(GO_LDFLAGS_FULL) -o bin/mongodb-healthcheck cmd/mongodb-healthcheck/main.go

test: vendor
	GOCACHE=$(GOCACHE) ENABLE_MONGODB_TESTS=$(ENABLE_MONGODB_TESTS) go test -v $(TEST_GO_EXTRA) $(GO_TEST_PATH)

test-race: vendor
	GOCACHE=$(GOCACHE) ENABLE_MONGODB_TESTS=$(ENABLE_MONGODB_TESTS) go test -v -race $(TEST_GO_EXTRA) $(GO_TEST_PATH)

test-full-prepare:
	TEST_RS_NAME=$(TEST_RS_NAME) \
	TEST_PSMDB_VERSION=$(TEST_PSMDB_VERSION) \
	TEST_ADMIN_USER=$(TEST_ADMIN_USER) \
	TEST_ADMIN_PASSWORD=$(TEST_ADMIN_PASSWORD) \
	TEST_PRIMARY_PORT=$(TEST_PRIMARY_PORT) \
	TEST_SECONDARY1_PORT=$(TEST_SECONDARY1_PORT) \
	TEST_SECONDARY2_PORT=$(TEST_SECONDARY2_PORT) \
	docker compose up -d \
	--force-recreate \
	--remove-orphans
	docker/test/init-test-replset-wait.sh

test-full-clean:
	docker compose down --volumes

test-full: vendor
	ENABLE_MONGODB_TESTS=true \
	TEST_RS_NAME=$(TEST_RS_NAME) \
	TEST_ADMIN_USER=$(TEST_ADMIN_USER) \
	TEST_ADMIN_PASSWORD=$(TEST_ADMIN_PASSWORD) \
	TEST_PRIMARY_PORT=$(TEST_PRIMARY_PORT) \
	TEST_SECONDARY1_PORT=$(TEST_SECONDARY1_PORT) \
	TEST_SECONDARY2_PORT=$(TEST_SECONDARY2_PORT) \
	GOCACHE=$(GOCACHE) go test -v -race $(TEST_GO_EXTRA) $(GO_TEST_PATH)
ifeq ($(TEST_CODECOV), true)
	curl -s https://codecov.io/bash | bash -s - -t ${CODECOV_TOKEN}
endif

release: clean
	docker build --build-arg GOLANG_DOCKERHUB_TAG=$(GO_VERSION_MAJ_MIN)-bookworm -t $(NAME)_release -f docker/Dockerfile.release .
	docker run --rm --network=host \
	-v $(BASE_DIR)/bin:/go/src/github.com/$(GITHUB_REPO)/bin \
	-e ENABLE_MONGODB_TESTS=$(ENABLE_MONGODB_TESTS) \
	-e TEST_CODECOV=$(TEST_CODECOV) \
	-e CODECOV_TOKEN=$(CODECOV_TOKEN) \
	-e TEST_RS_NAME=$(TEST_RS_NAME) \
	-e TEST_ADMIN_USER=$(TEST_ADMIN_USER) \
	-e TEST_ADMIN_PASSWORD=$(TEST_ADMIN_PASSWORD) \
	-e TEST_PRIMARY_PORT=$(TEST_PRIMARY_PORT) \
	-e TEST_SECONDARY1_PORT=$(TEST_SECONDARY1_PORT) \
	-e TEST_SECONDARY2_PORT=$(TEST_SECONDARY2_PORT) \
	-i $(NAME)_release

release-clean:
	rm -rf $(RELEASE_CACHE_DIR) 2>/dev/null
	docker rmi -f $(NAME)_release 2>/dev/null

docker-clean:
	docker rmi -f $(NAME)_release 2>/dev/null
	docker rmi -f $(NAME):$(MONGOD_DOCKERHUB_TAG) 2>/dev/null

docker-mongod: release
	docker build -t $(NAME):$(MONGOD_DOCKERHUB_TAG) -f docker/mongod/Dockerfile .
	docker run --rm -i $(NAME):$(MONGOD_DOCKERHUB_TAG) mongod --version
	docker run --rm -i $(NAME):$(MONGOD_DOCKERHUB_TAG) mongodb-healthcheck --version

docker-mongod-push:
	docker tag $(NAME):$(MONGOD_DOCKERHUB_TAG) $(MONGOD_DOCKERHUB_REPO):$(MONGOD_DOCKERHUB_TAG)
	docker push $(MONGOD_DOCKERHUB_REPO):$(MONGOD_DOCKERHUB_TAG)
ifeq ($(GIT_BRANCH), master)
	docker tag $(NAME):$(MONGOD_DOCKERHUB_TAG) $(MONGOD_DOCKERHUB_REPO):latest
	docker push $(MONGOD_DOCKERHUB_REPO):latest
endif

clean:
	rm -rf bin cover.out vendor 2>/dev/null || true
