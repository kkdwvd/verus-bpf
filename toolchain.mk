# SPDX-License-Identifier: GPL-2.0
# Shared compiler selection; the nested Verus pin owns the Rust version.
ifndef VERUS_BPF_TOOLCHAIN_INCLUDED
VERUS_BPF_TOOLCHAIN_INCLUDED := 1
VERUS_BPF_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VERUS_DIR ?= $(VERUS_BPF_DIR)/dep/verus
# --- toolchain -------------------------------------------------------------
# The toolchain is Verus's pin (dep/verus/rust-toolchain.toml): one rustc
# serves the verification pass, the proc macros, libcore and the BPF compile.
# Its LLVM must not be newer than the LLVM tools below -- bitcode reads
# forward only. See TOOLCHAIN.md for the toolchain matrix.
RUSTUP_HOME ?= $(HOME)/.rustup
RUST_HOST ?= x86_64-unknown-linux-gnu
RUST_CHANNEL := $(shell sed -n 's/^channel = "\(.*\)"/\1/p' $(VERUS_DIR)/rust-toolchain.toml)
RUST_TOOLCHAIN ?= $(RUST_CHANNEL)-$(RUST_HOST)
RUSTC ?= $(RUSTUP_HOME)/toolchains/$(RUST_TOOLCHAIN)/bin/rustc
RUST_SRC ?= $(RUSTUP_HOME)/toolchains/$(RUST_TOOLCHAIN)/lib/rustlib/src/rust/library
# Same toolchain's cargo, so the host proc-macro .so matches the rustc that
# will dlopen it.
CARGO ?= $(RUSTUP_HOME)/toolchains/$(RUST_TOOLCHAIN)/bin/cargo
# The toolchain root RUSTC/RUST_SRC/CARGO are rooted under. rust-project.json
# names it so that rust-analyzer, normally a stable build on PATH, expands
# proc macros with *this* toolchain's own
# <sysroot>/libexec/rust-analyzer-proc-macro-srv instead: a proc-macro
# dylib has to be loaded by a server built by the same compiler that built
# it. See the `rust-project` target below.
RA_SYSROOT ?= $(RUSTUP_HOME)/toolchains/$(RUST_TOOLCHAIN)

LLVM_PREFIX ?= /usr/lib/llvm-22
LLC ?= $(LLVM_PREFIX)/bin/llc
OPT ?= $(LLVM_PREFIX)/bin/opt
LLVM_LINK ?= $(LLVM_PREFIX)/bin/llvm-link
LLVM_AS ?= $(LLVM_PREFIX)/bin/llvm-as
LLVM_DIS ?= $(LLVM_PREFIX)/bin/llvm-dis
LLVM_OBJCOPY ?= $(LLVM_PREFIX)/bin/llvm-objcopy
# llvm-sys finds LLVM through llvm-config on PATH.
LLVM_CONFIG_DIR ?= $(LLVM_PREFIX)/bin

# bpf-postproc links llvm-sys. Static linking against llvm-static pulls
# std::__glibcxx_assert_fail, which RHEL 9's base libstdc++ lacks; the shared
# libLLVM has it resolved internally, so link dynamically. Passed on the
# cargo command line so that the imported Cargo.toml stays untouched.
POSTPROC_FEATURES ?= llvm-sys-22/prefer-dynamic

PYTHON ?= python3
# /usr/local/bin/bpftool is a wrapper script on some hosts; add_ksyms.py
# execs the path directly, so default to the real binary.
BPFTOOL ?= /usr/sbin/bpftool

# --- Verus -----------------------------------------------------------------
# Built by `make verus` at the repository root. VERUS_DIR can point at an
# external checkout instead of the submodule.
VERUS_TARGET ?= $(VERUS_DIR)/source/target-verus/release
VERUS ?= $(VERUS_TARGET)/verus
VERUS_MACROS_SO ?= $(VERUS_TARGET)/libverus_builtin_macros.so
# Set VERIFY=0 to skip verification when debugging the compile pipeline.
VERIFY ?= 1

endif
