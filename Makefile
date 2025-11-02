# Variables
SHELL := /bin/bash
MAIN_SCRIPT := main.sh
CONFIGURED_FLAG := .configured

# Default target
all: check run

# Check if the configuration has been set up
check:
	@if [ ! -f $(CONFIGURED_FLAG) ]; then \
		echo "No configuration found. Running setup..."; \
		$(SHELL) $(MAIN_SCRIPT) --setup; \
		touch $(CONFIGURED_FLAG); \
	else \
		echo "Configuration already exists."; \
	fi

# Run the main script
run:
	@echo "Executing main script..."
	$(SHELL) $(MAIN_SCRIPT)

# Clean the configuration
clean:
	@echo "Cleaning configuration..."
	rm -f $(CONFIGURED_FLAG)

# Help message
help:
	@echo "Usage:"
	@echo "  make            - Check and run the main script"
	@echo "  make check      - Run setup if not configured"
	@echo "  make run        - Execute the main script"
	@echo "  make clean      - Remove configuration"
	@echo "  make help       - Show this help message"

.PHONY: all check run clean help
