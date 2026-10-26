# Bundled interface font

UI-01e adds **Noto Sans CJK SC Regular 2.004**, unmodified, from the official
[Noto CJK Sans2.004 release](https://github.com/notofonts/noto-cjk/tree/Sans2.004).

- File: `NotoSansCJKsc-Regular.otf` (16,437,364 bytes).
- [Exact source](https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf).
- SHA-256: `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b`.
- License: [SIL Open Font License 1.1](OFL-NotoSansCJK.txt), included by every export preset. Copyright notices remain embedded in the original font.

`i18n/fonts.gd` installs it as a fallback on the engine's existing font before
startup. Latin text keeps Godot's original Open Sans face and metrics. The full
font is retained for Chinese names entered by players; no runtime download or
system CJK installation is required. The CJK import disables system fallback,
and the language regression checks every Chinese character in the catalog
against this bundled font. Import with the project's normal Godot import step.
