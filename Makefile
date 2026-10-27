CC = xcrun clang
CFLAGS = -Wall -Wextra -Werror -O2 -fobjc-arc -Isrc
FRAMEWORKS = -framework Cocoa

.PHONY: all clean test test-arm64e format
all: build/window-effects build/payload.dylib build/loader

build:
	mkdir -p build

build/window-effects: src/main.m src/protocol.h Makefile | build
	$(CC) $(CFLAGS) $< $(FRAMEWORKS) -o $@

build/payload.dylib: src/payload.m src/protocol.h src/skylight.h Makefile | build
	$(CC) $(CFLAGS) -arch arm64e -dynamiclib $< $(FRAMEWORKS) -o $@
	codesign --force --sign - $@

build/loader: src/loader.m Makefile | build
	$(CC) -Wall -Wextra -Werror -O2 -arch arm64e $< $(FRAMEWORKS) -o $@
	codesign --force --sign - $@

build/test-payload.dylib: src/payload.m src/protocol.h src/skylight.h | build
	$(CC) $(CFLAGS) -DWE_TEST_HOST -dynamiclib $< $(FRAMEWORKS) -o $@

build/test-client: src/main.m src/protocol.h | build
	$(CC) $(CFLAGS) -DWE_TEST_HOST $< $(FRAMEWORKS) -o $@

test: all build/fixture build/test-payload.dylib build/test-client
	python3 tests/integration.py

# Requires arm64e user binaries to be enabled on this Mac, as Dock injection does.
build/fixture-arm64e: tests/fixture.m src/skylight.h | build
	$(CC) $(CFLAGS) -arch arm64e $< $(FRAMEWORKS) -o $@

build/test-payload-arm64e.dylib: src/payload.m src/protocol.h src/skylight.h | build
	$(CC) $(CFLAGS) -arch arm64e -DWE_TEST_HOST -dynamiclib $< $(FRAMEWORKS) -o $@

test-arm64e: test build/fixture-arm64e build/test-payload-arm64e.dylib
	WE_TEST_ARCH=arm64e python3 tests/integration.py

build/fixture: tests/fixture.m src/skylight.h | build
	$(CC) $(CFLAGS) $< $(FRAMEWORKS) -o $@

format:
	xcrun clang-format -i src/*.m src/*.h tests/*.m

clean:
	rm -rf build
