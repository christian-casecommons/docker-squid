# Project variables
export PROJECT_NAME ?= squid
export AWS_REGIONS ?= us-east-1
export ORG_NAME ?= casecommons
REPO_NAME ?= $(PROJECT_NAME)
DOCKER_REGISTRY ?= 334274607422.dkr.ecr.us-east-1.amazonaws.com
AWS_ACCOUNT_ID ?= 334274607422
ENV ?= nil

# Release settings
export SQUID_WHITELIST ?= *.acceptance.casebookplatform.org,*.okta.com
export NO_WHITELIST ?= false

# Common settings
-include .env/$(ENV)
include Makefile.settings

.PHONY: all orchestrate version release clean tag tag%default login logout publish compose
all:
	# do nothing
orchestrate: login release tag-default publish clean logout

# Prints version
version:
	@ echo $(APP_VERSION)

# Builds release image and runs acceptance tests
# Use 'make release :nopull' to disable default pull behaviour
release:
	${INFO} "Building images..."
	@ docker-compose $(RELEASE_ARGS) build $(NOPULL_FLAG)
	${INFO} "Build complete"
	${INFO} "Starting squid service..."
	@ docker-compose $(RELEASE_ARGS) up -d squid
	@ $(call check_service_health,$(RELEASE_ARGS),squid)
	${INFO} "Release environment created"
	${INFO} "Squid is running at http://$(DOCKER_HOST_IP):$(call get_port_mapping,$(RELEASE_ARGS),squid,3128)"

# Cleans environment
clean:
	${INFO} "Destroying release environment..."
	@ docker-compose $(RELEASE_ARGS) down -v || true
	${INFO} "Removing dangling images..."
	@ $(call clean_dangling_images,$(PROJECT_NAME))
	${INFO} "Clean complete"

# 'make tag <tag> [<tag>...]' tags development and/or release image with specified tag(s)
tag:
	${INFO} "Tagging release image with tags $(TAG_ARGS)..."
	@ $(foreach tag,$(TAGS),docker tag $(ORG_NAME)/$(REPO_NAME):latest $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME):$(tag);)
	${INFO} "Tagging complete"

# Tags with default set of tags
tag%default:
	@ make tag latest $(APP_VERSION) $(COMMIT_ID) $(COMMIT_TAG)

# Login to Docker registry
login:
	${INFO} "Logging in to Docker registry $$DOCKER_REGISTRY..."
	@ $(if $(AWS_ROLE),$(call assume_role,$(AWS_ROLE)),)
	@ $(DOCKER_LOGIN_EXPRESSION)
	${INFO} "Logged in to Docker registry $$DOCKER_REGISTRY"

# Logout of Docker registry
logout:
	${INFO} "Logging out of Docker registry $$DOCKER_REGISTRY..."
	@ docker logout
	${INFO} "Logged out of Docker registry $$DOCKER_REGISTRY"

# Publishes image(s) tagged using make tag commands
publish:
	${INFO} "Publishing release image to $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)..."
	@ docker push $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)
	${INFO} "Publish complete"

# Streams logs
logs:
	@ docker-compose $(RELEASE_ARGS) logs -f

# Executes docker-compose commands in release environment
#   e.g. 'make compose ps' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> ps
#   e.g. 'make compose run nginx' is the equivalent of docker-compose -f path/to/dockerfile -p <project-name> run nginx
#
# Use '--'' after make to pass flags/arguments
#   e.g. 'make -- compose run --rm nginx' ensures the '--rm' flag is passed to docker-compose and not interpreted by make
compose:
	${INFO} "Running docker-compose command in release environment..."
	@ docker-compose $(RELEASE_ARGS) $(ARGS)

# IMPORTANT - ensures arguments are not interpreted as make targets
%:
	@: