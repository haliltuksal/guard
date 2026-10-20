CLT := /Library/Developer/CommandLineTools
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
  -Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing \
  -Xlinker -F -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
BIN := $(shell swift build --show-bin-path)

.PHONY: build test coverage app cert dist install clean model eval

build: ; swift build

test: ; swift test $(TESTFLAGS)

coverage:
	swift test --enable-code-coverage $(TESTFLAGS)
	@mkdir -p build
	xcrun llvm-cov report "$(BIN)/NobetciPackageTests.xctest/Contents/MacOS/NobetciPackageTests" \
	  -instr-profile="$(BIN)/codecov/default.profdata" \
	  -ignore-filename-regex='(\.build|Tests|Sources/Nobetci/|Sources/nobetci-eval)/' | tee build/coverage.txt
	python3 -I scripts/coverage_gate.py build/coverage.txt NobetciCore 90

app: ; ./scripts/bundle.sh && ./scripts/sign.sh

cert: ; ./scripts/make-cert.sh

clean: ; rm -rf .build build
