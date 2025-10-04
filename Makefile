###############################################################
############################ Variables ########################
###############################################################

SWIFTLINT_CMD=$(shell mise where swiftlint)/swiftlint
PROJECT_ROOT=$(shell pwd)
MAIN_PACKAGE_SCHEME ?= "StateMachine"
MAIN_LIBRARY_NAME ?= "StateMachine"
EXECUTOR_IMAGE ?= registry.gitlab.com/intech-consulting-app/shared/executor
EXECUTOR_VERSION ?= 0.10.2

HOSTING_BASE_PATH ?= ""
GITLAB_API_TOKEN ?= ""
GITLAB_PROJECT_ID ?= ""
GITLAB_API_URL ?= "https://gitlab.com"


###############################################################
######################### Defaults Cmd ########################
###############################################################

.DEFAULT_GOAL= help

help: ## Quick help
	@echo ""
	@echo "Usage:"
	@echo "    make $(OBJ_COLOR)<target>$(NO_COLOR)"
	@echo ""
	@echo "Target:"
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "    $(OBJ_COLOR)%-30s$(NO_COLOR) %s\n", $$1, $$2}'
	@echo ""

###############################################################
########################## Mise CLI ###########################
###############################################################

mise_install:
	mise install

mise_activate: mise_install
	mise activate -C $(ROOT_PROJECT) bash --shims

###############################################################
########################## Mint CLI ###########################
###############################################################

mint_install: mise_install
	  mise exec -- mint bootstrap

mint_bootstrap: mint_install

docker_login:
	docker login registry.gitlab.com -u $(GITLAB_USER) -p $(GITLAB_TOKEN)

###############################################################
######################### Run Linter ##########################
###############################################################

format: mint_bootstrap
	mise exec -- mint run executor format .

format_linux:
	docker run --rm --privileged --interactive --tty --volume "$(PROJECT_ROOT):/src" --workdir "/src" $(EXECUTOR_IMAGE):$(EXECUTOR_VERSION) executor format .

check_format: format
	# git diff --exit-code --name-only "*.swift"
	git diff --exit-code

check_documentation: mise_activate
	mise exec -- mint run executor documentation lint ./Sources  --swiftlint-bin $(SWIFTLINT_CMD)

###############################################################
########################## Run tests ##########################
###############################################################

build: mint_bootstrap
	swift build

build_linux:
	docker run --rm --privileged --interactive --tty --volume "$(PROJECT_ROOT):/src" --workdir "/src" swift:latest swift build

###############################################################
########################## Run tests ##########################
###############################################################

test: mint_bootstrap ## Run test with fastlane
	mise exec -- mint run executor swift test  --enable-code-coverage
	mise exec -- mint run executor test report --report-for-type swift ./
	mise exec -- mint run executor coverage swift --verbose

test_linux:
	swift test

test_docker:
	docker run --rm --privileged --interactive --tty --volume "$(PROJECT_ROOT):/src" --workdir "/src" swift:latest swift test


###############################################################
######################## Documentation ########################
###############################################################

start_documentation_server:
	python3 -m http.server -d public

build_documentation: mint_bootstrap
	mise exec -- mint run executor xcodebuild docc --scheme "$(MAIN_PACKAGE_SCHEME)" --platform macOS --verbose --hosting-base-path "$(HOSTING_BASE_PATH)" --filter-scheme "$(MAIN_LIBRARY_NAME)"

###############################################################
###################### Run Gitlab-CLI #########################
###############################################################

labels_create: mint_bootstrap ## Create or update labels on gitlab.com
	mise exec -- mint run gitlab-cli labels create\
	    --project-id $(GITLAB_PROJECT_ID)\
		--api-url $(GITLAB_API_URL)\
		--access-token $(GITLAB_API_TOKEN)\
	    --force
