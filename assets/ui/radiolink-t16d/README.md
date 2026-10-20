# Radiolink T16D front photo

`front-original.png` is the transparent frontal product image from Radiolink's [official T16D page](https://radiolink.com.cn/t16d), downloaded on 2026-10-20 from `https://radiolink.com.cn/e8b4a443654e2c42fa2ad87f2fa7ba22.png` (1092 × 1245 pixels). Copyright Radiolink Electronic Limited. The project owner states that Radiolink has granted permission to use its imagery in this simulator; this is not a general-purpose license grant.

Install `tools/ui/requirements.txt`, then run `python tools/ui/build_radiolink_t16d_overlay.py` to reproduce `app/assets/ui/radiolink_t16d.png`. The source already has transparency and a blank LCD. The build trims its transparent border and scales it; the flight overlay adds live sticks and display values.
