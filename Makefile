.PHONY: test lint install uninstall check

# Run the full test suite
test:
	bash tests/run_tests.sh

# Static validation only (fast)
lint:
	bash -n apm
	bash -n lib/shell/config.shlib
	bash -n lib/shell/locks.shlib
	bash -n lib/shell/ui.shlib
	bash -n lib/shell/fs.shlib
	python3 -m py_compile lib/py/apm_python.py
	@echo "lint: ok"

# Install apm to ~/.local/bin (or ~/bin)
install:
	bash install.sh

# Remove the installed symlink
uninstall:
	bash install.sh --uninstall

# Check dependencies without installing
check:
	bash install.sh --check
