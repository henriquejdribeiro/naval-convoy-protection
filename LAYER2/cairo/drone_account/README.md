# drone_account — wizard-generated OZ account (currently dormant)

The contract source under `src/lib.cairo` is the basic Account contract
generated from the OpenZeppelin Cairo Contracts v3 wizard:

  https://docs.openzeppelin.com/contracts-cairo/3.x/wizard

The intent is to have a project-controlled, source-verifiable account class
declared on each Madara so the drone-side keys map to known bytecode.

## Why it's not currently built or deployed

The OZ Cairo Contracts v3.0.0 packages (`openzeppelin_account = "3.0.0"`)
require **scarb ≥ 2.13.1** because they depend on `starknet ^2.13.1`.

Our toolchain is currently pinned to **scarb 2.11.4** because that's the
closest available match to `cairo-lang-sierra-to-casm 2.12.3`, which is
the version Madara **v0.9.1** uses internally. Madara v0.10.1+ migrated
to the rebranded `cairo-lang 1.0.0-alpha` (the next-gen Sierra compiler)
which is incompatible with scarb's 2.x CASM output entirely.

So there's no Madara tag that simultaneously supports:
  - scarb ≥ 2.13.1 (needed by OZ v3)
  - the cairo-lang 2.x CASM format (needed for compatibility with scarb 2.x)

When that alignment exists (likely after Madara's main branch stabilises
on the new cairo-lang), this project should compile and be deployed via
`scripts/deploy-l2.sh` (add a `declare_account_class()` step), then
`scripts/generate-drone-accounts.sh` should be updated to use the
resulting class hash instead of Madara's pre-declared OZ class.

## What we use instead

`scripts/generate-drone-accounts.sh` deploys drone accounts using
Madara devnet's **pre-declared** OZ account class at hash
`0xe2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6`.
That's bytecode-identical to a stock OZ account, just not built from
the wizard source we'd have preferred.
