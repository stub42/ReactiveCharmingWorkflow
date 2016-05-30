
CHARM_NAME := example

LAYER_BRANCH := master
DEVEL_BRANCH := test-built
STABLE_BRANCH := built

BUILD_DIR := $(JUJU_REPOSITORY)/$(CHARM_NAME)
CHARM_STORE_URL := $(CHARM_NAME)

SHELL := /bin/bash
export SHELLOPTS := errexit:pipefail


# Create the test-build worktree if it doesn't already exist.
$(BUILD_DIR):
	-git branch $(DEVEL_BRANCH) $(LAYER_BRANCH)
	git worktree add $@ $(DEVEL_BRANCH)


# A quick test build, not to be committed or released. Builds
# from the working tree including all untracked and uncommitted
# updates.
.PHONY: build
build: | $(BUILD_DIR)
	charm build -f -o $(JUJU_REPOSITORY) -n $(CHARM_NAME)


# A generate a fresh development build. Builds committed work only.
.PHONY: dev-build
build-dev: | $(BUILD_DIR)
	-cd $(BUILD_DIR) && git merge --abort
	cd $(BUILD_DIR) \
	    && git reset --hard $(TEST_BRANCH) \
	    && git clean -ffd \
	    && git merge --log --no-commit -s ours $(LAYER_BRANCH)
	charm build -f -o $(JUJU_REPOSITORY) -n $(CHARM_NAME)
	cd $(BUILD_DIR) \
	    && git add . \
	    && git commit -m "charm-build of $(LAYER_BRANCH)"


# Generate and publish a fresh development build.
publish-dev: build-dev
	cd $(BUILD_DIR) && charm publish -c development \
		`charm push . $(CHARM_STORE_URL) 2>&1 \
		 | tee /dev/tty | grep url: | cut -f 2 -d ' '` 

# Publish the latest development build as the stable release.
.PHONY: publish-stable
publish-stable:
	-git branch $(STABLE_BRANCH) $(DEVEL_BRANCH)
	rm -rf .tmp-repo
	git clone --no-single-branch -b $(STABLE_BRANCH) . .tmp-repo
	cd .tmp-repo \
	    && git merge --no-ff origin/$(DEVEL_BRANCH) --log \
		-m "charm-build of $(LAYER_BRANCH)" \
	    && export rev=`charm push . $(CHARM_NAME) 2>&1 \
		| tee /dev/tty | grep url: | cut -f 2 -d ' '` \
	    && git tag `echo $$rev | tr -s '~:/' -` \
	    && git push --tags .. $(STABLE_BRANCH) \
	    && git publish -c stable $$rev
	rm -rf .tmp-repo
