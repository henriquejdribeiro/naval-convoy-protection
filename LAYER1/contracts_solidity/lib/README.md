# Vendored Solidity contract dependencies

These directories were originally git submodules; they are now vendored in-tree
(plain files) so the exact dependency source ships with this repository and is
reproducible independently of upstream. Each is the **unmodified** upstream tree
at the pinned commit below — verified byte-for-byte against upstream.

| Directory | Upstream | Pinned commit | Version | License |
|---|---|---|---|---|
| `forge-std` | https://github.com/foundry-rs/forge-std | `1eea5bae12ae557d589f9f0f0edae2faa47cb262` | v1.9.4 | MIT / Apache-2.0 (see `forge-std/LICENSE-MIT`, `forge-std/LICENSE-APACHE`) |
| `openzeppelin-contracts` | https://github.com/OpenZeppelin/openzeppelin-contracts | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | 12 commits past v5.0.0 | MIT (see `openzeppelin-contracts/LICENSE`) |

Foundry remappings resolve these at their existing paths, so `forge build` is
unaffected by the submodule-to-files conversion.

Verify provenance for any entry:

    git clone <upstream> /tmp/x && git -C /tmp/x checkout <pinned-commit>
    diff -r --exclude=.git <directory> /tmp/x
