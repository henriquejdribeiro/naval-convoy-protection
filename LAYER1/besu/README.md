# Hyperledger Besu — vendored Layer-1 client source

This directory vendors the **complete, unmodified** source of the Ethereum
execution client our Layer-1 validators run.

- Image we run: `hyperledger/besu:26.7.1` (pinned in `LAYER1/docker-compose.l1.yml`)
- Source:       https://github.com/hyperledger/besu
- Tag:          26.7.1
- Commit:       49026aaf059f832a93f964d8d27191de2f0580e9
- License:      Apache-2.0 (see `besu-src/LICENSE` and `besu-src/NOTICE`)

We do not build Besu; the ships pull the official prebuilt image. This source is
included verbatim so the exact code behind that image can be read and the work
reproduced, independent of upstream availability. The upstream tree is unchanged.

The one external reference Besu declares (`ethereum/referencetests/.../external-resources`,
the Ethereum Foundation test vectors) is an upstream submodule and is intentionally
omitted here — it is shared test data, not Besu source.

## Cloning this repository on Windows

Besu's test tree contains file paths longer than Windows' 260-character limit.
Before cloning on Windows, enable long paths once:

    git config --global core.longpaths true
