import sys, wave, numpy as np, os
for p in sys.argv[1:]:
    w=wave.open(p); sr=w.getframerate(); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(float)/32768
    n=len(a); t=np.concatenate([a,a])
    # second difference = click sensitivity
    d2=np.abs(np.diff(t,2))
    win=int(0.002*sr)
    seam=d2[n-win:n+win].max()
    # distribution of the same window max elsewhere
    idx=np.arange(win, n-win, win)
    others=np.array([d2[i-win:i+win].max() for i in idx])
    pct=(others<seam).mean()*100
    print(f"{os.path.basename(p):24s} seam d2 {seam:.4f}  median {np.median(others):.4f}  p99 {np.percentile(others,99):.4f}  seam rank {pct:5.1f}%  ratio {seam/np.median(others):.1f}x")
