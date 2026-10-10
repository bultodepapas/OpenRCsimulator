# TOD-01 probe source and evidence

This folder contains the disposable external SceneTree probe and captured evidence for [the TOD-01 report](../../../docs/research/time-of-day-investigations/TOD-01/README.md). The probe imports the production `Atmosphere` and `Spec` scripts but changes no files under `app/`.

Run the commands in the report from the repository root. The legacy capture records the current default app path; the probe records a synthetic matte/specular scene under the current custom sky. Both use Godot 4.7.2 with Compatibility on llvmpipe. See the report for the settle rule, timing caveats and renderer limits. `evidence/SHA256SUMS` binds the probe, pinned engine/source inputs and retained outputs.
