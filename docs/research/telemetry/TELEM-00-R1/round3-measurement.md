# Telemetry follow-up: unconventional investigations F21–F24

Research date: 2026-11-18; baseline commit `48ae3016a655acf7d062da3f32d72b9050c9e59a`. Each investigation inspected an original non-English project document, translation resource, or issue and separately checked relevant implementation or official documentation. Localized text establishes what the text says, not by itself what a particular build executes. Moving `master`, `stable`, and `4.x` pages are not pinned release evidence. No researched application or diagnostic tool was installed or executed, and no export, capture or privacy UI was run.

**Search-method correction.** Six discovery queries accidentally included non-English literal search terms, contrary to the English-only instruction: three in OBS research and three in Fcitx research. Their exact submitted text is recorded below with those terms represented by Unicode escapes; decoding the escapes reproduces the original queries:

1. `site:github.com/obsproject/obs-studio/blob/master/frontend/data/locale/pt-BR.ini "\u0072\u0065\u0067\u0069\u0073\u0074\u0072\u006f"`
2. `site:github.com/obsproject/obs-studio "LogUploadDialog.Title" "Portugu\u00eas"`
3. `site:obsproject.com/forum "\u0072\u0065\u0067\u0069\u0073\u0074\u0072\u006f" "\u0063\u0061\u0072\u0072\u0065\u0067\u0061\u0072" "\u0070\u0072\u0069\u0076\u0061\u0063\u0069\u0064\u0061\u0064\u0065"`
4. `site:github.com/fcitx/fcitx5 "\u5f53\u524d\u7528\u6237" "System Info"`
5. `site:github.com/fcitx/fcitx5 "\u8bca\u65ad" "\u654f\u611f" fcitx5-diagnose Chinese translation`
6. `site:fcitx-im.org/wiki "fcitx5-diagnose" "\u654f\u611f"`

Those discovery results were discarded. All retained OBS and Fcitx evidence was rediscovered using English queries recorded in F21 and F24 and independently reopened. This correction is part of the four investigations, not an additional investigation.

<a id="f21"></a>

## F21 — OBS Studio, Brazilian Portuguese: viewing and sharing a diagnostic log

**Question.** Does a user-facing instruction to inspect a log establish that the log is suitable to upload without reviewing the actual contents?

**Exact English rediscovery queries.** `OBS Studio official Portuguese log file upload sensitive information privacy current logs support`; `site:github.com/obsproject/obs-studio/blob/master/plugins/obs-ffmpeg/data/locale/pt-BR.ini encoder fallback log file`; `site:github.com/obsproject/obs-studio/issues/3434 privacy log upload confirmation`; `site:github.com/obsproject/obs-studio/pull/11943 crash log confirmation upload`; `site:obsproject.com/forum/threads/static-like-screen-showing-up.13930 moderator removed sensitive username password`.

**Inspected primary sources.** OBS's [Brazilian Portuguese FFmpeg locale](https://github.com/obsproject/obs-studio/blob/master/plugins/obs-ffmpeg/data/locale/pt-BR.ini), moving `master`; [English UI strings](https://github.com/obsproject/obs-studio/blob/master/frontend/data/locale/en-US.ini), moving `master`; [issue #3434](https://github.com/obsproject/obs-studio/issues/3434), opened 2020 and closed 2025 by [merged PR #11943](https://github.com/obsproject/obs-studio/pull/11943); and a [2014 OBS support thread](https://obsproject.com/forum/threads/static-like-screen-showing-up.13930/). Accessed 2026-11-18.

**Observation.** The Portuguese locale's AV1 failure text directs the user to log files for details; it does not itself describe a sharing operation. English UI resources separately name viewing and uploading logs. The 2020 issue reported immediate upload in OBS 25.0.8; its later history says a 2025 change added confirmation and a privacy-policy link. The merged PR also describes an opt-in checkbox for upload of a most-recent crash report after an unclean shutdown, with Windows/macOS differences. A forum moderator in 2014 reported removing credentials from a shared log; that is a historical incident involving OBS 0.622b, not proof of present OBS behavior.

**Inference and transfer limit.** A useful local log, an upload confirmation, and a reviewed payload are different protections. OBS's UI strings alone do not prove mandatory content preview, exact current defaults, or deletion behavior. Its crash workflow is not the proposed OpenRC base telemetry.

**Proposed plan/test change.** Keep manual OpenRC issue submission separate: show the precise sanitized artifact and public destination before the player independently attaches it. Test a synthetic username/path/secret in diagnostic inputs, plus cancel and edit-after-preview cases; ensure the reviewed bytes are the bytes exported and never auto-attach the raw diagnostics archive. A future crash-report design must have its own notice, consent, and cache tests.

**Follow-up lead.** Check whether changing an exported file after preview can make a claimed preview stale; specify how the user re-reviews it.

<a id="f22"></a>

## F22 — Godot, Japanese: focus and readable consent under expansion

**Question.** Does a localized consent dialog with two visible buttons necessarily offer equivalent keyboard/controller access when text grows or the banner changes?

**Exact English discovery queries.** `Godot Japanese documentation pseudo localization accessibility focus translated text UI scaling official`; `site:docs.godotengine.org/ja/4.4 "focus" keyboard control accessibility Japanese documentation`; `site:docs.godotengine.org/en/stable/tutorials/ui/custom_gui_controls.html focus indicator custom minimum size`.

**Inspected primary sources.** Godot's [Japanese custom GUI controls tutorial](https://docs.godotengine.org/ja/4.x/tutorials/ui/custom_gui_controls.html), 4.x moving branch; its [English counterpart](https://docs.godotengine.org/en/stable/tutorials/ui/custom_gui_controls.html), [English navigation documentation for 4.4](https://docs.godotengine.org/en/4.4/tutorials/ui/gui_navigation.html), and [internationalization guidance](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html). The Japanese pseudolocalization page inspected largely falls back to English, so the Japanese source relied on here is the translated custom-controls discussion. Accessed 2026-11-18.

**Observation.** The Japanese tutorial describes focus support, a visible focus indicator and minimum sizing for custom controls; the English source corroborates those points. The navigation guide describes explicit focus neighbors and warns that focus can be lost when a control is hidden. Godot's English internationalization guidance recommends pseudolocalization for overflow and explicitly notes that it does not qualify CJK or right-to-left fonts.

**Inference and transfer limit.** A translated label or a pseudolocalized screenshot cannot establish real screen-reader announcements, controller focus, or the behavior of the exact 4.8-beta2 export. Japanese localization does not imply OpenRC promises Japanese support; EN/ES remain its planned supported languages.

**Proposed plan/test change.** In the future exported consent UI, run EN, ES, and an expansion fixture at 1080p first and at larger UI/text scales. Traverse both actions using keyboard and controller, verify visible focus and logical order, and test held input when the banner appears, focus entry before dismissal, large-text scrolling, back/close remaining off, and screen-reader names with an actual assistive technology. Track rendered action bounds and ensure both remain reachable. Separately test real glyph coverage only for languages actually supported.

**Follow-up lead.** Qualify whether the pinned beta's focus restoration and screen-reader path remain correct after the notice is dismissed or reopened.

<a id="f23"></a>

## F23 — GIMP, Spanish: targeted issue material differs from performance logs

**Question.** Does a useful performance report have the same data scope as an ordinary usage summary or a manually written bug description?

**Exact English discovery queries.** `GIMP official Spanish manual report bug debug crash output logs personal data`; `site:docs.gimp.org/2.10/es/gimp-bug-report.html bug report`; `site:docs.gimp.org/2.10/es/gimp-bug-report.html screenshots files attachments useful`.

**Inspected primary sources.** GIMP's [Spanish 2.10 bug-report manual](https://docs.gimp.org/2.10/es/gimp-bug-report.html), its [English counterpart](https://docs.gimp.org/2.10/en/gimp-bug-report.html), and the GIMP developers' [performance-log guide](https://developer.gimp.org/core/debug/performance-logs/), accessed 2026-11-18. The Spanish manual is a versioned historical guide; the English developer guide describes GIMP 2.10.8 and later, not an OpenRC feature.

**Observation.** The Spanish manual requests a useful issue description and recommends attaching files only where helpful; it notes reports can remain available for years, in a discussion of resource use. Separately, GIMP's developer guide describes deliberately recorded performance logs with periodic state samples and, on supported platforms, backtraces. It also says logs include values of variables prefixed `GIMP_`, `GEGL_`, and `BABL_`. Nothing in this comparison establishes GIMP's ordinary telemetry policy or that all attachments contain secrets.

**Inference and transfer limit.** “Performance data” can mean a much wider diagnostic artifact than OpenRC's finite interval histogram. A public issue is a different exposure surface from a short-lived private receiver. The privacy consequence of long-lived public material is this project's inference, not a claim that the Spanish manual intended it as a privacy warning.

**Proposed plan/test change.** For OpenRC's future manual report, allow deliberate selection of a minimal scenario description and bounded approved summaries. Use synthetic environment variables, paths, process names, markers and stack text as canaries; assert they are absent from the exact exported/previewed artifact unless a separately designed diagnostic route explicitly permits them. Canceling preview must create no remote request. Maintain an independently stated opt-in and retention decision for any future backtrace or raw-trace feature.

**Follow-up lead.** Assess whether each proposed manual field has a demonstrated debugging purpose before adding a broader local export.

<a id="f24"></a>

## F24 — Fcitx, Chinese: a warning can travel with an unreviewed dump

**Question.** Does a localized warning to review diagnostics before posting prove that the actual submitted report has been reviewed and minimized?

**Exact English rediscovery queries.** `site:github.com/fcitx/fcitx5-chinese-addons/issues/89 fcitx5 diagnose output warning sensitive information distribution`; `site:github.com/fcitx/fcitx5/blob/master/po/zh_CN.po fcitx5-diagnose current user debug information`; `site:fcitx-im.org wiki Chinese version fcitx5 diagnose troubleshooting sensitive information`; `site:github.com/fcitx/fcitx5-chinese-addons/issues/89 diagnose warning user report`.

**Inspected primary sources.** The original [Chinese-language Fcitx issue #89](https://github.com/fcitx/fcitx5-chinese-addons/issues/89), opened 2022 on Linux Mint 20.3; the project's [Chinese translation catalog](https://github.com/fcitx/fcitx5/blob/master/po/zh_CN.po); current moving-master [`fcitx5-diagnose.sh`](https://github.com/fcitx/fcitx5/blob/master/data/fcitx5-diagnose.sh); and the official [troubleshooting page](https://fcitx-im.org/wiki/Troubleshooting). All retained sources were rediscovered using English queries and reopened on 2026-11-18.

**Observation.** In the Chinese issue, a user posts a large diagnostic transcript that includes the tool's Chinese warning about potentially sensitive details and checking before public sharing. The project troubleshooting page independently lists possible username, distribution, date/time and connected-application information. The inspected script includes output of the current username/UID and configuration-directory information and, when run as root, selected sudo environment values. Which fields appear depends on the system and invocation.

**Inference and transfer limit.** The visible warning does not demonstrate that review occurred or that the poster understood it; the issue is one historical case, not evidence of their intent, a general user failure rate, or current OpenRC behavior. Translation strings alone do not establish collection; the separate script and official documentation provide that evidence.

**Proposed plan/test change.** Do not repurpose whole local diagnostics as the manual telemetry export. Construct a small typed allowlist from synthetic inputs; show the complete exact result before copying; explicitly label public sharing and account identity; verify adversarial canaries placed in usernames, paths, environment values, exception strings and arbitrary extra keys cannot appear through fallback or error messages. A free-text warning supplements that test and preview; it does not replace either. Keep all future raw report sharing a distinct, deliberate workflow.

**Follow-up lead.** Examine error and unsupported-platform fallbacks for accidental raw-object serialization when a safe classifier returns unknown.
