NAME?=mongodb-tools
PLATFORM?=$(shell uname -s | tr '[:upper:]' '[:lower:]')
BASE_DIR?=$(shell readlink -f $(CURDIR))
VERSION?=$(shell grep -oE '"\d+\.\d+\.\d+(-\S+)?"' version.go | tr -d \")
GIT_COMMIT?=$(shell git rev-parse HEAD)
GIT_BRANCH?=$(shell git rev-parse --abbrev-ref HEAD)

TAG?=$(shell git rev-parse --verify HEAD --short=16)
DOCKER_PROGRESS?=plain
DOCKER_USER?=vtomasr5
IMAGE_NAME?=${DOCKER_USER}/$(NAME)

GOARCH?=$(shell arch | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
GO_VERSION?=1.22
GO_VERSION_MAJ_MIN=$(shell echo $(GO_VERSION) | cut -d. -f1-2)
GO_LDFLAGS?=-s -w
GO_LDFLAGS_FULL="${GO_LDFLAGS} -X main.GitCommit=${GIT_COMMIT} -X main.GitBranch=${GIT_BRANCH}"
GO_TEST_PATH?=./...
GOCACHE?=

# default list of platforms for which multiarch image is built
ifeq (${PLATFORMS}, )
	export PLATFORMS="linux/amd64,linux/arm64"
	export DOCKER_PLATFORMS="linux/amd64,linux/arm64"
endif

# if IMG_RESULT is unspecified, by default the image will be pushed to registry
ifeq (${IMG_RESULT}, load)
	export PUSH_ARG="--load"
    # if load is specified, image will be built only for the build machine architecture.
    export PLATFORMS="local"
else ifeq (${IMG_RESULT}, cache)
	# if cache is specified, image will only be available in the build cache, it won't be pushed or loaded
	# therefore no PUSH_ARG will be specified
else
	export PUSH_ARG="--push"
endif

.PHONY: all
all: docker-build

.PHONY: k8s
k8s: bin/mongodb-healthcheck

.PHONY: vendor
vendor:
	go mod vendor

.PHONY: bin/mongodb-healthcheck
bin/mongodb-healthcheck: vendor cmd/mongodb-healthcheck/main.go healthcheck/*.go internal/*.go internal/*/*.go  pkg/*.go
	CGO_ENABLED=0 GOCACHE=$(GOCACHE) GOOS=$(PLATFORM) GOARCH=$(GOARCH) go build -ldflags=$(GO_LDFLAGS_FULL) -o bin/mongodb-healthcheck cmd/mongodb-healthcheck/main.go

.PHONY: clean
clean:
	rm -rf bin cover.out vendor 2>/dev/null || true

.PHONY: docker-build
docker-build: ## use Docker buildx to create normal and dind runner containers
	export DOCKER_CLI_EXPERIMENTAL=enabled ;\
	export DOCKER_BUILDKIT=1
	@if ! docker buildx ls | grep -q container-builder; then\
		docker buildx create --platform ${PLATFORMS} --name container-builder --use;\
	fi
	docker buildx build --platform ${PLATFORMS} --progress ${DOCKER_PROGRESS} \
		--build-arg GOLANG_DOCKERHUB_TAG=$(GO_VERSION_MAJ_MIN)-bookworm \
		-t "${IMAGE_NAME}:${TAG}${TAG_SUFFIX}" \
		-t "${IMAGE_NAME}:latest${TAG_SUFFIX}" \
		-f docker/Dockerfile.release \
		. ${PUSH_ARG}

docker-build-amd64: ## use Docker buildx to create containers for amd64 only
docker-build-amd64: export PLATFORMS = linux/amd64
docker-build-amd64: export TAG_SUFFIX := ${TAG_SUFFIX}-amd64
docker-build-amd64: docker-build

docker-build-arm64: ## use Docker buildx to create containers for arm64 only
docker-build-arm64: export PLATFORMS = linux/arm64
docker-build-arm64: export TAG_SUFFIX := ${TAG_SUFFIX}-arm64
docker-build-arm64: docker-build

docker-build-multiarch-manifest: ## Combine arch images built separately into single manifest
	docker buildx imagetools create \
		-t "${IMAGE_NAME}:${TAG}${TAG_SUFFIX}" \
		"${IMAGE_NAME}:${TAG}${TAG_SUFFIX}-amd64" \
		"${IMAGE_NAME}:${TAG}${TAG_SUFFIX}-arm64"


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

.PHONY: test
test: vendor
	GOCACHE=$(GOCACHE) ENABLE_MONGODB_TESTS=$(ENABLE_MONGODB_TESTS) go test -v $(TEST_GO_EXTRA) $(GO_TEST_PATH)

.PHONY: test-race
test-race: vendor
	GOCACHE=$(GOCACHE) ENABLE_MONGODB_TESTS=$(ENABLE_MONGODB_TESTS) go test -v -race $(TEST_GO_EXTRA) $(GO_TEST_PATH)

.PHONY: test-full-prepare
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

.PHONY: test-full-clean
test-full-clean:
	docker compose down --volumes

.PHONY: test-full
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
