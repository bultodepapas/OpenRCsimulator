# NK-3 native tooling research (2026-10-28)

Question: which existing, freely available tools most cheaply improve C++ migration checks and performance
investigation without changing the NK-3 numerical contract? This is a research note, not evidence that a new
tool or workflow has passed. The inspected tree was at `b16c48de4b481c246aac4db7fb443d9ca3767ab3` with unrelated
working-tree edits. The lock is GCC 13.3.0, SCons 4.10.1, godot-cpp commit `507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`
and the pinned Linux Godot editor ([lock](../../../../research/native-kernel/toolchain-lock.json)).

## Evidence

| Question | Source and applicability |
| --- | --- |
| Can sanitizers check an extension loaded by the official editor? | [ASan's maintainers](https://github.com/google/sanitizers/wiki/AddressSanitizer) describe using a dynamically linked ASan runtime preloaded into an unsanitized executable for an instrumented shared library. [Godot 4.7](https://docs.godotengine.org/en/4.7/engine_details/development/debugging/using_sanitizers.html) says checking the engine itself requires recompiling Godot. These statements address different coverage: an instrumented extension can be checked with the official host, but engine internals remain uninstrumented. Compatibility with this pinned host and extension has not been tested. |
| Will a sanitizer report necessarily fail the existing runner? | GCC 13.3 says [UBSan normally recovers](https://gcc.gnu.org/onlinedocs/gcc-13.3.0/gcc/Instrumentation-Options.html), so an error may still exit successfully. The [checked runner](../../../../tools/godot/run_checked.py) recognizes Godot-style line-start diagnostics; a typical ASan `==pid==ERROR` or UBSan `file:line: runtime error` is not classified by that expression. The existing numerical `NK_MUTATION` is not a sanitizer positive control. |
| Is a compilation database already available? | The [pinned godot-cpp source](https://github.com/godotengine/godot-cpp/blob/507ed9d840c01a3c5b2a39af8bb4000bfac30bf5/tools/godotcpp.py) defines `compiledb` and `compiledb_file`. [SCons](https://mail.scons.org/doc/latest/HTML/scons-user/ch27.html) supplies the database builder; [clang-tidy](https://clang.llvm.org/extra/clang-tidy/) consumes a compilation database. The current [NK-3 builder](../../../../research/native-kernel/build.py) does not expose this option. Inclusion of its outer `SharedObject` and all actual flags must be verified. |
| Does static analysis certify exact math? | No. [Clang](https://clang.llvm.org/docs/DriverInternals.html) does not support every GCC option; [GCC](https://gcc.gnu.org/onlinedocs/gcc-13.3.0/gcc/Extended-Asm.html) cannot validate all instruction/operand semantics inside extended asm. NK-3's [`nk::R`](../../../../research/native-kernel/src/nk_math.hpp) deliberately uses SSE2 asm and a `pow` barrier to preserve operand and library behavior; the existing pinned-GCC byte oracles remain necessary. |
| What timing evidence already exists? | The [trajectory harness](../../../../research/native-kernel/trajectory.gd) already alternates reference/native pairs, warms up, and reports per-tick median and p95. At the inspected snapshot its timed loop broke on a failed warm-up but still measured; it did not verify tick advancement for each measured call or reject a paused session. Existing [results](README.md) are shared-VM, debug-editor evidence, not target-host qualification. |
| What can Linux `perf` add? | [`perf stat -r`](https://github.com/torvalds/linux/blob/master/tools/perf/Documentation/perf-stat.txt) repeats a command and reports mean and standard deviation; [`perf record`](https://github.com/torvalds/linux/blob/master/tools/perf/Documentation/perf-record.txt) can sample call stacks. Access depends on [kernel perf permissions](https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html). Whole-command counters include startup and, in the present harness, both backends; they are not native-stage cost alone. |

## Ranked recommendations

1. **Add an isolated GCC ASan/UBSan diagnostic variant.** Keep the locked FP flags and add
   `-fsanitize=address,undefined`, `-fno-sanitize-recover=undefined`, debug symbols and frame pointers to the
   diagnostic compile, with sanitizer flags also on the shared-library link. Use a separate build/descriptor,
   receipt, reports and godot-cpp build artifacts; an explicit variant marker must prevent installation or
   promotion as the regular binary. Preload the matching `g++ -print-file-name=libasan.so` into **Godot only**,
   and record the runtime/compiler and binary identities. Run the existing stage oracle and a bounded trajectory;
   reject incomplete runs, nonzero exits and sanitizer signatures in retained stderr. First prove both ASan and
   UBSan detection with intentionally faulty, disposable instrumented code loaded by the same Godot path; the
   positive controls must report the intended error and fail. If an app-installed extension would auto-load the
   same class, run with an isolated, freshly imported app copy rather than overwrite it. Check actual compile and
   link commands to establish which components were instrumented. The sanitizer build supplements the normal
   exact-byte gate; it is neither performance evidence nor complete engine coverage. GCC does not include
   floating-point divide-by-zero and float-to-integer overflow in its `undefined` group; decide separately whether
   those checks fit the malformed-input contract ([GCC 13.3](https://gcc.gnu.org/onlinedocs/gcc-13.3.0/gcc/Instrumentation-Options.html)).

2. **Expose the pinned SCons compilation database, then try clang-tidy as advisory analysis.** Generate it under
   ignored `tmp/` using the existing godot-cpp/SCons facility, not a new database generator. Validate that it
   contains every NK-3 translation unit and its real generated include paths, defines, C++17 and strict FP flags;
   regenerate after build/source changes. Run a small, named set of bug-focused clang-tidy checks on NK-3 sources
   and headers, with a recorded exact tool version and no automatic fixes. Treat unsupported GCC flags, absent
   headers or `clang-diagnostic-error` as an unavailable analysis, not a clean pass. Manually review any suggested
   rewrite, especially `nk_math.hpp`, and rerun the regular GCC byte oracles after accepted code changes.
   `clang-tidy` and `clangd` were not on this host's `PATH` during this read-only inspection.

3. **Harden and reuse the existing paired timing before adding a performance gate.** Require completed warm-up
   and exactly the requested number of advancing, unpaused, fault-free measured ticks for each side and pair; retain
   individual pair results and reject incomplete cases. Compare matched baseline/candidate on the same tapes,
   aircraft/data, engine, target, settings and host; record source/binary identities, hardware, load and timing
   configuration. Use repeated pairs and their spread before selecting any threshold; noisy shared-host changes
   are inconclusive. Profile with stock `perf` only when access is available and attribution is actually needed;
   either delimit the desired phase or label counters as whole-process. Keep profiling and sanitizer overhead out
   of timing acceptance. `perf` was on `PATH` here and `perf_event_paranoid` was `4`; no PMU access test or
   benchmark was run, so availability is unknown. Do not change system permissions merely to enable the tool.

No new benchmark, sanitizer build or analysis was executed for this note. These checks establish software
behavior and measured execution cost only; neither establishes physical realism or display qualification.

## Focused timing policy repair (2026-10-28)

The timing and attribution loops now reject invalid counts, incomplete warm-up, failed or non-advancing ticks,
and missing native-stage/context coverage before emitting timing summaries. Checks run outside the measured
session/simulation calls. A checked headless run of `test_trajectory.gd` passed 105 checks with zero failures,
engine warnings or errors; it includes fake-session cases for both loops. The local report and log are under
`tmp/nk3-timing-tool-checks/nk3-timing-policy-recheck-3n110os5/`. This is policy verification, not a native
performance measurement; the pre-repair historical results above have not been requalified.

## ASan loader result and revised recommendation (2026-10-28)

**This supersedes the ASan recommendation above for the official Linux editor.** A real stage-oracle attempt
with GCC 13.3.0 ASan/UBSan extension `07e9b83d…279dc58` and the pinned editor `28485fbd…5e82` failed at extension
load, before any oracle results. The checked process exited 1 and lacked the pass marker; its local log is
`tmp/nk3-dev-stage-final/checks/oracle-ml7f__jd/engine.log`. The separate ASan and UBSan positive controls
detected their injected faults, but they used a preloaded constructor before `Godot --version` and did not
exercise GDExtension loading.

The [exact Godot revision](https://github.com/godotengine/godot/blob/4d10419cacd6d3009976e8f9fd3abd970fd58018/drivers/unix/os_unix.cpp)
selects `RTLD_NOW | RTLD_DEEPBIND` at compilation unless `ASAN_ENABLED` is defined; the same source passes
that mode to `dlopen` for GDExtension libraries. The [sanitizer maintainers](https://github.com/google/sanitizers/wiki/AddressSanitizer)
state that ASan does not support `RTLD_DEEPBIND`, and their [issue](https://github.com/google/sanitizers/issues/611)
describes the broken allocator interception behind this restriction. The generic shared-library preload advice
in the evidence table does not establish compatibility with this loader. No Godot runtime switch was found in the
inspected loader. GCC's [ASan source](https://github.com/gcc-mirror/gcc/blob/releases/gcc-13.3.0/libsanitizer/asan/asan_linux.cpp)
shows `verify_asan_link_order` controls a different startup check; turning it off does not remove deep binding.

For the smallest next check, try a **UBSan-only** extension against the unchanged official editor, with a
separate receipt, `-fsanitize=undefined` at compile and link, non-recovery and `UBSAN_ENABLED` for godot-cpp.
Run a disposable fault injected into an actually called native stage through the same GDExtension loader and
require the intended diagnostic and nonzero exit, then run the unmodified stage oracle. This route is a candidate,
not a demonstrated pass; it provides undefined-behavior coverage, not ASan memory checks. The host's GCC 13
`libubsan.so` exports UBSan handlers and showed no exported `dlopen` interceptor during read-only inspection,
which does not itself prove the proposed run.

For ASan coverage, use a separate diagnostic Godot built from the pinned engine source with `use_asan=yes`
and a matching compiler/runtime, leaving the official binary untouched. Godot's
[sanitizer instructions](https://docs.godotengine.org/en/4.7/engine_details/development/debugging/using_sanitizers.html)
describe the supported build option. Record that engine's identity and repeat both a loader-path ASan positive
control and the oracle; its results belong to the diagnostic build, not the official-editor gate. A custom
`dlopen` interposer that strips flags would alter symbol resolution and sanitizer interception, so it is not a
supported substitute established by these sources. No UBSan-only or rebuilt-engine check was run for this note.
