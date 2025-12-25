CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -O2 -g
LDFLAGS = -lyaml -lm

SRCDIR = src
INCDIR = include
OBJDIR = obj
BINDIR = bin

# Only include the core files we need
CORE_SOURCES = src/main.c src/yaml_parser.c src/fpga_converter.c src/flow_table.c src/unified_routing.c
CORE_OBJECTS = $(CORE_SOURCES:src/%.c=$(OBJDIR)/%.o)
TARGET = $(BINDIR)/yaml2fpga

.PHONY: all clean deps test

all: $(TARGET)

$(TARGET): $(CORE_OBJECTS) | $(BINDIR)
	$(CC) $(CORE_OBJECTS) -o $@ $(LDFLAGS)

$(OBJDIR)/%.o: src/%.c | $(OBJDIR)
	$(CC) $(CFLAGS) -I$(INCDIR) -c $< -o $@

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(BINDIR):
	mkdir -p $(BINDIR)

deps:
	@echo "Installing dependencies..."
	sudo apt-get update
	sudo apt-get install -y libyaml-dev

clean:
	rm -rf $(OBJDIR) $(BINDIR)

install: $(TARGET)
	sudo cp $(TARGET) /usr/local/bin/

test: $(TARGET)
	./$(TARGET) topology-tree.yaml

help:
	@echo "Available targets:"
	@echo "  all     - Build the project"
	@echo "  deps    - Install dependencies"
	@echo "  clean   - Remove build artifacts"
	@echo "  install - Install to system"
	@echo "  test    - Build and run with default config"
	@echo "  help    - Show this help"