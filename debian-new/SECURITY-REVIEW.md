Pre-installation software safety review of `debian-new`, 2026-09-19, at repository commit
`2577155a8a33db913f1250191bb1d766e6ba044f`.

**Follow-up:** Neovim language servers have been disabled at the user's request.
`run-all.sh` skips step 6, its `SERVERS` entries are commented out, and running
step 6 directly now exits without installing anything. The shared Neovim config
also comments out the `plugins.mason-lspconfig` import, preventing its automatic
server installation and activation. The findings below describe the original
configuration; review them before re-enabling language servers. This change does
not uninstall existing packages or alter the separate Claude plugin settings.

Recommendation: keep the core tools from their official sources, but correct
the Bash language server's vulnerable dependency before deployment. The checks
did not identify a known malicious package or an obvious malicious payload in
the screened plugin source. They did identify a real vulnerable dependency.
This is a qualified assessment, not certification that every component is free
of malware.

**Confirmed dependency issue:** resolving the existing versions with the
script's `2026-09-05` npm cutoff and Mason's shallow installation strategy gives:

```text
bash-language-server 5.6.0
  -> editorconfig 2.0.1
     -> minimatch 10.0.1
```

That minimatch version matches three published denial-of-service advisories:
[GHSA-23c5-xmqv-rm74](https://github.com/isaacs/minimatch/security/advisories/GHSA-23c5-xmqv-rm74),
[GHSA-3ppc-4f35-3m26](https://github.com/isaacs/minimatch/security/advisories/GHSA-3ppc-4f35-3m26),
and [GHSA-7r86-cg39-jmmj](https://github.com/isaacs/minimatch/security/advisories/GHSA-7r86-cg39-jmmj).
Crafted glob patterns can cause excessive CPU use or hangs. This is a vulnerable
dependency, not evidence of malware or a compromised publisher. Exploitability
through this particular editor configuration was not demonstrated.

A replacement candidate, `bash-language-server 5.7.1`, resolved with a
`2026-09-17` cutoff to `editorconfig 3.0.2` and `minimatch 10.2.6`. Its 36
package/version pairs returned no OSV advisory matches. However, it was
published September 16 and is rejected by the existing September 5 cutoff;
adopting it now would also depart from the script's two-week release-age policy.
An alternative is a reviewed dependency override while retaining the older
server. Neither option was applied, and functional compatibility was not tested.

| Software | Assessment from this review |
| --- | --- |
| Debian package list | A reasonable baseline when obtained through official Debian archives. The scripts name ordinary system/desktop/development packages; exact target versions and the complete APT dependency graph were not available for assessment. |
| Neovim, Yazi, Tree-sitter CLI, Node.js, GitHub CLI | Official upstream download locations; metadata and the advisory checks below did not identify a reason to reject these pinned releases as malicious. Prebuilt binaries were not reverse-engineered or comprehensively scanned. |
| 33 enabled Neovim plugins, lazy.nvim, TPM, tmux-resurrect | Exact source archives were retrieved from the configured upstream repositories. Targeted source screening and manual examination of flagged code did not reveal an obvious malicious payload. This was not a line-by-line audit. |
| Bash language server 5.6.0 | Correct the vulnerable minimatch dependency before rollout. |
| Pyright and TypeScript language server | No advisory matches in their resolved npm dependency trees, including Mason's additional TypeScript package. This does not prove absence of unreported malicious code. |
| Lua language server, OmniSharp, rust-analyzer | Recipes point to the expected upstream projects; their repository advisory APIs returned no published advisories. Bundled native/.NET dependencies were not comprehensively analyzed. |
| Claude plugins | The shared settings enable additional plugins but do not specify the installed versions. Their actual plugin payloads were not assessed in this source screening; no claim that they are compromised is being made. |

The plugin screening covered 36 active source archives and 2,267 selected code
files. It looked for credential access, unexpected download destinations,
encoded execution, and bundled executable assets, followed by examination of
the flagged paths. For example, Gitsigns' bytecode loading implements background
diff work, Kanagawa's generated code caches theme settings, and Fugitive reads
SSH configuration to resolve Git host aliases. These matches did not establish
malicious behavior. Both Copilot plugins in the Neovim lockfile are disabled in
the configuration and were excluded from the active archive screening.

All 36 active plugin/manager commits were also queried against OSV, with no
matches. Git-based plugin coverage in vulnerability databases is incomplete.
The three existing npm server installations resolved to 44 unique package/version
pairs; one is macOS-only optional `fsevents`, not needed on Debian. Of those 44,
only minimatch returned advisory matches. No known-malware match was returned.
The TypeScript resolution included `typescript 6.0.3`, required by the Mason
recipe read during this review.

No provisioning scripts, Neovim/tmux plugin code, or npm lifecycle scripts were
run. The official Node archive was checked against its pinned SHA-256 and used
under `/tmp` to run npm with `--package-lock-only --ignore-scripts`, isolated npm
configuration, and a temporary cache. No language-server packages were installed.
The target Debian machines, their APT configuration, and installed files were not
examined. Investigation data and candidate lockfiles are in
`/tmp/debian-new-content-review`; these are temporary review artifacts, not locks
used by the setup scripts.

The following checks passed:

- All five SHA-256 values in `3-download-programs.sh` match the publishers'
  current HTTPS release metadata. The installer checks each downloaded archive
  before unpacking it. This confirms agreement with the publisher's metadata;
  it does not prove the original release was trustworthy.
- `4-git-clones.sh` specifies full commit IDs for TPM, tmux-resurrect, and
  lazy.nvim. The shared Neovim lockfile contains 35 well-formed commit pins.
- Step 5 uses `Lazy! restore`, and step 6 specifies six language-server versions
  and enables npm's `ignore-scripts` setting.
- The runner refuses root execution and invokes only the Debian package step
  through sudo/su. User-level plugins still have access to the user's files and
  credentials; this privilege separation is not a plugin sandbox.
- All seven setup scripts passed `bash -n`. This is a syntax check, not a malware
  test.

| Download | Pinned version | Expected SHA-256 versus publisher metadata |
| --- | --- | --- |
| Neovim | 0.12.5 | Match: [release API](https://api.github.com/repos/neovim/neovim/releases/tags/v0.12.5) |
| Yazi | 26.9.1 | Match: [release API](https://api.github.com/repos/sxyazi/yazi/releases/tags/v26.9.1) |
| Tree-sitter CLI | 0.27.0 | Match: [release API](https://api.github.com/repos/tree-sitter/tree-sitter/releases/tags/v0.27.0) |
| Node.js | 22.23.2 | Match: [published checksums](https://nodejs.org/dist/v22.23.2/SHASUMS256.txt) |
| GitHub CLI | 2.100.0 | Match: [release API](https://api.github.com/repos/cli/cli/releases/tags/v2.100.0) |

The priority findings before deployment are:

1. **Mason installations are only partly pinned.**
   `6-language-servers.sh:29` fixes the six main versions, but
   `common/config/nvim/lua/plugins/mason-lspconfig.lua:90` also requests missing
   servers without versions. Opening a file before step 6 completes, or after a
   server is removed, can install a newer server outside step 6's date cutoff.
   The Mason configuration also uses an unversioned registry. At the pinned
   Mason commit, its [defaults](https://github.com/mason-org/mason.nvim/blob/2a6940af80375532e5e9e7c1f2fc6319a1b7a69d/lua/mason/settings.lua)
   enable registry refresh, and the [registry loader](https://github.com/mason-org/mason.nvim/blob/2a6940af80375532e5e9e7c1f2fc6319a1b7a69d/lua/mason-registry/sources/github.lua)
   resolves the latest release when no registry version is specified.
   Consequently, pinning the Mason plugin does not pin its installation recipes.
   Disable automatic server installation for this setup, pin the registry
   snapshot, and keep reviewed dependency locks and artifact hashes for the
   server installations.

2. **The npm cutoff is not a complete dependency lock or malware check.**
   `6-language-servers.sh:45` and `:89` restrict package publication dates, but
   the repository does not record the resolved npm dependency tree and its
   integrity hashes. A cutoff limits eligibility; it does not authenticate
   which dependencies were selected or show that older packages are safe.
   `ignore-scripts` blocks package lifecycle scripts during installation, but
   malicious code could still execute when a language server is launched.
   Commit the resolved lockfiles, install from those locks with lifecycle
   scripts disabled, and check the complete dependency tree against advisory
   databases. See npm's [configuration documentation](https://docs.npmjs.com/cli/v10/using-npm/config/)
   and [lockfile documentation](https://docs.npmjs.com/cli/v10/configuring-npm/package-lock-json/).

3. **A native Tree-sitter parser is fetched through a movable tag.**
   `common/config/nvim/lua/plugins/nvim-treesitter.lua:18` and `:27` update/build
   parsers and install missing ones. Of the 16 explicitly requested parsers,
   15 use commit revisions in the pinned plugin's [parser recipes](https://github.com/nvim-treesitter/nvim-treesitter/blob/e82ef6ae2c3eeb96c6916b29917f96bf630b2cdb/lua/nvim-treesitter/parsers.lua).
   The C# recipe uses `v0.23.5`. The pinned [installer](https://github.com/nvim-treesitter/nvim-treesitter/blob/e82ef6ae2c3eeb96c6916b29917f96bf630b2cdb/lua/nvim-treesitter/install.lua)
   downloads `/archive/<revision>.tar.gz` and compiles it without checking a
   separately pinned archive digest. A moved C# tag could therefore change the
   downloaded source while `lazy-lock.json` remains unchanged. Pin that parser
   to a reviewed full commit and verify downloaded parser artifacts before
   building. Parser binaries are additional executable dependencies beyond the
   plugin Git checkouts.

4. **Claude plugins and hooks extend the setup beyond these pins.**
   `2-link-dotfiles.sh:51` links the shared Claude settings. In
   `common/config/claude/settings.json:194`, eight plugins are enabled without
   versions recorded here; an extra marketplace is configured without a commit
   at `:204`, and the Claude update channel is `latest` at `:218`. Hooks also
   execute `~/.local/bin/aivim`, whose installation is outside these six steps.
   These entries are not evidence of compromise, but they are outside the
   setup's verification. Use a Debian-specific reviewed plugin inventory with
   pinned sources, or leave optional plugins disabled until separately reviewed.
   Claude's own updater and marketplace/plugin updates are separate mechanisms;
   changing the application channel alone does not pin plugins. See the
   [marketplace documentation](https://code.claude.com/docs/en/plugin-marketplaces).

5. **The rerun checks do not verify installed contents.**
   `3-download-programs.sh:41` and the analogous checks execute an existing
   program and trust its version output. `4-git-clones.sh:27` accepts a matching
   Git HEAD without checking modified or added files. Step 5 launches Neovim
   before checking plugin commits, and its loop at `5-neovim-plugins.sh:59`
   checks only lockfile entries: absent entries do not fail, additional plugins
   are not enumerated, and working-tree changes are not checked. Step 6 trusts
   version receipts. These checks help with repeatability but cannot detect
   many forms of installed-file tampering. Verify expected content before
   execution, check active plugins against the lock in both directions, and
   distinguish intentionally disabled plugins from missing required ones.

6. **“From Debian” is an assumption about each target machine.**
   `1-install-debian-packages.sh:73` uses the machine's existing APT sources,
   keys, and settings. It does not add a suspicious repository or disable
   verification, but it also does not establish that all candidates come from
   official Debian archives. Before provisioning, inspect candidate origins,
   require the intended Debian archive keys and suites, reject settings that
   bypass authentication, and verify security-update configuration. APT's
   signatures authenticate archive metadata and package hashes; they do not
   guarantee that a package maintainer or signing infrastructure was never
   compromised. See Debian's [apt-secure documentation](https://manpages.debian.org/trixie/apt/apt-secure.8.en.html).

The advisory checks were limited as follows:

| Check | Result on the review date |
| --- | --- |
| [GitHub CLI published advisories](https://github.com/cli/cli/security/advisories) | The 13 returned advisories identify fixes no later than 2.98.0; the pin is 2.100.0. |
| [Neovim published advisories](https://github.com/neovim/neovim/security/advisories) | The one returned advisory affects releases through 0.8.2; the pin is 0.12.5. |
| [Yazi published advisories](https://github.com/sxyazi/yazi/security/advisories) | The one returned advisory is fixed in 26.8.15; the pin is 26.9.1. |
| [Tree-sitter published advisories](https://github.com/tree-sitter/tree-sitter/security/advisories) | No published advisories returned. |
| [Node.js security releases](https://nodejs.org/en/blog/vulnerability/july-2026-security-releases) | The latest security-release notice listed at review time includes the pinned 22.23.2 release. |
| pyright 1.1.412, bash-language-server 5.6.0, typescript-language-server 6.0.0 | GitHub's reviewed-advisory API and the [OSV API](https://google.github.io/osv.dev/api/) returned no matches for these direct package/version pairs. Scanning their resolved dependencies found the minimatch advisories described above. |
| Lua language server, OmniSharp, rust-analyzer | Their upstream GitHub repository advisory APIs returned empty lists. This is limited evidence, not a clean bill of health for their binaries or dependencies. |
| 36 active plugin/manager commits | OSV commit queries returned no matches. See the source-screening scope and limitations above. |

No complete upstream source audit, binary malware scan, signature or
build-attestation verification, or isolated full installation test was performed.
The Debian dependency tree, native/.NET language-server dependencies, and full
plugin/parser/submodule dependency trees have not been comprehensively assessed.
Empty advisory results do not establish absence of malware or unreported
vulnerabilities.

The next deployment check should run in a disposable Debian VM without personal
credentials: capture the actual package/plugin inventory, verify its origins
and integrity, scan that resolved inventory, and inspect unexpected downloads
or processes. Repeat the review when changing pins, and keep security updates
under review: a permanently frozen version can retain a known vulnerability.
