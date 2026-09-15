#!/usr/bin/env python3
"""Reject files and values that belong in electricpeak-sensitive."""

from __future__ import annotations

import argparse
import ipaddress
import re
import subprocess
import sys
from dataclasses import dataclass


ZERO_SHA = "0" * 40
FORBIDDEN_TOP_LEVEL = {"deployment.nix", "private-config"}
FORBIDDEN_BASENAMES = {
    ".env.local",
    ".env.production",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "id_rsa",
}
FORBIDDEN_SUFFIXES = {".key", ".kdbx", ".p12", ".pfx"}
DOCUMENTATION_NETWORKS = tuple(
    ipaddress.ip_network(network)
    for network in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")
)


@dataclass(frozen=True)
class ContentRule:
    name: str
    pattern: re.Pattern[str]
    guidance: str


CONTENT_RULES = (
    ContentRule(
        "production Electricpeak domain",
        re.compile(r"(?i)(?:^|[^a-z0-9-])(?:[a-z0-9-]+\.)*electricpeak\.net(?:[^a-z0-9-]|$)"),
        "put production DNS, TLS, Envoy, and service hostnames in electricpeak-sensitive",
    ),
    ContentRule(
        "hardware filesystem UUID",
        re.compile(r"(?i)/dev/disk/by-uuid/[0-9a-f-]+"),
        "put hardware identifiers in electricpeak-sensitive and use labels/placeholders publicly",
    ),
    ContentRule(
        "Home Assistant device identifier",
        re.compile(r"(?im)^\s*device_id\s*:\s*[0-9a-f]{24,}\s*(?:#.*)?$"),
        "put real Home Assistant entity/device configuration in electricpeak-sensitive",
    ),
    ContentRule(
        "Home Assistant serial-bearing entity",
        re.compile(r"(?i)\b(?:sensor|binary_sensor|switch|light|lock|cover)\.[a-z0-9_]*[0-9]{8,}[a-z0-9_]*\b"),
        "replace device serials with examples or move the configuration to electricpeak-sensitive",
    ),
    ContentRule(
        "private key material",
        re.compile(r"-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----"),
        "remove the credential, rotate it, and store the replacement in 1Password",
    ),
    ContentRule(
        "GitHub or 1Password token",
        re.compile(r"\b(?:gh[opusr]_[A-Za-z0-9_]{20,}|ops_[A-Za-z0-9_]{20,})\b"),
        "remove and rotate the token; commit only its op:// reference",
    ),
)

PR_JOB_FORBIDDEN = (
    (re.compile(r"\$\{\{\s*secrets\."), "references GitHub secrets"),
    (re.compile(r"(?m)^\s{4}environment\s*:"), "declares a protected environment"),
    (re.compile(r"repository\s*:\s*junr03/electricpeak-sensitive"), "checks out private configuration"),
    (re.compile(r"tailscale/github-action"), "connects to the private network"),
)

DEPLOY_JOB_REQUIREMENTS = (
    "github.repository == 'junr03/electricpeak'",
    "github.ref == 'refs/heads/main'",
    "environment: production",
    "repository: junr03/electricpeak-sensitive",
    "token: ${{ secrets.PAT_ELECTRICPEAK }}",
)


def git(*args: str, input_text: str | None = None) -> bytes:
    return subprocess.check_output(
        ["git", *args],
        input=None if input_text is None else input_text.encode(),
        stderr=subprocess.DEVNULL,
    )


def revisions_from_push() -> list[str]:
    revisions: set[str] = set()
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise ValueError("unexpected pre-push input")
        _local_ref, local_sha, _remote_ref, remote_sha = fields
        if local_sha == ZERO_SHA:
            continue
        if remote_sha == ZERO_SHA:
            output = git("rev-list", local_sha, "--not", "--remotes")
        else:
            output = git("rev-list", f"{remote_sha}..{local_sha}")
        revisions.update(output.decode().splitlines())
    return sorted(revisions)


def tree_entries(revision: str) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    for raw in filter(None, git("ls-tree", "-rz", "--full-tree", revision).split(b"\0")):
        metadata, raw_path = raw.split(b"\t", 1)
        mode, kind, object_id = metadata.decode().split()
        entries.append((mode, kind, raw_path.decode("utf-8", "surrogateescape")))
    return entries


def read_blob(revision: str, path: str) -> str | None:
    content = git("show", f"{revision}:{path}")
    if b"\0" in content:
        return None
    return content.decode("utf-8", "replace")


def private_ipv4s(text: str) -> set[str]:
    findings: set[str] = set()
    for candidate in re.findall(r"(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])", text):
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        is_documentation = any(address in network for network in DOCUMENTATION_NETWORKS)
        if (
            address.is_private
            and not address.is_loopback
            and not address.is_unspecified
            and not is_documentation
        ):
            findings.add(candidate)
    return findings


def workflow_jobs(text: str) -> dict[str, str]:
    """Extract top-level job sections from the deliberately simple CI YAML."""
    jobs: dict[str, list[str]] = {}
    current: str | None = None
    in_jobs = False
    for line in text.splitlines(keepends=True):
        if line == "jobs:\n" or line == "jobs:\r\n":
            in_jobs = True
            continue
        if not in_jobs:
            continue
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*(?:#.*)?$", line.rstrip("\r\n"))
        if match:
            current = match.group(1)
            jobs[current] = [line]
        elif line and not line[0].isspace():
            break
        elif current is not None:
            jobs[current].append(line)
    return {name: "".join(lines) for name, lines in jobs.items()}


def inspect_ci_workflow(revision: str, text: str) -> list[str]:
    failures: list[str] = []
    jobs = workflow_jobs(text)
    for name, section in jobs.items():
        location = f"{revision[:12]}:.github/workflows/ci.yml:{name}"
        if not re.search(r"(?m)^    runs-on:\s*ubuntu-latest\s*$", section):
            failures.append(f"{location}: public workflow jobs must run on ubuntu-latest")
        if name == "deploy-production":
            for requirement in DEPLOY_JOB_REQUIREMENTS:
                if requirement not in section:
                    failures.append(
                        f"{location}: production deployment is missing guard {requirement!r}"
                    )
            continue
        for pattern, description in PR_JOB_FORBIDDEN:
            if pattern.search(section):
                failures.append(
                    f"{location}: pull-request-capable job {description}; "
                    "only deploy-production may cross the private boundary"
                )
    return failures


def inspect_revision(revision: str) -> list[str]:
    failures: list[str] = []
    for mode, kind, path in tree_entries(revision):
        parts = path.split("/")
        if parts[0] in FORBIDDEN_TOP_LEVEL:
            failures.append(
                f"{revision[:12]}:{path}: production configuration belongs in electricpeak-sensitive"
            )
            continue
        if path == ".gitmodules" or mode == "160000" or kind == "commit":
            failures.append(
                f"{revision[:12]}:{path}: submodules are forbidden in the public repository"
            )
            continue
        basename = parts[-1].lower()
        if basename in FORBIDDEN_BASENAMES or any(basename.endswith(suffix) for suffix in FORBIDDEN_SUFFIXES):
            failures.append(
                f"{revision[:12]}:{path}: credential-shaped files must not be committed publicly"
            )
            continue
        if kind != "blob":
            failures.append(f"{revision[:12]}:{path}: unexpected Git object type {kind}")
            continue
        text = read_blob(revision, path)
        if text is None:
            continue
        if path == ".github/workflows/ci.yml":
            failures.extend(inspect_ci_workflow(revision, text))
        for rule in CONTENT_RULES:
            for match in rule.pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{revision[:12]}:{path}:{line}: {rule.name}; {rule.guidance}"
                )
        for address in sorted(private_ipv4s(text)):
            line = next(
                index for index, value in enumerate(text.splitlines(), 1) if address in value
            )
            failures.append(
                f"{revision[:12]}:{path}:{line}: private IPv4 address {address}; "
                "use a documentation address publicly or move the value to electricpeak-sensitive"
            )
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--rev", action="append", dest="revisions", metavar="REV")
    source.add_argument("--history", action="store_true", help="scan every reachable commit")
    source.add_argument(
        "--pre-push", action="store_true", help="read the standard pre-push update list from stdin"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.pre_push:
        revisions = revisions_from_push()
    elif args.history:
        revisions = git("rev-list", "--all").decode().splitlines()
    else:
        revisions = args.revisions or ["HEAD"]

    failures: list[str] = []
    for revision in revisions:
        resolved = git("rev-parse", "--verify", f"{revision}^{{commit}}").decode().strip()
        failures.extend(inspect_revision(resolved))

    if failures:
        print("Public-boundary check failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        print(
            "\nDo not bypass this check. Move deployment-specific content to "
            "junr03/electricpeak-sensitive and rotate any exposed credential.",
            file=sys.stderr,
        )
        return 1

    print(f"Public-boundary check passed for {len(revisions)} commit(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
