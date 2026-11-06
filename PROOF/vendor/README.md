# Vendored dependency: stark-evm-adapter

Originally a git submodule, now vendored in-tree (plain files) — the **unmodified**
upstream tree at the pinned commit below, verified byte-for-byte against upstream.

- Directory:     `stark-evm-adapter/`
- Upstream:      https://github.com/zksecurity/stark-evm-adapter
- Pinned commit: `e044116e3cf4e3cbca11cce7b9e508a0f3e6870b`
- Version:       33 commits past v0.1.0-alpha
- Language:      Rust
- License:       see `stark-evm-adapter/LICENSE`

The convoy submitter (`PROOF/submitter`) builds against this crate.

Verify: `git clone <upstream> /tmp/x && git -C /tmp/x checkout e044116 && diff -r --exclude=.git stark-evm-adapter /tmp/x`
