# Agent storage: platform and tool investigations

Date checked: 2026-11-15. This is a research snapshot, not evidence that a
particular tool or filesystem is present on an OpenRC host. For the overall
findings and proposed sequence, see the [agent storage research synthesis](README.md).
No live Windows, Linux or remote Mac storage inventory was performed. Drive
letters do not establish physical-disk separation. Recommendations are
proposals, not implemented Disk Steward behavior.

## R09 — Windows storage inventory

**Question:** Which existing tools can identify storage consumers before an
operator chooses a cleanup?

**Exact queries:** `site:diskanalyzer.com WizTree how it works master file table admin NTFS official`;
`site:windirstat.net WinDirStat Windows directory statistics official scans`.

**Evidence and finding:** The [WizTree FAQ](https://diskanalyzer.com/faq) is
vendor documentation: accelerated NTFS scanning requires administrator rights,
and its file allocation totals omit some filesystem metadata. The
[WinDirStat project](https://windirstat.net/) describes drive, folder and share
scans, logical and physical sizes, and report exports. WizTree's
[license](https://diskanalyzer.com/eula) requires a supporter code for commercial
use at each business site. Godot documents that imported resources live in
[`res://.godot/imported/`](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html).

**Limits:** Scan completeness varies with permissions and filesystem; logical
folder totals can overstate physical use where links or shared blocks exist.
The Godot source does not establish that all `.godot` contents are disposable.

**OpenRC recommendation:** Have an operator capture dated, read-only scans of
the relevant C: and D: volumes, including snapshots, caches and VHDX files, and
compare with host free space before selecting any deletion.

## R10 — ReFS block cloning and hard links

**Question:** Can per-task copies share space while preserving independent writes?

**Exact query:** `site:learn.microsoft.com Dev Drive block cloning hard links ReFS requirements Windows 11`.

**Evidence and finding:** Microsoft documents [Dev Drive setup](https://learn.microsoft.com/en-us/windows/dev-drive/)
prerequisites of at least 8 GB RAM and 50 GB free disk space; these are Dev Drive
setup requirements, not universal requirements for all ReFS block cloning.
Starting in Windows 11 24H2, supported Dev Drive copy operations can use block
cloning. [ReFS cloning](https://learn.microsoft.com/en-us/windows-server/storage/refs/block-cloning)
requires the same ReFS volume and compatible integrity settings; its API has
alignment and extent-size limits. [Allocate-on-write](https://learn.microsoft.com/en-us/windows/win32/fileio/block-cloning)
preserves separate file contents after a write. By contrast,
[hard links](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions)
are names for the same file, so in-place changes are shared.

**Limits:** Not every copy is necessarily cloned; copies between volumes cannot
use the cited same-volume clone. Dev Drive's ReFS does not support WSL's
`metadata` mount option, and reformatting destroys existing volume contents.

**OpenRC recommendation:** Pilot disposable snapshots, measuring allocation and
testing independent edits; fall back to full copies. Do not hard-link mutable
working files or reformat a populated volume.

## R11 — WSL VHDX retained space

**Question:** Why might freeing guest files fail to increase Windows free space?

**Exact query:** `site:github.com/microsoft/WSL issue ext4.vhdx shrink compact disk space deleting files`.

**Evidence and finding:** [Microsoft's WSL storage guide](https://learn.microsoft.com/en-us/windows/wsl/disk-space)
documents an ext4 VHDX for each WSL 2 distribution and a guest `df` view of
its virtual filesystem. In the firsthand [WSL issue #12103](https://github.com/microsoft/WSL/issues/12103),
opened 2024-09-29 and open when checked, a Windows 10/WSL 2.2.4 user reported
an approximately 118 GB VHDX versus 64 GB of guest data, with sparse mode not
reclaiming the difference. The thread contains additional version-specific
experiences and suggested workarounds.

**Limits:** This is a user report, not a controlled test or a guarantee that
current WSL versions behave identically. Guest free space, VHDX apparent size,
VHDX allocated host space and host-volume free space are different measurements;
compaction is not guaranteed to reclaim a particular amount.

**OpenRC recommendation:** Report those measurements separately. Treat any
compaction as operator-managed maintenance after a verified backup and restore
path, not as an automatic response to a storage alert.

## R12 — BuildKit cache garbage collection

**Question:** Do BuildKit cache limits guarantee enough free space for builds?

**Exact queries:** `site:docs.docker.com build cache garbage collection buildkit reservedSpace maxUsedSpace minFreeSpace cache prune`;
`site:github.com/moby/buildkit issue cache garbage collection disk full buildkit prune`.

**Evidence and finding:** [Docker's GC documentation](https://docs.docker.com/build/cache/garbage-collection/)
describes periodic policies and the `reservedSpace`, `maxUsedSpace` and
`minFreeSpace` thresholds. Configuration differs by driver; custom policies do
not inherit the global thresholds. In firsthand [BuildKit issue #4218](https://github.com/moby/buildkit/issues/4218),
opened 2023-09-11 and open when checked, a user reported a full 130 GB volume
despite an approximately 80 GB cache target. A maintainer noted that reported
usage excluded metadata databases. [Buildx usage](https://docs.docker.com/reference/cli/docker/buildx/du/)
also distinguishes shared and in-use records.

**Limits:** The historical report is not proof of a current universal defect.
Periodic cleanup, shared layers and active builds prevent treating a cache
target as a hard host-wide free-space guarantee.

**OpenRC recommendation:** If Docker is used, inspect the selected builder and
host volume separately, set thresholds for its actual driver, and review a
narrow builder-specific prune instead of defaulting to a broad system prune.

## R13 — Python and conditional Node dependency caches

**Question:** Can agents reuse dependency artifacts without uncontrolled copies?

**Exact queries:** `site:docs.astral.sh/uv cache concurrency safe clean prune hardlink same filesystem`;
`site:pip.pypa.io caching http wheels pip cache purge pip  cache size`;
`site:pnpm.io store path prune concurrent installs same filesystem hard links pnpm store`.

**Evidence and finding:** [uv documentation](https://docs.astral.sh/uv/concepts/cache/)
describes concurrent cache access, environment installation locks, managed
pruning and same-filesystem linking; directly removing cache entries is unsafe.
In firsthand [uv issue #5731](https://github.com/astral-sh/uv/issues/5731),
opened 2024-08-02 and open when checked, a self-hosted runner user reported a
cache around 40 GB and requested a size cap. [pip](https://pip.pypa.io/en/stable/topics/caching/)
provides `pip cache info`; [pnpm](https://pnpm.io/faq) documents that
cross-filesystem installations copy instead of hard-linking from its store.

**Limits:** The issue is a historical report, not proof of behavior in every uv
version. Separate filesystems may need separate stores; summed logical sizes
can double-count hard-linked data. pnpm matters only if Node tooling is used.

**OpenRC recommendation:** Measure existing caches first. Consider one
tool-managed cache per compatible filesystem, retain per-task environments, and
budget and prune using the installed tool's supported operations.

## R14 — Compiler cache budgets

**Question:** Can native builds reuse compiler outputs within a measured budget?

**Exact queries:** `site:github.com/mozilla/sccache size cache limit SCCACHE_CACHE_SIZE 10G disk cache concurrency`;
`site:ccache.dev manual max_size cleanup automatic cache corruption hardlink`.

**Evidence and finding:** [sccache's local storage documentation](https://github.com/mozilla/sccache/blob/main/docs/Local.md)
states a 10 GB default limit, a configurable `SCCACHE_CACHE_SIZE`, and support
for only one server at a time per local store; concurrent servers can race.
The [ccache manual](https://ccache.dev/manual/4.14.1.html) describes a default
5 GB local limit, size statistics, and approximate least-recently-used cleanup
after new results are stored. Some remote backends require separate cleanup.

**Limits:** These are tool-version-specific local cache limits, not guarantees
about total host usage, active build output or host free space. Cache usefulness
and safe integration depend on the actual compiler and build configuration;
script-only Godot work may gain little.

**OpenRC recommendation:** If agents build the engine or native extensions,
benchmark hit rates, set explicit per-host budgets and enforce the documented
one-server-per-store constraint for sccache. Monitor the host volume separately.

## R15 — Deduplicated backups and full-disk recovery

**Question:** Can repeated task snapshots be backed up efficiently and pruned safely?

**Exact queries:** `site:restic.readthedocs.io prune disk space restic repository lock backup forget full disk`;
`site:github.com/restic/restic issue prune repository full disk no space left free space`.

**Evidence and finding:** [restic's backup documentation](https://restic.readthedocs.io/en/stable/040_backup.html)
describes content deduplication within a repository. Its
[retention documentation](https://restic.readthedocs.io/en/stable/060_forget.html)
describes separate `forget` and `prune` steps, dry-run options and scratch-space
requirements. In firsthand [restic issue #5766](https://github.com/restic/restic/issues/5766),
opened and closed 2026-03-28, a macOS user with 768 KiB free reported failed
pruning and an index repair that could not write. A contributor did not
establish a software bug from the available evidence.

**Limits:** Deduplication is not an independent backup. A shared repository also
shares access and retention risks. Near-full recovery can fail, and the
documented unsafe recovery mode has additional repository-availability risks.

**OpenRC recommendation:** Pilot a separately protected repository for valuable
state, monitor and reserve practical headroom, review retention with dry runs,
and test restores. Leave unsafe no-space recovery to an operator.

## R16 — Quotas and virtual-disk capacity

**Question:** Which Windows mechanisms can constrain agent storage growth?

**Exact queries:** `site:learn.microsoft.com NTFS disk quotas per user volume not directory folder server FSRM quota template`;
`site:learn.microsoft.com create attach virtual hard disk maximum size dynamically expanding virtual disk host physical disk diskpart`;
`site:learn.microsoft.com fsutil quota per volume user ReFS disk quotas unsupported`.

**Evidence and finding:** [Microsoft's NTFS quota documentation](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/fsutil-quota)
specifies per-user, per-volume quotas, not ordinary arbitrary-folder quotas.
The [Windows Server FSRM role](https://learn.microsoft.com/en-us/windows-server/storage/fsrm/fsrm-overview)
offers folder quotas on NTFS, not ReFS. Microsoft describes a dynamically
expanding [virtual disk](https://learn.microsoft.com/en-us/windows/win32/vstor/about-vhd)
whose configured maximum may exceed available backing-store free space.

**Limits:** FSRM is a Windows Server role, not a presumed Windows client
capability. An expandable virtual disk's maximum limits its virtual capacity;
it does not reserve host free space. Mounting, full-disk behavior, backup and
recovery need operational ownership.

**OpenRC recommendation:** Start with monitored warning and admission budgets.
If a hard boundary is needed, evaluate a separately mounted, finite VHDX for
disposable task data while monitoring both the guest volume and backing host.
