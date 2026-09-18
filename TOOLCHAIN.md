# Verus-to-BPF toolchain

`rules.mk` verifies Rust source with Verus, then compiles the same source to
BPF with ghost code erased. It also supports a verified userspace logic
crate and an ordinary Cargo loader. Programs, kernel APIs, policies, and
loading belong to the consumer.

## Setup

Clone with `git clone --recurse-submodules`, or run
`git submodule update --init --recursive` in an existing checkout. All
submodules retain full history. `dep/verus` pins upstream Verus. Its
`rust-toolchain.toml` is the source of the Rust version used for verification,
proc macros, libcore, BPF compilation, and the userspace binary.

`make verus` installs missing Rust prerequisites through rustup and builds
Verus with `--vstd-no-std --vstd-no-alloc`. It rebuilds incrementally after the pin, tracked Verus sources, or setup
configuration changes; an unchanged distribution is left untouched. Setup
is serialized so parallel consumers do not overwrite the verifier binary. Build products in the
Verus checkout are ignored by upstream. `make verus-clean` removes them.

The tested host is x86-64 Linux. Install LLVM 22 tools and development
libraries (Ubuntu: `llvm-22 llvm-22-dev`), Python 3, bpftool, and the kernel
build dependencies separately. The optional libbpf-rs consumer needs libelf
and zlib headers. LLVM_PREFIX defaults to `/usr/lib/llvm-22`; override it
for another installation. `bpf-postproc` uses llvm-sys 221 and dynamic LLVM
linking. LLVM tools must understand the bitcode produced by the pinned
rustc. LLVM 21 cannot read Rust 1.98.x's LLVM 22 bitcode.

The Verus build fetches Z3 using the pinned checkout's script. For older
x86-64 Linux hosts that cannot run that binary, it retains the equivalent
Z3 4.16.0 manylinux-wheel fallback inherited from Lachesis.

## Consumer interface

A program Makefile supplies its project root, source, exported symbols,
and ordered library crates, then includes `rules.mk`:

```make
ROOT_DIR := $(abspath ../..)
PROG := example
SRC := bpf/main.rs
KEEP_SYMS := example_entry _LICENSE
LIB_CRATES := runtime_trusted runtime
runtime_trusted_DIR := $(ROOT_DIR)/src/runtime/trusted
runtime_DIR := $(ROOT_DIR)/src/runtime
NOCHEAT_CRATES := runtime
TRUSTED_DIRS := $(runtime_trusted_DIR)
include ../../dep/verus-bpf/rules.mk
```

`ROOT_DIR` defaults to the program directory. `SRC`, `USER_MANIFEST`, and
`USER_CORE_SRC` are relative to the program directory; crate directories
and trust-boundary directories should be absolute. Each library imports
all preceding libraries. The program imports all libraries.

`LIB_CRATES` defaults to empty. `NOCHEAT_CRATES` defaults to all libraries
and the program. Verus checks `--no-cheating` over the imported crate graph:
a consumer calling trusted external bodies must explicitly choose where
that flag applies, while keeping the source lint enabled everywhere.

`LINT_SRC` defaults to `$(ROOT_DIR)/src`. `TRUSTED_DIRS` is empty by default;
only the explicit directories may contain unsafe code or proof escapes.
`UNVERIFIED_DIRS` permits unsafe but still rejects proof escapes; it defaults
to the directory containing `USER_MANIFEST`. Missing lint roots are errors.
`trusted-lines` reports Rust source sizes for these directories.

To build a userspace binary named `PROG`, set `USER_MANIFEST`. To verify its
separate logic crate, also set `USER_CORE_SRC` and `USER_CORE_NAME`. That
crate is always verified with `--no-cheating` and imports no BPF libraries.
Cargo dependencies on Verus macros can use
`dep/verus-bpf/dep/verus/source/builtin_macros` relative to the consumer.

`MUTANTS` lists unified diffs against `SRC`, relative to the program
directory: variants of the program that its contracts must reject. `verify`
applies each to a copy of `SRC`, runs the program's own verification pass on
it, and fails unless Verus reports at least one verification error; a mutant
that fails to compile is an error too, since it says nothing about the
contracts. Leading lines before the first hunk are ignored by `patch`, so a
patch can open with a comment saying what it breaks. `verify-mutants` runs
only those.

Supply `VMLINUX`, or `KERNEL_DIR` and `KERNEL_BUILD`, for the target kernel.
The object's kfunc BTF prototypes are copied from that kernel's BTF. Use the
same kernel to run it. No kernel is downloaded or built by this repository.

Targets: `all`, `verify`, `verify-mutants`, `lint-trusted`, `trusted-lines`,
`rust-project`, `clean`, `distclean`, and `help`. `make help` in a consumer prints resolved
variables. `BUILD_DIR` defaults to `$(ROOT_DIR)/build`; `DEPDIR` and `HOSTDIR`
select cached BPF libraries and host artifacts. A toolchain/configuration stamp invalidates cached artifacts when the Rust
compiler, Verus pin, selected tools, or consumer configuration changes.
`clean` removes the program's outputs; `distclean` also removes those caches. `VERIFY=0` is for compilation
debugging only and prints a warning; never load an object built that way.

## Pipeline and trust

Verus verifies the host-target source and exports `.vir` proofs plus host
metadata for dependent crates. Plain rustc compiles it for BPF with the
`verus!` macro erasing specs, proofs, and ghost arguments. The BPF program
and libraries use libcore and a stub compiler_builtins, with no allocator.
Verification and erased compilation remain separate passes: successful
Verus verification does not imply acceptance by the kernel BPF verifier.

LLVM links the bitcode and `multi3.ll`; `bpf-postproc` lowers BTF field
polyfills to CO-RE intrinsics. Optimization internalizes everything except
`KEEP_SYMS`. `add_ksyms.py` mirrors kfunc prototypes from the kernel and
lowers unsupported control flow. `btf_fixup.py` repairs DWARF descriptions
before llc emits the object and BTF, with jump tables turned off: LLVM 22
lowers a dense `switch` to a `gotox` table in a `.jumptables` section, which
the verifier of current kernels rejects. These transformations are trusted.

Two things a consumer may put in a library crate that the pipeline passes
through untouched: a BTF-defined map, a static in a `.maps` section whose
struct type spells the map parameters as pointers to arrays, named in
`KEEP_SYMS`; and BPF helper calls, made through a function pointer built
from the helper number, which the backend lowers to `call N`. Neither is a
kfunc, so `add_ksyms.py` does not see them; libbpf creates the map from the
BTF and the verifier checks the helper by number.

The optional loader is built by Cargo using the same rustc, with ghost
code erased. It is not verified; only its explicitly supplied logic crate
is. Runtime tests and scheduler attachment are the consumer's responsibility.

## Editor support

`make rust-project` writes `RUST_PROJECT_JSON`, defaulting to
`$(ROOT_DIR)/rust-project.json`, from the same library list used to build.
It points rust-analyzer at the pinned compiler's proc-macro server and an
erase-only Verus macro build. That avoids the Verus macro's `expand_expr`
bridge call, which rust-analyzer does not implement. The erase-only build
is for the editor; real compilation uses Verus's normal macro artifact.
Both Cargo output directories and rustc are explicitly selected for this
build so the Verus workspace cannot mix its own intermediate artifacts into it.
Consumers with a Cargo loader can name both projects in rust-analyzer.toml.

## Provenance and licensing

Extracted from `kkdwvd/lachesis` at `91af38a6b1ff`, including the local LLVM
22 path fix, on 2026-09-13. The original pipeline was imported from
<https://github.com/4ast/rust-bpf>, commit `2570069dd7fa`, on 2026-09-06.
The following remain byte-for-byte imports from that revision:

- `bpfel-unknown-none-v4.json` and `multi3.ll`;
- `add_ksyms.py`;
- `btf/`, `btf-macros/`, and `bpf-postproc/`, including their lockfiles.

`rules.mk`, `btf_fixup.py`, and `gen_rust_project.py` originated in Lachesis.
Toolchain setup and lint were separated and generalized during extraction.
The import is GPL-2.0, consistent with upstream's SPDX-marked files; see
LICENSE. The nested Verus checkout retains its own licensing.

## Validation

`make check` checks the parameterized source lint. A consumer build must
also verify every configured crate, compile its BPF object and optional
loader, and generate editor metadata. Loading is a separate runtime check.

The independent fixture can be built with:

```sh
make -C tests/fixtures/arithmetic BUILD_DIR="$PWD/build/smoke" \
    VMLINUX=/path/to/target/vmlinux
```

It proves and compiles an exported wrapping increment without any consumer
runtime crates. The fixture is a compile test, not a loadable BPF program.
