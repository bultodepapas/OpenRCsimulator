{
  "verified_utc": "2026-11-14T15:28:31.640749+00:00",
  "purpose": "Confirm the delivered fixture projects import and portable launcher reproduces original diagnostic observations",
  "checked_processes": 15,
  "original_baseline_count_unchanged": 845,
  "scope": "Four imports; eight diagnostic scripts; two race writers and one final reader. No baseline/timing rerun or hardware qualification.",
  "checks": [
    {
      "label": "routing-quad_fc",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "7e35f92440e8af7bffcf66eb3012ec11a008c461bb55539d56fdebcfe8044730"
    },
    {
      "label": "profiles-capture_probe",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "071a70b0f5ddebc3bb0a8124334d3e9a0f39b98cea41376c83a4815f0fd1bb5c"
    },
    {
      "label": "hotpath-audit_hotpath",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "d8f0288f77a0b153f95ca31bf56fad8d3db58d17e298930bcbcd7deac5ab077b"
    },
    {
      "label": "import-parent",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "75034796fb30cf6196d00fa49cd1e3a1b16bba34600ad3aa50faa1671532006d"
    },
    {
      "label": "import-profiles",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "a6433a4e4dc679ac5ed762c6a704cd5e46e799ea6ac35757c4266871942fd9a9"
    },
    {
      "label": "calibration-audit_probe",
      "ok": true,
      "errors": 0,
      "warnings": 2,
      "log_sha256": "f7f8d087fad5bc75d8c23c3f4aafe3d3e9e692a43a61dbef718f5ddeee534e52"
    },
    {
      "label": "routing-probe",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "03952485cc33f3168888875c4fffb1e54e33c2c826d4ffd565420fef3f1279bc"
    },
    {
      "label": "import-calibration",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "b7eff4b13dc594bf05431574a69793929f5345870b34061b668c8d5904e08370"
    },
    {
      "label": "routing-airship_pause",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "ea6e99c4de7de5bd9b375797d7007707f8587cef3319406b6a3084eeb776b8e7"
    },
    {
      "label": "profiles-probe",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "ad5aad0cdc4ec9b78c78941bf80b55659772b71ca89f7e9f2d3afe81d5ffcfed"
    },
    {
      "label": "calibration-ui_probe",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "1a4c2ad13e8525dbb46da523b9fdaa649078b6c7988a61f2ebfe4a37fe4af81b"
    },
    {
      "label": "import-routing",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "88bdeb0e03c404c5378adb24a1e7d16a57d4f80a31fe32019a489b62cc987dc7"
    },
    {
      "label": "race-portable-writer-B",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "7721d16607eaefba2f2c3048a8a2d2cdf5c15078aa6486155bf980376ab48a0b"
    },
    {
      "label": "race-portable-final-store",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "10c9edefa50ca44d6f31398ac813f37dbbcea159f4fc87aad2c7f9f3c0153043"
    },
    {
      "label": "race-portable-writer-A",
      "ok": true,
      "errors": 0,
      "warnings": 0,
      "log_sha256": "bc41939ccdcf8b2c7bbf11500e19624b3aeb46b105ed5d4df3aa167d328cdc7f"
    }
  ]
}
