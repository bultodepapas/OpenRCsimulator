# Interface languages

The game offers **English**, **Español**, **简体中文** (Simplified Chinese,
`zh_Hans`), **Português (Brasil)** (`pt_BR`), **Deutsch** (`de`), **Français** (`fr`), **Italiano** (`it`), **Русский** (`ru`), and **日本語** (`ja`), in that order. English remains the source and first-run default.
Home cycles through the nine choices; Settings → Interface lists them directly.
Selection updates open screens immediately and is saved for the next interactive
launch, including the startup screen. Technical command-line routes retain their
English-only, preference-independent behavior.

## Maintenance

- `languages.gd` owns codes and native names. Preferences, startup, Home and Settings
  share it. Preserve script subtags: `zh_Hans` must not be reduced to `zh`.
- `es.po` contains the source-message inventory. Chinese, Portuguese, German,
  French, Italian, Russian and Japanese use separate catalogs. Add new user-facing
  messages to every catalog; see the dated verification sections for coverage gaps.
  English text stays in code and `msgid`; translate complete `msgstr` sentences,
  not fragments. Do not copy repeated source IDs into new catalogs.
- Preserve formatting arguments, their order, BBCode, file/URL identifiers,
  aircraft/product names and control/key identifiers. Chinese and Japanese each have one plural form.
- `project.godot` registers the catalogs. Verify glyph coverage in the existing
  or a bundled font, with corresponding layout/interaction checks.
- `fonts.gd` adds [Noto Sans CJK SC](../assets/fonts/README.md) to the engine font
  while Chinese is active, and removes it when returning to a Latin-script language.
  This preserves the existing Latin layout metrics. The language dropdown has
  its own multilingual font so the Chinese option is readable in every locale.
  Fonts and translations are local resources; no online translation is used.

Terminology: throttle 油门; roll 横滚; pitch 俯仰; yaw 偏航; aileron 副翼;
elevator 升降舵; rudder 方向舵; aerodynamic stall 失速; trim 微调;
controller 控制器; transmitter 遥控器; Workshop 工坊. Arming is 解锁,
not a claim that the motor starts. Preserve the experimental/validation caveats.

## Portuguese wording (UI-01f)

The `pt_BR` catalog uses Brazilian spelling and familiar interface terms
(`Configurações`, `Salvar`, `controle`, `trem de pouso`) with clear wording and
no unnecessary slang. It is selectable by Portuguese speakers everywhere;
there is no separate European Portuguese catalog or automatic region switch.
The existing first-run English default remains unchanged.

Keep technical terms consistent: throttle **acelerador**, pitch **arfagem**,
roll **rolagem**, yaw **guinada**, elevator **profundor**, rudder **leme**,
stall **estol**, trim **trimagem**, transmitter **transmissor**, Workshop
**Oficina**. Arming enables the motor; it does not mean starting it. Proper
names, keyboard/button labels, units and experimental caveats remain intact.
The original Latin font covers Portuguese accents; no font dependency is added.

Brazilian gettext uses `nplurals=2; plural=(n > 1);`, following the
[GNU gettext plural rules](https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html).
The current catalog has no plural-message entries.

## German wording (UI-01g)

The shared `de` catalog uses standard German, concise UI labels and consistent
informal instructions. Native selection is **Deutsch**. Region-qualified German
locale names resolve to that language; the first-run English default is unchanged.

Use established RC terms: **Gas**, **Querruder**, **Höhenruder**, **Seitenruder**,
**Trimmung**, **Fahrwerk**, **Strömungsabriss** and **Sender**. Distinguish
**Scharfschalten** (arming) from starting a motor or rotor. Keep physical key
identifiers and model names intact while translating descriptive key names.
The original Latin font is used for German; no new font download is required.

## French wording (UI-01h)

The shared `fr` catalog uses standard French and consistent polite imperative
instructions. **Français** is the sixth option. Regional French locale names
resolve to it; there are no separate regional catalogs or automatic changes to
the first-run English default.

Keep RC terminology consistent: **gaz**, **roulis**, **tangage**, **lacet**,
**aileron**, **gouverne de profondeur**, **gouverne de direction**, **décrochage**,
**radiocommande**, **manette** and **Atelier**. Rotor pitch is **pas**, with
**pas collectif** and **pas cyclique** distinct from aircraft pitch attitude.
Arming (**armer**) enables operation; it does not start the motor or rotor.
Preserve model names, physical input identifiers, units and experimental caveats.
The original Latin font supplies the accents and ligatures.

## Italian wording (UI-01i)

The shared `it` catalog uses standard Italian with consistent informal imperative
instructions. **Italiano** is the seventh option; `it_IT` and `it_CH` resolve to it.
English remains the first-run default. Keep RC terms consistent: **gas**, **rollio**,
**beccheggio**, **imbardata**, **alettone**, **elevatore**, **timone**, **stallo**,
**trasmittente** and **Officina**. Rotor blade pitch is **passo**, distinct from
pitch attitude. Arming (**armare**) and motor locking do not mean rotor startup.
The original Latin font supplies Italian accented letters.

## Russian wording (UI-01j)

The shared `ru` catalog uses standard Russian and consistent polite instructions.
**Русский** is the eighth option; regional Russian locale names resolve to it.
English remains the first-run default. Keep RC terminology consistent: **газ**,
**крен**, **тангаж**, **рыскание**, **элерон**, **руль высоты**, **руль направления**,
**срыв потока**, **передатчик**, **геймпад** and **расходы** (control travel).
Rotor blade pitch is **шаг**; motor locking, permission to start and actual rotor
startup are distinct states. Preserve physical Latin key labels even when a
Cyrillic letter looks similar. The original font covers the Russian alphabet;
no new font dependency or CJK fallback is required.

## Japanese wording (UI-01k)

**日本語** (`ja`) is the ninth option; `ja_JP` resolves to it. Use concise standard
Japanese with natural kana and kanji, and polite instructions. Keep RC vocabulary
consistent: **スロットル**, **ロール**, **ピッチ**, **ヨー**, **エルロン**,
**エレベーター**, **ラダー**, **失速**, **送信機** and **舵角**. Distinguish
collective blade pitch from aircraft pitch attitude, and arming permission from
actual rotor startup. Preserve physical Latin key labels, units and model names.
The bundled Noto Sans CJK JP font provides Japanese glyph forms; switching back
to Chinese restores SC forms and Latin languages retain the original font.

## UI-01e verification — 2026-10-26

`test_ui_language.gd` covers all catalog keys, nonempty translations, ordered
format arguments, bundled Chinese glyphs, region/script handling, the three-step
Home cycle, Chinese persistence after rebuilding the app, font restoration and
unchanged direct-route preferences. `test_ui_settings_integration.gd` exercises
the third option with real keyboard events, immediate open-screen refresh,
saving, and return to Spanish. Both pass. `test_brand_startup.gd` passes,
including the Chinese read-only startup preference.

`test_ui_home_layout.gd` passes for all three languages and all eleven catalog
entries, including 1080p, 720p and the existing 200% text checks. The modal matrix checks 1,008 cases: all 336 Chinese cases pass. Its three
Spanish Workshop failures at 200% text and 960×540, 1024×576 and 1024×768 logical
viewports reproduce in the pre-change baseline (672 cases, the same three
failures). No new modal failure remains. Pause geometry passes 627 checks across
all three languages.
The full simulator suite was not run for this presentation-only change.

The font was imported and exercised without an existing import cache in a
minimal fixture populated from a fresh sparse clone plus the candidate files.
Catalog lookup, CJK glyphs, license presence and live fallback restoration passed.
Translation review corrected the arming instructions and full-rudder wording.
These checks are software evidence, not native-speaker certification or physical
flight validation. Screenshots and disposable checks stay in ignored `tmp/ui-zh/`.

Native X11 captures were reviewed at 1920×1080, 2560×1440 and 1280×720.
Home and Settings render Chinese text and the language menu exposes all three
native names, including when the surrounding interface is English. A restart
with the same isolated profile restores Chinese. Flight overlays, keyboard
help and wind/telemetry labels were also inspected in Chinese during a paused
flight. This is layout evidence, not hardware performance qualification.

A Linux export pack was built through the existing preset and loaded by the
pinned engine. A runtime probe verified Chinese translations, glyph coverage,
font activation/restoration and the included OFL license from the pack. No new
public installer/release was published. The static skill linter reports no new
diagnostics relative to its baseline; the Godot checked runners are the parse
and runtime authority for these changes.

## UI-01f verification — 2026-10-26

Added all 2,439 source messages in Brazilian Portuguese, including setup,
calibration, flight overlays, Workshop and failure messages. Key/placeholder/
markup parity checks pass. Review clarified helicopter throttle-cut latching,
rotor startup and calibration persistence, and translated descriptive key names.
Physical key identifiers, units and product names remain unchanged.

The language, Settings integration and startup tests pass for the fourth option,
immediate updates, saved `pt_BR` selection and return through the full language
cycle. The original font covers the Portuguese accents; switching from Chinese
to Portuguese restores the Latin font behavior.

Home layout passes across all four languages and eleven aircraft, including
1080p, 720p and 200% text. Compact windows with enlarged text now keep navigation
inside the scroll area so the selected page retains usable space. The advanced
control-surface toggle in Workshop wraps instead of forcing a wide panel. The
modal matrix now passes all **1,344 cases** across four languages (including the
three Spanish cases recorded under UI-01e); Pause passes **832 checks**.

Native Home and Settings were reviewed at 1920×1080 and 1280×720; Home and
Workshop were also inspected at 720p with 200% text. Restarting the isolated
profile restores Portuguese. The existing Linux preset exports the new catalog;
a runtime probe loaded that pack and checked every Portuguese message, accented
glyphs, locale selection and the absence of an unnecessary CJK fallback.

No new font, external translation service or public installer/release was added.
The static skill linter reports no new diagnostics relative to the pre-change
baseline. The full simulator suite was not run. Evidence logs, captures and the
export hash stay under ignored `tmp/ui-pt/`; the large temporary pack is disposable.

## UI-01g verification — 2026-10-26

All 2,439 source messages have German translations. Key, ordered format-argument
and markup parity checks pass. Review clarified rotor startup, throttle-cut
latching and calibration persistence. Graphics labels and the disconnected-radio
message use concise wording that retains their meaning.

Language, Settings integration and startup tests pass: fifth-option selection,
immediate translation, saved `de`, restart persistence, regional locale handling,
German glyph coverage and the full five-language cycle. Home layout passes for
all five languages and eleven aircraft at 1080p, 720p and enlarged text. Compact
Home utility labels use an 18-pixel base font to fit without clipping; normal
1080p and enlarged-text sizing retain their existing behavior. The modal matrix
passes **1,680 cases**, and Pause passes **1,037 checks**.

Native X11 captures cover German Home and Settings at 1920×1080 and Home at
1280×720, including 200% text. Restarting the isolated profile retains German.
The 1080p captures show intermittent malformed glyphs in some controls, also
reproduced after switching to English in the same session; this is an unresolved
rendering observation, not missing German glyph coverage or a passed visual
rendering qualification. The compact Home captures render the labels correctly.

The Linux export preset includes the German catalog. A runtime probe loaded the
pack and verified all messages, German glyphs and the original Latin font behavior.
The export used manual build metadata; no public installer or release was published.
Static lint adds no diagnostics relative to the baseline. The full simulator
suite was not run. Logs, native captures and the export hash remain in ignored
`tmp/ui-de/`; the temporary large pack was removed after verification.

## UI-01h verification — 2026-10-26

French covers all 2,439 source messages. Key, nonempty-value, ordered format-
argument and markup parity checks pass. Review clarified helicopter motor locking
and rotor startup, preserved physical key identifiers, and shortened the radio
disconnect warning without dropping the safe-state or recovery instructions.
The labels **Heure**, **Exercices**, **Conserver** and **Réinitialiser les graphismes**
keep compact and enlarged-text layouts usable.

Language, Settings integration and startup tests pass for sixth-option selection,
immediate updates, persistence, regional French names and the six-language cycle.
French accents and ligatures are covered by the original Latin font. The unsupported-
language test now uses `zz`, because `fr` is supported. Home layout passes across
all six languages and eleven aircraft, including 1080p, 720p and 200% text.
The modal matrix passes **2,016 cases**; Pause passes **1,242 checks**.

Native Home and Settings were reviewed at 1920×1080 and 1280×720, including
200% text at 720p. Restarting the isolated profile retains French. The 1080p
Settings capture still shows the malformed-glyph observation recorded under
UI-01g; these checks do not establish rendering or hardware qualification.
One direct bridge stop interrupted Home preparation and reported worker/resource
shutdown errors. A repeat through Home's normal Quit action drained preparation
and exited with no crash or leaked objects. The software-rendered X11 session
also reports its driver limitation when setting VSync.

The existing Linux export preset includes the catalog. A runtime probe loaded
the pack and checked every French message, accented glyphs and Latin font behavior.
The manual-build metadata warning is expected for this local smoke export.
Static lint adds no diagnostics; the full simulator suite was not run. No new
font, external translation service or public installer/release was added.
Evidence stays in ignored `tmp/ui-fr/`; the export hash is retained and the
temporary large pack is removed after verification.

## UI-01i verification — 2026-10-26

Italian covers all 2,439 source messages with nonempty translations and matching
keys, ordered format arguments, markup and explicit line breaks. Review aligned
control-travel terminology (**corse**) and distinguished motor locking, arming,
rotor startup and governed speed. Concise labels and status messages fit the
existing layout without further runtime UI changes.

Language, Settings integration and startup tests pass for seventh-option selection,
immediate updates, saved `it`, restart persistence, regional locale names and
Italian accents. Home layout passes for all seven languages and eleven aircraft,
including 1080p, 720p and 200% text. The modal matrix passes **2,352 cases** and
Pause passes **1,447 checks**. Static lint adds no diagnostics relative to the
pre-change baseline; the full simulator suite was not run.

Native Home and Settings were inspected at 1920×1080 with normal and 200% text,
then at 1280×720 with 200% text. The same isolated profile restores Italian.
The malformed-glyph observation from UI-01g remains visible in some 1080p
Settings controls; glyph coverage and geometry checks do not establish rendering
qualification. Both sessions exited through Home's Quit action without crashes
or leaked objects. The X11 software driver reports its existing VSync limitation.

The Linux preset exports the catalog. A runtime probe loaded the pack and checked
all Italian messages, accented glyphs and original Latin font behavior. Manual
build metadata is the expected export warning. No new font, translation service
or public installer/release was added. Logs, captures and the export hash remain
under ignored `tmp/ui-it/`; the temporary large pack was removed after checking.

## UI-01j verification — 2026-10-26

Russian covers all **2,461** current source messages, including 22 stock-lighting
messages added to Spanish during this work. Exact keys, nonempty values, ordered
format arguments, markup, named arguments and explicit line breaks pass. The
packaged catalog and every Russian Cyrillic character use the original font.

Russian language checks pass for eighth-option selection, immediate updates,
saved `ru`, restart persistence, regional locales and glyph coverage. Settings
integration and startup tests pass. The final full language suite reports five
coverage failures: Chinese, Portuguese, German, French and Italian still lack the
22 concurrent stock-lighting messages. The suite passed before that inventory
change; its remaining failures do not concern Russian.

Home layout passes across eight languages and eleven aircraft, including 1080p,
720p and 200% text. Long utility labels now wrap as whole buttons; the advanced
control-surface toggle in Workshop wraps text instead of widening the panel.
Concise Russian Pause and graphics labels preserve their meaning and format
arguments. Pause passes **1,652 checks**. The final responsive modal matrix
passes **2,688 cases** across all eight languages.

The additional legacy `test_ui_home.gd` run reports 51 failed layout assertions.
A disposable overlay restoring only the former utility HBox reproduces the same
51 assertion labels, including compact-scroll and enlarged-navigation expectations.
Those existing failures remain unresolved; this is not a full-suite pass. Static
lint adds no diagnostics in the localization changes. The final whole-tree scan
also sees one new unrelated missing-fixture warning in `test_field_replacement.gd`.

Native Russian Home and Settings were inspected at 1920×1080. Restarting the same
isolated profile retains Russian; the final Home capture shows full utility labels
on two rows. The malformed-glyph observation from UI-01g remains in some native
Settings controls, so geometry and font coverage do not establish rendering
qualification. Both native sessions exited through Home's Quit action without
crashes or leaked objects.

The Linux preset exports successfully, and a runtime probe loads all 2,461 Russian
messages and checks Cyrillic coverage from that pack. A disk-space failure during
an earlier export was resolved by writing the temporary pack to shared memory.
Manual build metadata remains the expected export warning. No public installer or
release was produced. Logs, captures and the pack hash are in ignored `tmp/ui-ru/`;
the large temporary pack was removed after verification.


## UI-01k verification — 2026-10-26

Japanese covers all **2,461** source messages with nonempty translations and exact
keys, ordered format arguments, markup, named arguments and explicit line breaks.
Review distinguishes arming from rotor startup and preserves physical Latin key
labels. Concise Pause, next-flight and Settings-preview labels fit enlarged text;
Workshop uses **工房** consistently.

Japanese language checks pass for ninth-option selection, immediate updates,
saved `ja`, restart persistence, regional locale names and all non-ASCII catalog
glyphs. Font switching checks cover Japanese → Chinese → English, using the JP
and SC variants exclusively and restoring the original Latin font. Settings
integration and startup checks pass. The whole language suite still reports four
coverage failures: Portuguese, German, French and Italian lack the 22 stock-lighting
messages recorded under UI-01j; Japanese and Chinese cover the current inventory.

Home layout passes for all nine languages and eleven aircraft, including 1080p,
720p and 200% text. The final modal matrix passes **3,024 cases** across all nine
languages. Pause passes **1,857 checks**. Static lint adds no diagnostics
relative to the starting tree. The full simulator suite and the legacy Home test
with the known failures recorded under UI-01j were not rerun.

Native Home and Settings were inspected at 1920×1080 with normal and 200% text.
The captured Japanese glyphs render legibly, and the restarted isolated profile
retains Japanese. Both sessions exited through Home's Quit action without crashes
or leaked objects. This is software layout evidence, not performance qualification
or a claim that the earlier general rendering observation is resolved.

The Linux preset exports the full catalog, Noto Sans CJK JP 2.004 and the shared
OFL license. A runtime pack probe checks every translated message and non-ASCII
glyph, disabled system-font fallback, and Japanese/Chinese/English font switching.
The export uses manual build metadata; no new public installer or release was
published. Logs, captures and the export hash remain under ignored `tmp/ui-ja/`;
the large temporary pack was removed after verification.
