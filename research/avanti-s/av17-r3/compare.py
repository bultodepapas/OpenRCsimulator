"""Check the complete rudder-release matrix and render its before/after traces."""
import argparse
import copy
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    proof = args.evidence
    root = Path(__file__).resolve().parents[3]
    names = ["baseline-240.json", "candidate-240.json", "candidate-480.json"]
    runs = [json.loads((proof/name).read_text(encoding="utf-8")) for name in names]
    for run in runs:
        assert run["completed"] and len(run["cases"]) == 18
        assert all(x["completed"] and x["finite"] and len(x["samples"]) == 280 for x in run["cases"])
        assert all(x["command_opposite"] < 1e-12 and x["rudder_opposite"] < 1e-8 and x["unwanted_command"] == 0 for x in run["cases"])
    before, after, fine = runs
    keys = ["peak_yaw_rate", "return_yaw_rate", "peak_beta", "late_beta", "peak_roll_rate"]
    errors = {k:max(abs(a[k]-b[k]) for a,b in zip(after["cases"],fine["cases"])) for k in keys}
    assert errors["return_yaw_rate"] < 0.1 and errors["peak_beta"] < 0.02
    reductions=[]
    rows=[]
    for old, new in zip(before["cases"],after["cases"]):
        assert (old["speed"],old["yaw"],old["hold_s"]) == (new["speed"],new["yaw"],new["hold_s"])
        reduction=1-abs(new["return_yaw_rate"])/abs(old["return_yaw_rate"])
        reductions.append(reduction)
        rows.append(dict(speed=old["speed"],yaw=old["yaw"],before={k:old[k] for k in keys},
                         after={k:new[k] for k in keys},rebound_reduction_fraction=reduction))
    assert min(reductions)>0.55
    baseline=json.loads((proof/'baseline-aircraft.json').read_text())
    current=json.loads((root/'app/data/aircraft/sebart_avanti_s_a200.json').read_text())
    assert before['data_sha256'] == hashlib.sha256((proof/'baseline-aircraft.json').read_bytes()).hexdigest()
    current_hash = hashlib.sha256((root/'app/data/aircraft/sebart_avanti_s_a200.json').read_bytes()).hexdigest()
    assert after['data_sha256'] == fine['data_sha256'] == current_hash
    assert all((a['speed'],a['yaw'],a['hold_s']) == (b['speed'],b['yaw'],b['hold_s'])
               for a,b in zip(after['cases'],fine['cases']))
    a,b=copy.deepcopy(baseline),copy.deepcopy(current)
    for key in ['Cnp','Cnr']:
        a['aero']['coefficients'].pop(key)
        b['aero']['coefficients'].pop(key)
    for key in ['yaw_scale','yaw_response_time']: b['controls']['gamepad'].pop(key)
    assert a==b
    summary=dict(complete_cases=54,minimum_rebound_reduction_fraction=min(reductions),
                 maximum_rebound_reduction_fraction=max(reductions),max_240_480_difference=errors,
                 all_other_aircraft_values_identical=True,
                 exceptions=['controls.gamepad.yaw_scale','controls.gamepad.yaw_response_time','aero.coefficients.Cnp','aero.coefficients.Cnr'],
                 source_hashes={name:hashlib.sha256((proof/name).read_bytes()).hexdigest() for name in names},cases=rows)
    (proof/'comparison.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig,axes=plt.subplots(3,2,figsize=(10,7.5),sharex=True,constrained_layout=True)
    for col,speed in enumerate([29,45]):
        for run,label,color in [(before,'Before R3','#c84b39'),(after,'R3 integrated','#167995')]:
            row=next(x for x in run['cases'] if x['speed']==speed and x['yaw']==.5)
            for index,(channel,unit) in enumerate([(10,'Actual rudder (deg)'),(5,'Body yaw rate (deg/s)'),(3,'Sideslip (deg)')]):
                axes[index,col].plot([x[0] for x in row['samples']],[x[channel] for x in row['samples']],label=label,color=color)
                axes[index,col].set_ylabel(unit)
                axes[index,col].grid(alpha=.2)
        for ax in axes[:,col]:
            ax.axvspan(.5,1.5,color='#4d6075',alpha=.08)
            ax.set_xlim(0,4)
        axes[0,col].set_title(f'{speed} m/s, raw yaw 50%')
        axes[0,col].legend()
        axes[2,col].set_xlabel('Time (s); release at 1.5 s')
    fig.suptitle('Rudder release — simulated response, not Avanti flight measurements')
    fig.savefig(proof/'rudder-comparison.png',dpi=160)
    print(json.dumps({k:v for k,v in summary.items() if k not in ['cases','source_hashes']},indent=2))


if __name__=='__main__':
    main()
