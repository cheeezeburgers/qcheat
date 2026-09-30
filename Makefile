.PHONY: install uninstall tag push-tag release

install:
	./install.sh

uninstall:
	bash dev/uninstall.sh

# Commit the current version first, then tag, push-tag and release in order.
tag:
	bash dev/release.sh tag

push-tag:
	bash dev/release.sh push-tag

release:
	bash dev/release.sh release
