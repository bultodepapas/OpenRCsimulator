# GDU-12 native Windows renderer checks

All 16 checked invocations and the collection integrity summarizer passed on the RTX 3090 using official beta2, with zero engine warnings or errors. Lighting segment filtering, skin patterns, path coordinates and lighting policy ran under Compatibility, Forward+ and Mobile. The High profile ran under Forward+; skyline, population gaze and woodland habitat readbacks ran under explicit OpenGL 3 Compatibility. No conditional skip was printed.

Commands requested a 1920×1080 native window. The RGB pixel fixtures explicitly test their 1080p viewports; other tests retain their own internal fixture dimensions. This is desktop renderer correctness evidence, not mobile-device or frame-time qualification. Commands, individual completion counts, diagnostic counts and test hashes are in [verification.json](verification.json); raw reports and logs are retained beside it.
