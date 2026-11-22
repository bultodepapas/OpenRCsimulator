#!/usr/bin/env python3
"""Independent equations, not an execution of Godot, for A36-R2 mathematical witnesses."""
import math

def density(height_m):
    t0, p0, lapse, gas, gravity = 288.15, 101325., 0.0065, 287.05287, 9.80665
    t = t0 - lapse * height_m
    return p0 * (t / t0)**(gravity/(gas*lapse)) / (gas*t)

def mul(a,b):
    w,x,y,z = a
    v,i,j,k = b
    return (w*v-x*i-y*j-z*k, w*i+x*v+y*k-z*j,
            w*j-x*k+y*v+z*i, w*k+x*j-y*i+z*v)

def conj(q):
    return (q[0],-q[1],-q[2],-q[3])

def euler(yaw,pitch,roll):
    cy,sy=math.cos(yaw/2),math.sin(yaw/2)
    cp,sp=math.cos(pitch/2),math.sin(pitch/2)
    cr,sr=math.cos(roll/2),math.sin(roll/2)
    return (cr*cp*cy+sr*sp*sy, sr*cp*cy-cr*sp*sy,
            cr*sp*cy+sr*cp*sy, cr*cp*sy-sr*sp*cy)

def rotate(q,v):
    """Independent quaternion product instead of the production scalar rotation."""
    return mul(mul(q,(0.,)+v),conj(q))[1:]

def heading(q):
    nose=rotate(q,(1.,0.,0.))
    horizontal=math.hypot(nose[0],nose[1])
    if horizontal > 0.2:
        return math.atan2(nose[1],nose[0]),horizontal,"nose"
    top=rotate(q,(0.,0.,-1.))
    if nose[2]<0.:
        return math.atan2(-top[1],-top[0]),horizontal,"reversed-top"
    return math.atan2(top[1],top[0]),horizontal,"top"

def angle_error(q):
    h,horiz,branch=heading(q)
    d=mul(conj(q),euler(h,0.,0.))
    sign=-1. if d[0]<0 else 1.
    norm=math.sqrt(sum(v*v for v in d[1:]))
    scale=2.*sign if norm<=1e-9 else sign*2.*math.atan2(norm,sign*d[0])/norm
    return (scale*d[1],scale*d[2]),math.degrees(h),horiz,branch

def main():
    rho0=density(0)
    for h in (500,1000,3000):
        r=density(h)/rho0
        print(f"ISA {h:4d}m density ratio {r:.9f}; nominal 33N physical fixed-rpm thrust {33*r:.6f}N; constant-coefficient hover RPM ratio {1/math.sqrt(r):.6f}")
    r=density(500)/rho0
    assert .95<r<.96 and abs(33-33*r)>1.5
    cases=[]
    for pitch in (78.462,78.464):
        q=euler(0.,math.radians(pitch),math.radians(90.))
        error,h,horiz,branch=angle_error(q)
        cases.append((error,h))
        print(f"pitch={pitch:.3f}deg nose-horizontal={horiz:.9f}, branch={branch}, heading={h:.6f}deg, pre-gain (roll,pitch) error=({error[0]:.9f},{error[1]:.9f})rad")
    jump=abs(cases[1][1]-cases[0][1])
    error_jump=math.hypot(*(cases[1][0][k]-cases[0][0][k] for k in (0,1)))
    print(f"heading jump {jump:.6f}deg / 0.002deg pitch; pre-gain rate-command vector jump {error_jump:.8f}rad")
    assert jump>89.9 and error_jump>1.2
    volume=2.502001
    for h in (1000,3000):
        buoyancy_drop=(rho0-density(h))*volume*9.80665
        print(f"5m constant-volume blimp @ {h}m: ideal ISA buoyancy reduction {buoyancy_drop:.6f}N")
    # An admitted hypothetical 3S custom resistance of 0.5 ohm at full SOC.
    demand=36+36+17.333333333333332+12.083333333333332
    ocv=12.6
    r_pack=0.5
    available=ocv*ocv/(4*r_pack)
    print(f"constructed full-speed airship power request={demand:.6f}W; Thevenin bus max={available:.6f}W; deficit={demand-available:.6f}W")
    assert demand>available
    print("Passed independent arithmetic witnesses; requires original Godot component and accepted-session qualification.")

if __name__=="__main__":
    main()
