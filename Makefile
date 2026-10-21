CLT := /Library/Developer/CommandLineTools
TESTFLAGS := -Xswiftc -F -Xswiftc $(CLT)/Library/Developer/Frameworks \
  -Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing \
  -Xlinker -F -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
BIN := $(shell swift build --show-bin-path)

.PHONY: build test coverage app cert dist install relaunch clean model eval

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

model: ; ./scripts/build-model.sh

# app'e bağlı: VERSION değişince eski paketin DMG'ye girmesini önler.
dist: app ; ./scripts/dist.sh

eval: ; @echo "LFW eşik kalibrasyonu (D14) Faz 4 hizalama hattı + veri seti gerektirir; bkz docs/model-evaluation.md"

clean: ; rm -rf .build build

install: app
	rm -rf "/Applications/Nöbetçi.app" && cp -R "build/Nöbetçi.app" /Applications/
	@echo "kuruldu: /Applications/Nöbetçi.app"

# Kurup yeniden başlatır. pkill -f yolu eşleştirmez (dosya adı NFD), ad ile öldür.
relaunch: install
	@pkill -x Nobetci 2>/dev/null || true
	@sleep 1 && open -a "/Applications/Nöbetçi.app" && sleep 1
	@echo "çalışıyor: pid=$$(pgrep -x Nobetci | head -1)"
