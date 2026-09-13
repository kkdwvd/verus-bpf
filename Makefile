SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
include toolchain.mk

# --- Verus ---
# Built out of the pinned submodule with vstd in no_std/no_alloc mode, so it
# can be linked against a #![no_std] crate that owns its own panic handler.
VERUS_SOURCE := $(VERUS_DIR)/source
VERUS_TARGET := $(VERUS_SOURCE)/target-verus/release
VERUS_BIN := $(VERUS_TARGET)/verus
VERUS_Z3 := $(VERUS_SOURCE)/z3
VERUS_Z3_VERSION ?= 4.16.0
# Upstream's get-z3.sh fetches a build linked against glibc 2.39; RHEL 9 has
# 2.34. The z3-solver wheel for the same release is a manylinux_2_27 build of
# the same version, so fall back to it when the release binary will not run.
VERUS_Z3_WHEEL ?= https://github.com/Z3Prover/z3/releases/download/z3-$(VERUS_Z3_VERSION)/z3_solver-$(VERUS_Z3_VERSION).0-py3-none-manylinux_2_27_x86_64.whl

.PHONY: help verus verus-clean rust-toolchain check
help:
	@printf '%s\n' 'Targets: rust-toolchain verus verus-clean check' \
		'Include rules.mk from a consumer; see TOOLCHAIN.md.' \
		'Rust: $(RUST_TOOLCHAIN)' 'Verus: $(VERUS_DIR)'

rust-toolchain:
	@installed=$$(rustup component list --toolchain "$(RUST_TOOLCHAIN)" --installed 2>/dev/null || true); \
		missing=0; \
		for component in rust-src rustc-dev llvm-tools rustfmt; do \
			grep -qE "^$$component(-|$$)" <<< "$$installed" || missing=1; \
		done; \
		if ((missing)) || [[ ! -x "$(RUSTC)" || ! -f "$(RUST_SRC)/core/src/lib.rs" ]]; then \
			rustup toolchain install "$(RUST_TOOLCHAIN)" --profile minimal \
				--component rust-src,rustc-dev,llvm-tools,rustfmt; \
		fi

# Build a pinned distribution once. Re-running vargo replaces rust_verify,
# which can break another verifier process when it re-execs itself for trait
# checking. Serialize setup and leave a current distribution untouched.
verus: rust-toolchain $(VERUS_Z3)
	@mkdir -p $(VERUS_SOURCE)/target-verus
	@{ flock -x 9; \
		key=$$({ git -C $(VERUS_DIR) rev-parse HEAD; \
			git -C $(VERUS_DIR) diff HEAD -- source dependencies tools rust-toolchain.toml; \
			sha256sum $(VERUS_BPF_DIR)/Makefile $(VERUS_BPF_DIR)/toolchain.mk; \
			printf '%s\n' '$(RUST_TOOLCHAIN)' 'no-std no-alloc'; \
			} | sha256sum); \
		stamp=$(VERUS_SOURCE)/target-verus/.verus-bpf-build; \
		if [[ -x $(VERUS_BIN) && -f $(VERUS_TARGET)/vstd.vir && \
			-f $$stamp && $$(cat $$stamp) == "$$key" ]]; then \
			echo 'Verus distribution is current'; \
		else \
			cd $(VERUS_SOURCE); \
			source ../tools/activate; \
			RUSTC_BOOTSTRAP=1 vargo build --release --vstd-no-std --vstd-no-alloc; \
			printf '%s\n' "$$key" > "$$stamp"; \
		fi; \
	} 9>$(VERUS_SOURCE)/target-verus/.verus-bpf-lock

$(VERUS_Z3):
	cd $(VERUS_SOURCE) && ./tools/get-z3.sh
	@if ! $(VERUS_Z3) --version >/dev/null 2>&1; then \
		echo "z3 from upstream's release does not run here; using the manylinux wheel"; \
		tmp=$$(mktemp -d); \
		curl -sL -o "$$tmp/z3.whl" '$(VERUS_Z3_WHEEL)'; \
		$(PYTHON) -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract(sys.argv[2], sys.argv[3])" \
			"$$tmp/z3.whl" 'z3_solver-$(VERUS_Z3_VERSION).0.data/data/bin/z3' "$$tmp"; \
		install -m 0755 "$$tmp/z3_solver-$(VERUS_Z3_VERSION).0.data/data/bin/z3" $(VERUS_Z3); \
		rm -rf "$$tmp"; \
	fi
	@rm -rf $(VERUS_SOURCE)/z3-$(VERUS_Z3_VERSION)-*
	$(VERUS_Z3) --version

verus-clean:
	rm -rf $(VERUS_SOURCE)/target $(VERUS_SOURCE)/target-verus \
		$(VERUS_DIR)/tools/vargo/target


check:
	python3 -m unittest discover -s tests -v
