# Madara — vendored Layer-2 client source

This directory vendors the **complete, unmodified** source of the Starknet
sequencer our Layer-2 runs.

- Image we run: `ghcr.io/madara-alliance/madara:v0.9.1` (pinned in `LAYER2/docker-compose.l2.yml`)
- Source:       https://github.com/madara-alliance/madara  (release v0.9.1)
- Language:     Rust (Cargo workspace)
- License:      see `madara-src/LICENSE`

We do not build Madara; the L2 stack pulls the official prebuilt image. This
source is included verbatim so the exact code behind that image can be read and
the work reproduced, independent of upstream availability. Upstream unmodified.
