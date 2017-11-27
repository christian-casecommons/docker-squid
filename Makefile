# Project variables
export PROJECT_NAME ?= squid
export AWS_REGIONS ?= us-east-1

ORG_NAME ?= cwds
REPO_NAME ?= squid
DOCKER_REGISTRY ?= 429614120872.dkr.ecr.us-west-2.amazonaws.com
AWS_ACCOUNT_ID ?= 429614120872
DOCKER_LOGIN_EXPRESSION ?= $$(aws ecr get-login --registry-ids $(AWS_ACCOUNT_ID))

# Release settings
export SQUID_WHITELIST ?=
export NO_WHITELIST ?= false

# Common settings
include Makefile.settings

.PHONY: version release clean tag tag%default login logout publish compose all

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

# Executes a full workflow
all: clean release tag-default login publish clean

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
	@ $(foreach tag,$(TAG_ARGS), echo $(call get_image_id,$(RELEASE_ARGS),squid) | xargs -I ARG docker tag ARG $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME):$(tag);)
	${INFO} "Tagging complete"

# Tags with default set of tags
tag%default:
	@ make tag latest $(APP_VERSION) $(COMMIT_ID) $(COMMIT_TAG)

# Login to Docker registry
login:
	${INFO} "Logging in to Docker registry $$DOCKER_REGISTRY..."
	@ eval $(DOCKER_LOGIN_EXPRESSION)
	${INFO} "Logged in to Docker registry $$DOCKER_REGISTRY"

# Logout of Docker registry
logout:
	${INFO} "Logging out of Docker registry $$DOCKER_REGISTRY..."
	@ docker logout
	${INFO} "Logged out of Docker registry $$DOCKER_REGISTRY"

# Publishes image(s) tagged using make tag commands
publish:
	${INFO} "Publishing release image to $(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)..."
	@ for tag in $(call get_repo_tags,$(RELEASE_ARGS),squid,$(DOCKER_REGISTRY)/$(ORG_NAME)/$(REPO_NAME)); do echo $$tag | xargs -I TAG docker push TAG; done
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