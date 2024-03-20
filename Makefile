# Ensure Make is run with bash shell as some syntax below is bash-specific
# 确保使用bash shell运行Make，因为下面的语法是bash特定的
SHELL:=/usr/bin/env bash

.DEFAULT_GOAL:=help

#
# Go.
#
GO_VERSION ?= 1.19.2
GO_CONTAINER_IMAGE ?= docker.io/library/golang:$(GO_VERSION)

# Use GOPROXY environment variable if set
# 如果设置了GOPROXY环境变量，则使用它
GOPROXY := $(shell go env GOPROXY)
ifeq ($(GOPROXY),)
GOPROXY := https://goproxy.cn,direct
endif
export GOPROXY

# Active module mode, as we use go modules to manage dependencies
# 激活模块模式，因为我们使用go modules来管理依赖关系
export GO111MODULE=on

# This option is for running docker manifest command
# 这个选项用于运行docker manifest命令
export DOCKER_CLI_EXPERIMENTAL := enabled

#
# Directories.
#
# Full directory of where the Makefile resides
# Makefile所在的完整目录
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
EXP_DIR := exp
BIN_DIR := bin
TEST_DIR := test
TOOLS_DIR := hack/tools
TOOLS_BIN_DIR := $(abspath $(TOOLS_DIR)/$(BIN_DIR))
E2E_FRAMEWORK_DIR := $(TEST_DIR)/framework
GO_INSTALL := ./scripts/go_install.sh

export PATH := $(abspath $(TOOLS_BIN_DIR)):$(PATH)

#
# Binaries.
#
# Note: Need to use abspath so we can invoke these from subdirectories
# 注意：需要使用abspath，这样我们可以从子目录中调用它们
KUSTOMIZE_VER := v4.5.2
KUSTOMIZE_BIN := kustomize
KUSTOMIZE := $(abspath $(TOOLS_BIN_DIR)/$(KUSTOMIZE_BIN)-$(KUSTOMIZE_VER))
KUSTOMIZE_PKG := sigs.k8s.io/kustomize/kustomize/v4

SETUP_ENVTEST_VER := v0.0.0-20211110210527-619e6b92dab9
SETUP_ENVTEST_BIN := setup-envtest
SETUP_ENVTEST := $(abspath $(TOOLS_BIN_DIR)/$(SETUP_ENVTEST_BIN)-$(SETUP_ENVTEST_VER))
SETUP_ENVTEST_PKG := sigs.k8s.io/controller-runtime/tools/setup-envtest

CONTROLLER_GEN_VER := v0.9.1
CONTROLLER_GEN_BIN := controller-gen
CONTROLLER_GEN := $(abspath $(TOOLS_BIN_DIR)/$(CONTROLLER_GEN_BIN)-$(CONTROLLER_GEN_VER))
CONTROLLER_GEN_PKG := sigs.k8s.io/controller-tools/cmd/controller-gen

GOTESTSUM_VER := v1.6.4
GOTESTSUM_BIN := gotestsum
GOTESTSUM := $(abspath $(TOOLS_BIN_DIR)/$(GOTESTSUM_BIN)-$(GOTESTSUM_VER))
GOTESTSUM_PKG := gotest.tools/gotestsum

HADOLINT_VER := v2.10.0
HADOLINT_FAILURE_THRESHOLD = warning

GOLANGCI_LINT_BIN := golangci-lint
GOLANGCI_LINT := $(abspath $(TOOLS_BIN_DIR)/$(GOLANGCI_LINT_BIN))

# Define Docker related variables. Releases should modify and double check these vars.
REGISTRY ?= docker.io/kubespheredev
PROD_REGISTRY ?= docker.io/kubesphere

# capkk
CAPKK_IMAGE_NAME ?= capkk-controller
CAPKK_CONTROLLER_IMG ?= $(REGISTRY)/$(CAPKK_IMAGE_NAME)

# bootstrap
K3S_BOOTSTRAP_IMAGE_NAME ?= k3s-bootstrap-controller
K3S_BOOTSTRAP_CONTROLLER_IMG ?= $(REGISTRY)/$(K3S_BOOTSTRAP_IMAGE_NAME)

# control plane
K3S_CONTROL_PLANE_IMAGE_NAME ?= k3s-control-plane-controller
K3S_CONTROL_PLANE_CONTROLLER_IMG ?= $(REGISTRY)/$(K3S_CONTROL_PLANE_IMAGE_NAME)

# It is set by Prow GIT_TAG, a git-based tag of the form vYYYYMMDD-hash, e.g., v20210120-v0.3.10-308-gc61521971
# 它由Prow GIT_TAG设置，一个基于git的标签，格式为vYYYYMMDD-hash，例如，v20210120-v0.3.10-308-gc61521971
TAG ?= dev
ARCH ?= $(shell go env GOARCH)
ALL_ARCH = amd64 arm arm64 ppc64le s390x

# Allow overriding the imagePullPolicy
# 允许覆盖imagePullPolicy
PULL_POLICY ?= Always

# Hosts running SELinux need :z added to volume mounts
# 运行SELinux的主机需要在卷挂载上添加
SELINUX_ENABLED := $(shell cat /sys/fs/selinux/enforce 2> /dev/null || echo 0)

ifeq ($(SELINUX_ENABLED),1)
  DOCKER_VOL_OPTS?=:z
endif

# Set build time variables including version details
# 设置构建时的版本详细信息
LDFLAGS := $(shell hack/version.sh)

# Set kk build tags
# 设置kk构建标签
BUILDTAGS = exclude_graphdriver_devicemapper exclude_graphdriver_btrfs containers_image_openpgp

.PHONY: all
all: test managers

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} /^[0-9A-Za-z_-]+:.*?##/ { printf "  \033[36m%-45s\033[0m %s\n", $$1, $$2 } /^\$$\([0-9A-Za-z_-]+\):.*?##/ { gsub("_","-", $$1); printf "  \033[36m%-45s\033[0m %s\n", tolower(substr($$1, 3, length($$1)-7)), $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

## --------------------------------------
## Generate / Manifests
## --------------------------------------

##@ generate:
#定义了一个变量，包含了三个模块的名称。
ALL_GENERATE_MODULES = capkk k3s-bootstrap k3s-control-plane
#：定义了一个伪目标generate，表示这个目标不是实际的文件，而是一个执行一系列命令的方式。
#generate目标依赖于另外三个目标：generate-modules、generate-manifests和generate-go-deepcopy。当执行make generate时，会依次执行这三个目标。
.PHONY: generate
generate: ## Run all generate-manifests-*, generate-go-deepcopy-* targets
	$(MAKE) generate-modules generate-manifests generate-go-deepcopy
#定义了一个伪目标generate-manifests。
#generate-manifests目标依赖于另外三个目标：generate-manifests-capkk、generate-manifests-k3s-bootstrap和generate-manifests-k3s-control-plane。
.PHONY: generate-manifests
generate-manifests: ## Run all generate-manifest-* targets
	$(MAKE) $(addprefix generate-manifests-,$(ALL_GENERATE_MODULES))
#定义了一个伪目标generate-manifests-capkk。
#generate-manifests-capkk目标依赖于两个工具：controller-gen和kustomize。
#执行一个名为clean-generated-yaml的目标，传入一个参数SRC_DIRS，值为"./config/crd/bases"。
#执行controller-gen命令，生成CRD、RBAC等配置文件。
.PHONY: generate-manifests-capkk
generate-manifests-capkk: $(CONTROLLER_GEN) $(KUSTOMIZE) ## Generate manifests e.g. CRD, RBAC etc. for core
	$(MAKE) clean-generated-yaml SRC_DIRS="./config/crd/bases"
	$(CONTROLLER_GEN) \
		paths=./api/... \
		paths=./controllers/... \
		crd:crdVersions=v1 \
		rbac:roleName=manager-role \
		output:crd:dir=./config/crd/bases \
		output:webhook:dir=./config/webhook \
		webhook
#定义了一个伪目标generate-manifests-k3s-bootstrap。
#generate-manifests-k3s-bootstrap目标依赖于两个工具：controller-gen和kustomize。
.PHONY: generate-manifests-k3s-bootstrap
generate-manifests-k3s-bootstrap: $(CONTROLLER_GEN) $(KUSTOMIZE) ## Generate manifests e.g. CRD, RBAC etc. for core
	$(MAKE) clean-generated-yaml SRC_DIRS="./bootstrap/k3s/config/crd/bases"
	$(CONTROLLER_GEN) \
		paths=./bootstrap/k3s/api/... \
		paths=./bootstrap/k3s/controllers/... \
		crd:crdVersions=v1 \
		rbac:roleName=manager-role \
		output:crd:dir=./bootstrap/k3s/config/crd/bases \
		output:rbac:dir=./bootstrap/k3s/config/rbac \
		output:webhook:dir=./bootstrap/k3s/config/webhook \
		webhook


#定义了一个伪目标generate-manifests-k3s-control-plane。
#generate-manifests-k3s-control-plane目标依赖于两个工具：controller-gen和kustomize。
.PHONY: generate-manifests-k3s-control-plane
generate-manifests-k3s-control-plane: $(CONTROLLER_GEN) $(KUSTOMIZE) ## Generate manifests e.g. CRD, RBAC etc. for core
	$(MAKE) clean-generated-yaml SRC_DIRS="./controlplane/k3s/config/crd/bases"
	$(CONTROLLER_GEN) \
		paths=./controlplane/k3s/api/... \
		paths=./controlplane/k3s/controllers/... \
		crd:crdVersions=v1 \
		rbac:roleName=manager-role \
		output:crd:dir=./controlplane/k3s/config/crd/bases \
		output:rbac:dir=./controlplane/k3s/config/rbac \
		output:webhook:dir=./controlplane/k3s/config/webhook \
		webhook

#定义了一个伪目标generate-go-deepcopy。
#generate-go-deepcopy目标依赖于另外三个目标：generate-go-deepcopy-capkk、generate-go-deepcopy-k3s-bootstrap和generate-go-deepcopy-k3s-control-plane。
.PHONY: generate-go-deepcopy
generate-go-deepcopy:  ## Run all generate-go-deepcopy-* targets
	$(MAKE) $(addprefix generate-go-deepcopy-,$(ALL_GENERATE_MODULES))

#定义了一个伪目标generate-go-deepcopy-capkk。
#generate-go-deepcopy-capkk目标依赖于controller-gen工具。
.PHONY: generate-go-deepcopy-capkk
generate-go-deepcopy-capkk: $(CONTROLLER_GEN) ## Generate deepcopy go code for capkk
	$(MAKE) clean-generated-deepcopy SRC_DIRS="./api"
	$(CONTROLLER_GEN) \
		object:headerFile=./hack/boilerplate.go.txt \
		paths=./api/... \

#定义了一个伪目标generate-go-deepcopy-k3s-bootstrap。
#generate-go-deepcopy-k3s-bootstrap目标依赖于controller-gen工具。
.PHONY: generate-go-deepcopy-k3s-bootstrap
generate-go-deepcopy-k3s-bootstrap: $(CONTROLLER_GEN) ## Generate deepcopy go code for k3s-bootstrap
	$(MAKE) clean-generated-deepcopy SRC_DIRS="./bootstrap/k3s/api"
	$(CONTROLLER_GEN) \
		object:headerFile=./hack/boilerplate.go.txt \
		paths=./bootstrap/k3s/api/... \

#定义了一个伪目标generate-go-deepcopy-k3s-control-plane。
#generate-go-deepcopy-k3s-control-plane目标依赖于controller-gen工具。
.PHONY: generate-go-deepcopy-k3s-control-plane
generate-go-deepcopy-k3s-control-plane: $(CONTROLLER_GEN) ## Generate deepcopy go code for k3s-control-plane
	$(MAKE) clean-generated-deepcopy SRC_DIRS="./controlplane/k3s/api"
	$(CONTROLLER_GEN) \
		object:headerFile=./hack/boilerplate.go.txt \
		paths=./controlplane/k3s/api/... \

#定义了一个伪目标generate-modules。
#generate-modules目标依赖于go mod tidy命令，用于确保所有依赖的模块都是最新的。
.PHONY: generate-modules
generate-modules: ## Run go mod tidy to ensure modules are up to date
	go mod tidy

## --------------------------------------
## Lint / Verify
## --------------------------------------

##@ lint and verify:
# 定义了一个伪目标lint。
#lint目标依赖于golangci-lint工具。
#执行golangci-lint命令，对代码进行静态分析。
#切换到TEST_DIR目录，然后执行golangci-lint命令。
#切换到TOOLS_DIR目录，然后执行golangci-lint命令。
#执行一个名为ci-lint-dockerfiles.sh的脚本，传入两个参数：HADOLINT_VER和HADOLINT_FAILURE_THRESHOLD。
.PHONY: lint
lint: $(GOLANGCI_LINT) ## Lint the codebase
	$(GOLANGCI_LINT) run -v $(GOLANGCI_LINT_EXTRA_ARGS)
	cd $(TEST_DIR); $(GOLANGCI_LINT) run -v $(GOLANGCI_LINT_EXTRA_ARGS)
	cd $(TOOLS_DIR); $(GOLANGCI_LINT) run -v $(GOLANGCI_LINT_EXTRA_ARGS)
	./scripts/ci-lint-dockerfiles.sh $(HADOLINT_VER) $(HADOLINT_FAILURE_THRESHOLD)

#定义了一个伪目标lint-dockerfiles。
#执行一个名为ci-lint-dockerfiles.sh的脚本，传入两个参数：HADOLINT_VER和HADOLINT_FAILURE_THRESHOLD。
.PHONY: lint-dockerfiles
lint-dockerfiles:
	./scripts/ci-lint-dockerfiles.sh $(HADOLINT_VER) $(HADOLINT_FAILURE_THRESHOLD)

#verify目标依赖于另外三个目标：verify-modules、verify-gen和lint-dockerfiles。
.PHONY: verify
verify: $(addprefix verify-,$(ALL_VERIFY_CHECKS)) lint-dockerfiles ## Run all verify-* targets

#定义了一个伪目标verify-modules。
#verify-modules目标依赖于generate-modules目标。
#使用git命令检查go.mod和go.sum文件是否有变化，如果有变化则输出错误信息并退出。
#查找所有包含go.mod文件的目录，并检查是否包含不兼容的k8s.io/client-go版本。
#如果发现不兼容的k8s.io/client-go版本，则输出错误信息并退出。
.PHONY: verify-modules
verify-modules: generate-modules  ## Verify go modules are up to date
	@if !(git diff --quiet HEAD -- go.sum go.mod $(TOOLS_DIR)/go.mod $(TOOLS_DIR)/go.sum $(TEST_DIR)/go.mod $(TEST_DIR)/go.sum); then \
		git diff; \
		echo "go module files are out of date"; exit 1; \
	fi
	@if (find . -name 'go.mod' | xargs -n1 grep -q -i 'k8s.io/client-go.*+incompatible'); then \
		find . -name "go.mod" -exec grep -i 'k8s.io/client-go.*+incompatible' {} \; -print; \
		echo "go module contains an incompatible client-go version"; exit 1; \
	fi

.PHONY: verify-gen
verify-gen: generate  ## Verify go generated files are up to date
	@if !(git diff --quiet HEAD); then \
		git diff; \
		echo "generated files are out of date, run make generate"; exit 1; \
	fi

## --------------------------------------
## Binaries
## --------------------------------------

##@ build:
#定义了一个伪目标kk
# kk目标的依赖。
#定义了一个伪目标kk
# 使用go命令构建kk二进制文件，并将输出文件放到BIN_DIR目录下。
#定义了一个变量，包含了三个模块的名称。
.PHONY: kk
kk:
	CGO_ENABLED=0 go build -trimpath -tags "$(BUILDTAGS)" -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/kk github.com/kubesphere/kubekey/v3/cmd/kk;
ALL_MANAGERS = capkk k3s-bootstrap k3s-control-plane

#定义了一个伪目标managers。
#managers目标依赖于另外三个目标：manager-capkk、manager-k3s-bootstrap和manager-k3s-control-plane。
.PHONY: managers
managers: $(addprefix manager-,$(ALL_MANAGERS)) ## Run all manager-* targets

#定义了一个伪目标manager-capkk。
#manager-capkk目标的依赖。
#使用go命令构建capkk管理器二进制文件，并将输出文件放到BIN_DIR目录下。
.PHONY: manager-capkk
manager-capkk: ## Build the capkk manager binary into the ./bin folder
	go build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/manager github.com/kubesphere/kubekey/v3

#定义了一个伪目标manager-k3s-bootstrap。
#manager-k3s-bootstrap目标的依赖。
#使用go命令构建k3s-bootstrap管理器二进制文件，并将输出文件放到BIN_DIR目录下。
.PHONY: manager-k3s-bootstrap
manager-k3s-bootstrap: ## Build the k3s bootstrap manager binary into the ./bin folder
	go build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/k3s-bootstrap-manager github.com/kubesphere/kubekey/v3/bootstrap/k3s

#定义了一个伪目标manager-k3s-control-plane。
#manager-k3s-control-plane目标的依赖。
#使用go命令构建k3s-control-plane管理器二进制文件，并将输出文件放到BIN_DIR目录下。
.PHONY: manager-k3s-control-plane
manager-k3s-control-plane: ## Build the k3s control plane manager binary into the ./bin folder
	go build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/k3s-control-plane-manager github.com/kubesphere/kubekey/v3/controlplane/k3s

#定义了一个伪目标docker-pull-prerequisites。
#docker-pull-prerequisites目标的依赖。
#从Docker Hub拉取dockerfile镜像。
#从指定的镜像仓库拉取Go容器镜像。
.PHONY: docker-pull-prerequisites
docker-pull-prerequisites:
	docker pull docker.io/docker/dockerfile:1.4
	docker pull $(GO_CONTAINER_IMAGE)

#定义了一个伪目标docker-build-all。
#目标依赖于另外三个目标：docker-build-capkk、docker-build-k3s-bootstrap和docker-build-k3s-control-plane。
.PHONY: docker-build-all
docker-build-all: $(addprefix docker-build-,$(ALL_ARCH)) ## Build docker images for all architectures

#定义了一个模式规则，用于生成docker-build-*目标。
docker-build-%:
	$(MAKE) ARCH=$* docker-build

#执行docker-build目标，并传递ARCH参数。
ALL_DOCKER_BUILD = capkk k3s-bootstrap k3s-control-plane

#定义了一个变量，包含了三个模块的名称。
#定义了一个伪目标docker-build。
#docker-build目标依赖于docker-pull-prerequisites目标。
#执行docker-build-*目标，并传递ARCH参数。
.PHONY: docker-build
docker-build: docker-pull-prerequisites ## Run docker-build-* targets for all providers
	$(MAKE) ARCH=$(ARCH) $(addprefix docker-build-,$(ALL_DOCKER_BUILD))

#定义了一个伪目标docker-build-capkk。
#docker-build-capkk目标的依赖
#使用docker命令构建capkk的Docker镜像。
.PHONY: docker-build-capkk
docker-build-capkk: ## Build the docker image for capkk
	DOCKER_BUILDKIT=1 docker build --build-arg builder_image=$(GO_CONTAINER_IMAGE) --build-arg goproxy=$(GOPROXY) --build-arg ARCH=$(ARCH) --build-arg ldflags="$(LDFLAGS)" . -t $(CAPKK_CONTROLLER_IMG)-$(ARCH):$(TAG)

#定义了一个伪目标docker-build-k3s-bootstrap。
#docker-build-k3s-bootstrap目标的依赖。
#使用docker命令构建k3s-bootstrap的Docker镜像。
.PHONY: docker-build-k3s-bootstrap
docker-build-k3s-bootstrap: ## Build the docker image for k3s bootstrap controller manager
	DOCKER_BUILDKIT=1 docker build --build-arg builder_image=$(GO_CONTAINER_IMAGE) --build-arg goproxy=$(GOPROXY) --build-arg ARCH=$(ARCH) --build-arg package=./bootstrap/k3s --build-arg ldflags="$(LDFLAGS)" . -t $(K3S_BOOTSTRAP_CONTROLLER_IMG)-$(ARCH):$(TAG)

#定义了一个伪目标docker-build-k3s-control-plane。
#docker-build-k3s-control-plane目标的依赖。
#使用docker命令构建k3s-control-plane的Docker镜像。
.PHONY: docker-build-k3s-control-plane
docker-build-k3s-control-plane: ## Build the docker image for k3s control plane controller manager
	DOCKER_BUILDKIT=1 docker build --build-arg builder_image=$(GO_CONTAINER_IMAGE) --build-arg goproxy=$(GOPROXY) --build-arg ARCH=$(ARCH) --build-arg package=./controlplane/k3s --build-arg ldflags="$(LDFLAGS)" . -t $(K3S_CONTROL_PLANE_CONTROLLER_IMG)-$(ARCH):$(TAG)

#定义了一个伪目标docker-build-e2e
#docker-build-e2e目标的依赖。
#执行docker-build目标，并传递相关参数。
.PHONY: docker-build-e2e
docker-build-e2e: ## Build the docker image for capkk
	$(MAKE) docker-build REGISTRY=docker.io/kubespheredev PULL_POLICY=IfNotPresent TAG=e2e

## --------------------------------------
## Deployment
## --------------------------------------

##@ deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

#安装CRD到K8s集群，集群配置文件位于~/.kube/config。
.PHONY: install
install: generate $(KUSTOMIZE) ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

### 从K8s集群中卸载CRD。调用时使用ignore-not-found=true来忽略删除过程中的资源未找到错误。
.PHONY: uninstall
uninstall: generate $(KUSTOMIZE) ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

### 将控制器部署到K8s集群，集群配置文件位于~/.kube/config。
.PHONY: deploy
deploy: generate $(KUSTOMIZE) ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	$(MAKE) set-manifest-image \
		MANIFEST_IMG=$(REGISTRY)/$(CAPKK_IMAGE_NAME)-$(ARCH) MANIFEST_TAG=$(TAG) \
		TARGET_RESOURCE="./config/default/manager_image_patch.yaml"
	cd config/manager
	$(KUSTOMIZE) build config/default | kubectl apply -f -

# ## 从K8s集群中卸载控制器。调用时使用ignore-not-found=true来忽略删除过程中的资源未找到错误。
.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

## --------------------------------------
## Testing
## --------------------------------------

##@ test:

ARTIFACTS ?= ${ROOT_DIR}/_artifacts
# # 使用darwin/amd64二进制文件，直到有arm64版本可用
ifeq ($(shell go env GOOS),darwin) # Use the darwin/amd64 binary until an arm64 version is available
	KUBEBUILDER_ASSETS ?= $(shell $(SETUP_ENVTEST) use --use-env -p path --arch amd64 $(KUBEBUILDER_ENVTEST_KUBERNETES_VERSION))
else
	KUBEBUILDER_ASSETS ?= $(shell $(SETUP_ENVTEST) use --use-env -p path $(KUBEBUILDER_ENVTEST_KUBERNETES_VERSION))
endif
### 运行单元和集成测试
.PHONY: test
test: $(SETUP_ENVTEST) ## Run unit and integration tests
	KUBEBUILDER_ASSETS="$(KUBEBUILDER_ASSETS)" go test ./... $(TEST_ARGS)
### 运行单元和集成测试，并显示详细信息
.PHONY: test-verbose
test-verbose: ## Run unit and integration tests with verbose flag
	$(MAKE) test TEST_ARGS="$(TEST_ARGS) -v"
# ## 运行单元和集成测试，并生成junit报告
.PHONY: test-junit
test-junit: $(SETUP_ENVTEST) $(GOTESTSUM) ## Run unit and integration tests and generate a junit report
	set +o errexit; (KUBEBUILDER_ASSETS="$(KUBEBUILDER_ASSETS)" go test -json ./... $(TEST_ARGS); echo $$? > $(ARTIFACTS)/junit.exitcode) | tee $(ARTIFACTS)/junit.stdout
	$(GOTESTSUM) --junitfile $(ARTIFACTS)/junit.xml --raw-command cat $(ARTIFACTS)/junit.stdout
	exit $$(cat $(ARTIFACTS)/junit.exitcode)
# ## 运行单元和集成测试，并生成覆盖率报告
.PHONY: test-cover
test-cover: ## Run unit and integration tests and generate a coverage report
	$(MAKE) test TEST_ARGS="$(TEST_ARGS) -coverprofile=out/coverage.out"
	go tool cover -func=out/coverage.out -o out/coverage.txt
	go tool cover -html=out/coverage.out -o out/coverage.html
# ## 运行端到端测试
.PHONY: test-e2e
test-e2e: ## Run e2e tests
	$(MAKE) -C $(TEST_DIR)/e2e run
### 运行端到端测试（使用k3s）
.PHONY: test-e2e-k3s
test-e2e-k3s: ## Run e2e tests
	$(MAKE) -C $(TEST_DIR)/e2e run-k3s

## --------------------------------------
## Release
## --------------------------------------

##@ release:

## latest git tag for the commit, e.g., v0.3.10
## 获取最新的git标签，例如：v0.3.10
RELEASE_TAG ?= $(shell git describe --abbrev=0 2>/dev/null)
ifneq (,$(findstring -,$(RELEASE_TAG)))
    PRE_RELEASE=true
endif
# the previous release tag, e.g., v0.3.9, excluding pre-release tags
# 上一个发布标签，例如：v0.3.9，排除预发布标签
PREVIOUS_TAG ?= $(shell git tag -l | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$$" | sort -V | grep -B1 $(RELEASE_TAG) | head -n 1 2>/dev/null)
RELEASE_DIR := out

$(RELEASE_DIR):
	mkdir -p $(RELEASE_DIR)/

## 使用最新的git标签构建并推送容器镜像
.PHONY: release
release: clean-release ## Build and push container images using the latest git tag for the commit
	@if [ -z "${RELEASE_TAG}" ]; then echo "RELEASE_TAG is not set"; exit 1; fi
	@if ! [ -z "$$(git status --porcelain)" ]; then echo "Your local git repository contains uncommitted changes, use git clean before proceeding."; exit 1; fi
	git checkout "${RELEASE_TAG}"
	## Build binaries first.
	## 首先构建二进制文件。
	GIT_VERSION=$(RELEASE_TAG) $(MAKE) release-binaries
	# Set the manifest image to the production bucket.
	# 将manifest镜像设置为生产存储桶。
	$(MAKE) manifest-modification REGISTRY=$(PROD_REGISTRY)
	## Build the manifests
	## 构建manifests
	$(MAKE) release-manifests
	## Build the templates
	## 构建模板
	$(MAKE) release-templates
	## Clean the git artifacts modified in the release process
	# 清理在发布过程中修改的git工件
	$(MAKE) clean-release-git

### 构建要与发布一起发布的二进制文件
release-binaries: ## Build the binaries to publish with a release
	RELEASE_BINARY=./cmd/kk GOOS=linux GOARCH=amd64 $(MAKE) release-binary
	RELEASE_BINARY=./cmd/kk GOOS=linux GOARCH=amd64 $(MAKE) release-archive
	RELEASE_BINARY=./cmd/kk GOOS=linux GOARCH=arm64 $(MAKE) release-binary
	RELEASE_BINARY=./cmd/kk GOOS=linux GOARCH=arm64 $(MAKE) release-archive
	RELEASE_BINARY=./cmd/kk GOOS=darwin GOARCH=amd64 $(MAKE) release-binary
	RELEASE_BINARY=./cmd/kk GOOS=darwin GOARCH=amd64 $(MAKE) release-archive
	RELEASE_BINARY=./cmd/kk GOOS=darwin GOARCH=arm64 $(MAKE) release-binary
	RELEASE_BINARY=./cmd/kk GOOS=darwin GOARCH=arm64 $(MAKE) release-archive

release-binary: $(RELEASE_DIR)
	docker run \
		--rm \
		-e CGO_ENABLED=0 \
		-e GOOS=$(GOOS) \
		-e GOARCH=$(GOARCH) \
		-e GOPROXY=$(GOPROXY) \
		-v "$$(pwd):/workspace$(DOCKER_VOL_OPTS)" \
		-w /workspace \
		golang:$(GO_VERSION) \
		go build -a -trimpath -tags "$(BUILDTAGS)" -ldflags "$(LDFLAGS) -extldflags '-static'" \
		-o $(RELEASE_DIR)/$(notdir $(RELEASE_BINARY)) $(RELEASE_BINARY)

release-archive: $(RELEASE_DIR)
	tar -czf $(RELEASE_DIR)/kubekey-$(RELEASE_TAG)-$(GOOS)-$(GOARCH).tar.gz -C $(RELEASE_DIR)/ $(notdir $(RELEASE_BINARY))
	rm -rf  $(RELEASE_DIR)/$(notdir $(RELEASE_BINARY))

# 设置manifest镜像为staging/production存储桶。
.PHONY: manifest-modification
manifest-modification: # Set the manifest images to the staging/production bucket.
	$(MAKE) set-manifest-image \
		MANIFEST_IMG=$(REGISTRY)/$(CAPKK_IMAGE_NAME) MANIFEST_TAG=$(RELEASE_TAG) \
		TARGET_RESOURCE="./config/default/manager_image_patch.yaml"
	$(MAKE) set-manifest-image \
		MANIFEST_IMG=$(REGISTRY)/$(K3S_BOOTSTRAP_IMAGE_NAME) MANIFEST_TAG=$(RELEASE_TAG) \
		TARGET_RESOURCE="./bootstrap/k3s/config/default/manager_image_patch.yaml"
	$(MAKE) set-manifest-image \
    	MANIFEST_IMG=$(REGISTRY)/$(K3S_CONTROL_PLANE_IMAGE_NAME) MANIFEST_TAG=$(RELEASE_TAG) \
		TARGET_RESOURCE="./controlplane/k3s/config/default/manager_image_patch.yaml"
	$(MAKE) set-manifest-pull-policy PULL_POLICY=IfNotPresent TARGET_RESOURCE="./config/default/manager_pull_policy.yaml"
	$(MAKE) set-manifest-pull-policy PULL_POLICY=IfNotPresent TARGET_RESOURCE="./bootstrap/k3s/config/default/manager_pull_policy.yaml"
	$(MAKE) set-manifest-pull-policy PULL_POLICY=IfNotPresent TARGET_RESOURCE="./controlplane/k3s/config/default/manager_pull_policy.yaml"

#构建要与发布一起发布的manifests
.PHONY: release-manifests
release-manifests: $(RELEASE_DIR) $(KUSTOMIZE) ## Build the manifests to publish with a release
	# Build capkk-components.
	# 构建capkk-components。
	$(KUSTOMIZE) build config/default > $(RELEASE_DIR)/infrastructure-components.yaml
	# Build bootstrap-components.
	# 构建bootstrap-components。
	$(KUSTOMIZE) build bootstrap/k3s/config/default > $(RELEASE_DIR)/bootstrap-components.yaml
	# Build control-plane-components.
	# 构建control-plane-components。
	$(KUSTOMIZE) build controlplane/k3s/config/default > $(RELEASE_DIR)/control-plane-components.yaml

	# Add metadata to the release artifacts
	# 向发布构件添加元数据
	cp metadata.yaml $(RELEASE_DIR)/metadata.yaml

## 生成发布模板
.PHONY: release-templates
release-templates: $(RELEASE_DIR) ## Generate release templates
	cp templates/cluster-template*.yaml $(RELEASE_DIR)/

## 构建并将容器镜像推送到prod
.PHONY: release-prod
release-prod: ## Build and push container images to the prod
	REGISTRY=$(PROD_REGISTRY) TAG=$(RELEASE_TAG) $(MAKE) docker-build-all docker-push-all

## --------------------------------------
## Docker
## --------------------------------------
#定义一个伪目标，用于推送所有架构下的Docker镜像以及相关的多架构清单
## 推送capkk、k3s-bootstrap和k3s-control-plane的多架构清单
.PHONY: docker-push-all
docker-push-all: $(addprefix docker-push-,$(ALL_ARCH))  ## Push the docker images to be included in the release for all architectures + related multiarch manifests
	$(MAKE) docker-push-manifest-capkk
	$(MAKE) docker-push-manifest-k3s-bootstrap
	$(MAKE) docker-push-manifest-k3s-control-plane

#为每个架构生成推送Docker镜像的目标
docker-push-%:
	$(MAKE) ARCH=$* docker-push

# 推送Docker镜像的通用目标
# 推送CAPKK、K3S_BOOTSTRAP和K3S_CONTROL_PLANE控制器镜像的当前架构版本
.PHONY: docker-push
docker-push: ## Push the docker images
	docker push $(CAPKK_CONTROLLER_IMG)-$(ARCH):$(TAG)
	docker push $(K3S_BOOTSTRAP_CONTROLLER_IMG)-$(ARCH):$(TAG)
	docker push $(K3S_CONTROL_PLANE_CONTROLLER_IMG)-$(ARCH):$(TAG)

# 推送capkk Docker镜像的多架构清单
# 创建并推送capkk控制器镜像的多架构清单
.PHONY: docker-push-manifest-capkk
docker-push-manifest-capkk: ## Push the multiarch manifest for the capkk docker images
	## Minimum docker version 18.06.0 is required for creating and pushing manifest images.
	docker manifest create --amend $(CAPKK_CONTROLLER_IMG):$(TAG) $(shell echo $(ALL_ARCH) | sed -e "s~[^ ]*~$(CAPKK_CONTROLLER_IMG)\-&:$(TAG)~g")
	@for arch in $(ALL_ARCH); do docker manifest annotate --arch $${arch} ${CAPKK_CONTROLLER_IMG}:${TAG} ${CAPKK_CONTROLLER_IMG}-$${arch}:${TAG}; done
	docker manifest push --purge $(CAPKK_CONTROLLER_IMG):$(TAG)

#推送k3s-bootstrap Docker镜像的多架构清单
# 创建并推送k3s引导控制器镜像的多架构清单
.PHONY: docker-push-manifest-k3s-bootstrap
docker-push-manifest-k3s-bootstrap: ## Push the multiarch manifest for the k3s bootstrap docker images
	## Minimum docker version 18.06.0 is required for creating and pushing manifest images.
	docker manifest create --amend $(K3S_BOOTSTRAP_CONTROLLER_IMG):$(TAG) $(shell echo $(ALL_ARCH) | sed -e "s~[^ ]*~$(K3S_BOOTSTRAP_CONTROLLER_IMG)\-&:$(TAG)~g")
	@for arch in $(ALL_ARCH); do docker manifest annotate --arch $${arch} ${K3S_BOOTSTRAP_CONTROLLER_IMG}:${TAG} ${K3S_BOOTSTRAP_CONTROLLER_IMG}-$${arch}:${TAG}; done
	docker manifest push --purge $(K3S_BOOTSTRAP_CONTROLLER_IMG):$(TAG)

# 推送k3s-control-plane Docker镜像的多架构清单
# 创建并推送k3s控制面控制器镜像的多架构清单
.PHONY: docker-push-manifest-k3s-control-plane
docker-push-manifest-k3s-control-plane: ## Push the multiarch manifest for the k3s control plane docker images
	## Minimum docker version 18.06.0 is required for creating and pushing manifest images.
	docker manifest create --amend $(K3S_CONTROL_PLANE_CONTROLLER_IMG):$(TAG) $(shell echo $(ALL_ARCH) | sed -e "s~[^ ]*~$(K3S_CONTROL_PLANE_CONTROLLER_IMG)\-&:$(TAG)~g")
	@for arch in $(ALL_ARCH); do docker manifest annotate --arch $${arch} ${K3S_CONTROL_PLANE_CONTROLLER_IMG}:${TAG} ${K3S_CONTROL_PLANE_CONTROLLER_IMG}-$${arch}:${TAG}; done
	docker manifest push --purge $(K3S_CONTROL_PLANE_CONTROLLER_IMG):$(TAG)

# 更新kustomize资源的镜像拉取策略
# 更新管理资源的kustomize拉取策略文件
.PHONY: set-manifest-pull-policy
set-manifest-pull-policy:
	$(info Updating kustomize pull policy file for manager resources)
	sed -i'' -e 's@imagePullPolicy: .*@imagePullPolicy: '"$(PULL_POLICY)"'@' $(TARGET_RESOURCE)

#更新kustomize资源的镜像地址
#更新管理资源的kustomize镜像补丁文件
.PHONY: set-manifest-image
set-manifest-image:
	$(info Updating kustomize image patch file for manager resource)
	sed -i'' -e 's@image: .*@image: '"${MANIFEST_IMG}:$(MANIFEST_TAG)"'@' $(TARGET_RESOURCE)

## --------------------------------------
## Cleanup / Verification
## --------------------------------------

##@ clean:

.PHONY: clean
clean: ## Remove all generated files
	$(MAKE) clean-bin

.PHONY: clean-bin
clean-bin: ## Remove all generated binaries
	rm -rf $(BIN_DIR)
	rm -rf $(TOOLS_BIN_DIR)

.PHONY: clean-release
clean-release: ## Remove the release folder
	rm -rf $(RELEASE_DIR)

.PHONY: clean-release-git
clean-release-git: ## Restores the git files usually modified during a release
	git restore ./*manager_image_patch.yaml ./*manager_pull_policy.yaml

.PHONY: clean-generated-yaml
clean-generated-yaml: ## Remove files generated by conversion-gen from the mentioned dirs. Example SRC_DIRS="./api/v1beta1"
	(IFS=','; for i in $(SRC_DIRS); do find $$i -type f -name '*.yaml' -exec rm -f {} \;; done)

.PHONY: clean-generated-deepcopy
clean-generated-deepcopy: ## Remove files generated by conversion-gen from the mentioned dirs. Example SRC_DIRS="./api/v1beta1"
	(IFS=','; for i in $(SRC_DIRS); do find $$i -type f -name 'zz_generated.deepcopy*' -exec rm -f {} \;; done)

## --------------------------------------
## Hack / Tools
## --------------------------------------

##@ hack/tools:
#构建controller-gen本地副本
.PHONY: $(CONTROLLER_GEN_BIN)
$(CONTROLLER_GEN_BIN): $(CONTROLLER_GEN) ## Build a local copy of controller-gen.
# 构建gotestsum本地副本
.PHONY: $(GOTESTSUM_BIN)
$(GOTESTSUM_BIN): $(GOTESTSUM) ## Build a local copy of gotestsum.
# 构建kustomize本地副本
.PHONY: $(KUSTOMIZE_BIN)
$(KUSTOMIZE_BIN): $(KUSTOMIZE) ## Build a local copy of kustomize.
# 构建setup-envtest本地副本
.PHONY: $(SETUP_ENVTEST_BIN)
$(SETUP_ENVTEST_BIN): $(SETUP_ENVTEST) ## Build a local copy of setup-envtest.
# 构建golangci-lint本地副本
.PHONY: $(GOLANGCI_LINT_BIN)
$(GOLANGCI_LINT_BIN): $(GOLANGCI_LINT) ## Build a local copy of golangci-lint
# 从tools目录构建controller-gen
$(CONTROLLER_GEN): # Build controller-gen from tools folder.
	GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) $(CONTROLLER_GEN_PKG) $(CONTROLLER_GEN_BIN) $(CONTROLLER_GEN_VER)
# 从tools目录构建gotestsum
$(GOTESTSUM): # Build gotestsum from tools folder.
	GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) $(GOTESTSUM_PKG) $(GOTESTSUM_BIN) $(GOTESTSUM_VER)
# 从tools目录构建kustomize
$(KUSTOMIZE): # Build kustomize from tools folder.
	CGO_ENABLED=0 GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) $(KUSTOMIZE_PKG) $(KUSTOMIZE_BIN) $(KUSTOMIZE_VER)
# 从tools目录构建setup-envtest
$(SETUP_ENVTEST): # Build setup-envtest from tools folder.
	GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) $(SETUP_ENVTEST_PKG) $(SETUP_ENVTEST_BIN) $(SETUP_ENVTEST_VER)
# 使用hack脚本在tools目录下载golangci-lint
$(GOLANGCI_LINT): .github/workflows/golangci-lint.yml # Download golangci-lint using hack script into tools folder.
	hack/ensure-golangci-lint.sh \
		-b $(TOOLS_BIN_DIR) \
		$(shell cat .github/workflows/golangci-lint.yml | grep [[:space:]]version | sed 's/.*version: //')
# 构建仓库iso镜像 artifact
# build the artifact of repository iso
ISO_ARCH ?= amd64
ISO_OUTPUT_DIR ?= ./output
ISO_BUILD_WORKDIR := hack/gen-repository-iso
ISO_OS_NAMES := centos7 debian9 debian10 ubuntu1604 ubuntu1804 ubuntu2004 ubuntu2204
ISO_BUILD_NAMES := $(addprefix build-iso-,$(ISO_OS_NAMES))
build-iso-all: $(ISO_BUILD_NAMES)
.PHONY: $(ISO_BUILD_NAMES)
$(ISO_BUILD_NAMES):
	@export DOCKER_BUILDKIT=1
	docker build \
		--platform linux/$(ISO_ARCH) \
		--build-arg TARGETARCH=$(ISO_ARCH) \
		-o type=local,dest=$(ISO_OUTPUT_DIR) \
		-f $(ISO_BUILD_WORKDIR)/dockerfile.$(subst build-iso-,,$@) \
		$(ISO_BUILD_WORKDIR)
# 运行go-releaser测试发布流程
go-releaser-test:
	goreleaser release --rm-dist --skip-publish --snapshot
