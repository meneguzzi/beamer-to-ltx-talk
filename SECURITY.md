# Security Policy

## Scope

This project is a set of local scripts and agent instructions that transform `.tex` files on disk.
It doesn't run as a network service and doesn't handle credentials, so the realistic attack surface
is narrow: mainly path handling in `scripts/*.py` when run against untrusted input files, and
supply-chain integrity of the repo itself.

## Reporting a vulnerability

If you find a security issue — e.g. a way a crafted `.tex`/filename could cause `scripts/*.py` to
read/write outside the intended project directory, or a problem with how a release artefact is
built — please open a [GitHub issue](https://github.com/meneguzzi/beamer-to-ltx-talk/issues/new)
using the bug report template, with a description and, if possible, a minimal reproduction. If the
issue is sensitive enough that public disclosure before a fix would be risky, note that at the top
of the issue and keep technical details minimal until a maintainer responds.

Expect an acknowledgement within a few days; this is a small project maintained alongside other
work, not a funded security response team.

## Not in scope

Bugs in the *conversion logic itself* (a construct that converts incorrectly, a `--lint` false
negative, a compile error) are correctness issues, not security issues — please file those as a
normal [bug report](.github/ISSUE_TEMPLATE/bug_report.yml) instead.
