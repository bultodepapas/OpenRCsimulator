import sys, wave, numpy as np, glob, os
rows=[]
for p in sorted(sys.argv[1:]):
    w=wave.open(p); n=w.getnframes(); ch=w.getnchannels(); sr=w.getframerate(); sw=w.getsampwidth()
    raw=w.readframes(n)
    a=np.frombuffer(raw,dtype=np.int16 if sw==2 else np.uint8).astype(float)
    a=a.reshape(-1,ch)[:,0]/32768.0
    rms=np.sqrt(np.mean(a**2)); peak=np.max(np.abs(a))
    # seam: jump between last and first sample relative to typical sample-to-sample step
    d=np.abs(np.diff(a)); typ=np.percentile(d,99)
    seam=abs(a[0]-a[-1])
    # level envelope at seam (first/last 50 ms RMS)
    k=int(0.05*sr); e0=np.sqrt(np.mean(a[:k]**2)); e1=np.sqrt(np.mean(a[-k:]**2))
    dc=np.mean(a)
    # dominant frequency
    sp=np.abs(np.fft.rfft(a*np.hanning(len(a)))); f=np.fft.rfftfreq(len(a),1/sr)
    f0=f[np.argmax(sp[1:])+1]
    # spectral centroid
    cen=np.sum(f*sp)/np.sum(sp)
    # slow envelope modulation: 20 ms RMS frames, coefficient of variation
    fr=int(0.02*sr); m=len(a)//fr; env=np.sqrt(np.mean(a[:m*fr].reshape(m,fr)**2,axis=1))
    cv=np.std(env)/max(np.mean(env),1e-9)
    print(f"{os.path.relpath(p,'app/assets/audio'):42s} {sr:6d}Hz ch{ch} {n/sr:6.2f}s rms{20*np.log10(rms+1e-12):6.1f}dB pk{20*np.log10(peak+1e-12):6.1f} dc{dc:+.4f} seam{seam:.4f}/p99step{typ:.4f} edgeRMS{20*np.log10(e0+1e-9):6.1f}/{20*np.log10(e1+1e-9):6.1f} f0 {f0:7.1f} cen {cen:6.0f} envCV {cv:.2f}")
