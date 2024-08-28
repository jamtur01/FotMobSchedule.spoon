# Variables to track current version and short git SHA
OBJ_VERSION=$(shell grep -Eo 'obj.version\s*=\s*"[^"]+"' init.lua | cut -d'"' -f2)
SHORT_GIT_SHA=$(shell git rev-parse --short HEAD)
TAG_FILE=.tag

# Ensure auto-changelog is installed
install_auto_changelog:
	@if ! command -v auto-changelog &> /dev/null; then \
		echo "auto-changelog not found. Installing..."; \
		npm install -g auto-changelog; \
	fi

# Increment the version in init.lua
increment_version:
	@echo "Current version: $(OBJ_VERSION)"
	@new_version=$$(echo $(OBJ_VERSION) | awk -F. '{$$NF = $$NF + 1;} 1' | sed 's/ /./g'); \
	echo "Incrementing version to: $$new_version"; \
	sed -i.bak "s/obj.version = \"$(OBJ_VERSION)\"/obj.version = \"$$new_version\"/" init.lua; \
	rm -f init.lua.bak; \
	echo "Version incremented to $$new_version"; \
	echo "$$new_version" > $(TAG_FILE)

# Commit the version change
commit_version_change:
	@git add init.lua
	@git commit -m "Bump version to v$$(cat $(TAG_FILE))"

# Generate a changelog using auto-changelog
changelog:
	@echo "Generating CHANGELOG.md"
	@new_version=$$(cat $(TAG_FILE)); \
	auto-changelog --output CHANGELOG.md --latest-version v$$new_version --unreleased --tag-prefix v
	@echo "CHANGELOG.md generated."
	@git add CHANGELOG.md
	@git commit -m "Update CHANGELOG.md for v$$(cat $(TAG_FILE))"

# Create a new tag based on the incremented version
create_tag:
	@new_version=$$(cat $(TAG_FILE)); \
	git tag -a "v$$new_version" -m "Release v$$new_version"; \
	echo "Tag created: v$$new_version"

# Push the code and tag
push_changes:
	@git push origin main
	@git push origin --tags
	@echo "Code and tag pushed to GitHub: v$$(cat $(TAG_FILE))"

# Release target
release: install_auto_changelog increment_version commit_version_change changelog create_tag push_changes clean

# Clean up the temporary tag file
clean:
	@rm -f $(TAG_FILE)