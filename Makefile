DOCKER    = docker

BASE_REPO = cloudflare/quiche
BASE_TAG  = latest

QNS_REPO  = cloudflare/quiche-qns
QNS_TAG   = latest

FUZZ_REPO = cloudflare.mayhem.security:5000/protocols/quiche-libfuzzer
FUZZ_TAG  = latest

INSTALL_INC_DIR := /usr/local/include/quiche-boringssl
INSTALL_LIB_DIR := /usr/lib
QUICHE_SRC      := ./

docker-build: docker-base docker-qns

# build quiche-apps only
.PHONY: build-apps
build-apps:
	cargo build --package=quiche_apps

# build base image
.PHONY: docker-base
docker-base: Dockerfile
	$(DOCKER) build --target quiche-base -t $(BASE_REPO):$(BASE_TAG) .

# build qns image
.PHONY: docker-qns
docker-qns: Dockerfile apps/run_endpoint.sh
	$(DOCKER) build --target quiche-qns -t $(QNS_REPO):$(QNS_TAG) .

.PHONY: docker-publish
docker-publish:
	$(DOCKER) push $(BASE_REPO):$(BASE_TAG)
	$(DOCKER) push $(QNS_REPO):$(QNS_TAG)

# build fuzzers
.PHONY: build-fuzz
build-fuzz:
	cargo +nightly fuzz build --release --debug-assertions packet_recv_client
	cargo +nightly fuzz build --release --debug-assertions packet_recv_server
	cargo +nightly fuzz build --release --debug-assertions packets_recv_server
	cargo +nightly fuzz build --release --debug-assertions packets_posths_server
	cargo +nightly fuzz build --release --debug-assertions qpack_decode

# build fuzzing image
.PHONY: docker-fuzz
docker-fuzz:
	$(DOCKER) build -f fuzz/Dockerfile --target quiche-libfuzzer --tag $(FUZZ_REPO):$(FUZZ_TAG) .

.PHONY: docker-fuzz-publish
docker-fuzz-publish:
	$(DOCKER) push $(FUZZ_REPO):$(FUZZ_TAG)

.PHONY: clean
clean:
	@for id in `$(DOCKER) images -q $(BASE_REPO)` `$(DOCKER) images -q $(QNS_REPO)` `$(DOCKER) images -q $(FUZZ_REPO)`; do \
		echo ">> Removing $$id"; \
		$(DOCKER) rmi -f $$id; \
	done

.PHONY: install-deps
install-deps:
	@echo "Copying Quiche and BoringSSL components to system directories and quiche-boringssl..."
	@sudo mkdir -p $(INSTALL_LIB_DIR)
	@sudo mkdir -p /usr/local/include
	@sudo mkdir -p $(INSTALL_INC_DIR)/boringssl/src/include
	@sudo mkdir -p $(INSTALL_INC_DIR)/build
	@LIBQUICHE_SO=$$(find $(QUICHE_SRC) -type f -name "libquiche.so" 2>/dev/null | head -n 1); \
	if [ -n "$$LIBQUICHE_SO" ]; then \
		echo "libquiche.so found: $$LIBQUICHE_SO"; \
		sudo cp $$LIBQUICHE_SO $(INSTALL_LIB_DIR)/; \
	else \
		echo "Error: libquiche.so not found under $(QUICHE_SRC). Make sure 'cdylib' is in crate-type!"; \
		exit 1; \
	fi
	@LIBQUICHE_A=$$(find $(QUICHE_SRC) -type f -name "libquiche.a" 2>/dev/null | head -n 1); \
	if [ -n "$$LIBQUICHE_A" ]; then \
		echo "libquiche.a found: $$LIBQUICHE_A"; \
		sudo cp $$LIBQUICHE_A $(INSTALL_LIB_DIR)/; \
	else \
		echo "Error: libquiche.a not found under $(QUICHE_SRC)."; \
		exit 1; \
	fi
	@QUICHE_H=$$(find $(QUICHE_SRC) -maxdepth 4 -type f -name "quiche.h" -path "*/include/*" 2>/dev/null | head -n 1); \
	if [ -n "$$QUICHE_H" ]; then \
		echo "quiche.h found: $$QUICHE_H"; \
		sudo cp $$QUICHE_H /usr/local/include/; \
	else \
		echo "Error: quiche.h not found under $(QUICHE_SRC)."; \
		exit 1; \
	fi
	@BORINGSSL_INC=$$(find $(QUICHE_SRC)/target/release/build -maxdepth 5 -type d -path "*/out/boringssl/src/include" 2>/dev/null | head -n 1); \
	if [ -n "$$BORINGSSL_INC" ]; then \
		echo "BoringSSL include files found: $$BORINGSSL_INC"; \
		sudo cp -r $$BORINGSSL_INC/* $(INSTALL_INC_DIR)/boringssl/src/include/; \
	else \
		echo "Warning: BoringSSL out directory not generated yet! Falling back to submodule sources."; \
		sudo cp -r $(QUICHE_SRC)/deps/boringssl/src/include/* $(INSTALL_INC_DIR)/boringssl/src/include/ 2>/dev/null || true; \
	fi
	@LIBSSL=$$(find $(QUICHE_SRC)/target/release/build -maxdepth 8 -type f -name "libssl.a" 2>/dev/null | head -n 1); \
	LIBCRYPTO=$$(find $(QUICHE_SRC)/target/release/build -maxdepth 8 -type f -name "libcrypto.a" 2>/dev/null | head -n 1); \
	if [ -n "$$LIBSSL" ] && [ -n "$$LIBCRYPTO" ]; then \
		echo "libssl.a found: $$LIBSSL"; \
		echo "libcrypto.a found: $$LIBCRYPTO"; \
		sudo cp $$LIBSSL $(INSTALL_INC_DIR)/build/; \
		sudo cp $$LIBCRYPTO $(INSTALL_INC_DIR)/build/; \
	else \
		echo "Error: libssl.a / libcrypto.a not found under $(QUICHE_SRC)/target/release/build."; \
		exit 1; \
	fi
	@sudo ldconfig
	@echo "Setup completed successfully!"