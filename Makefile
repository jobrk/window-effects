CC = xcrun clang
CFLAGS = -Wall -Wextra -Werror -O2 -fobjc-arc -Isrc
FRAMEWORKS = -framework Cocoa

.PHONY: all clean test
all: build/window-effects build/payload.dylib build/loader

build:
	mkdir -p build

build/window-effects: src/main.m src/protocol.h | build
	$(CC) $(CFLAGS) $< $(FRAMEWORKS) -o $@

build/payload.dylib: src/payload.m src/protocol.h src/skylight.h | build
	$(CC) $(CFLAGS) -arch arm64e -dynamiclib $< $(FRAMEWORKS) -o $@

build/loader: src/loader.m | build
	$(CC) -Wall -Wextra -Werror -O2 -arch arm64e $< $(FRAMEWORKS) -o $@

build/test-payload.dylib: src/payload.m src/protocol.h src/skylight.h | build
	$(CC) $(CFLAGS) -DWE_TEST_HOST -dynamiclib $< $(FRAMEWORKS) -o $@

build/test-client: src/main.m src/protocol.h | build
	$(CC) $(CFLAGS) -DWE_TEST_HOST $< $(FRAMEWORKS) -o $@

test: all build/probe build/fixture build/test-payload.dylib build/test-client
	python3 tests/integration.py

build/probe: tests/probe.m src/skylight.h | build
	$(CC) $(CFLAGS) $< $(FRAMEWORKS) -o $@

build/fixture: tests/fixture.m src/skylight.h | build
	$(CC) $(CFLAGS) $< $(FRAMEWORKS) -o $@

clean:
	rm -rf build
