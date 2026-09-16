## Public-boundary review

- [ ] This change contains no credentials, private keys, tokens, private IP addresses, hardware IDs, device IDs, or production hostnames.
- [ ] Deployment-specific configuration is committed to `junr03/electricpeak-sensitive`, not this repository.
- [ ] `python3 scripts/check-public-boundary.py --rev HEAD` passes.
- [ ] Generated Compose Nix modules match their source YAML.

If any box cannot be checked, stop and move the private portion to
`electricpeak-sensitive` before requesting review.
