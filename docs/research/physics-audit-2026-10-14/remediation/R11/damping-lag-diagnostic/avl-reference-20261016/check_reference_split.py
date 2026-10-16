"""Check the existing D11f reference's actual profile/circulation derivative split."""
import contextlib
import importlib.util
import io
import json
import math
from pathlib import Path

source = Path('C:/DEVELOPMENT/OpenRCsimulator/research/aero/d11f/wing_yaw_damping.py')
spec = importlib.util.spec_from_file_location('d11f', source)
model = importlib.util.module_from_spec(spec)
with contextlib.redirect_stdout(io.StringIO()):
    spec.loader.exec_module(model)

result = []
for degree in [0, 4, 11]:
    alpha, h = math.radians(degree), 0.05
    row = {'alpha_deg': degree}
    for label, cd0 in [('total', 0.0434), ('circulatory', 0.0)]:
        model.CD0 = cd0
        derivative = (model.loads(alpha, h)[1] - model.loads(alpha, -h)[1]) / (2*h)
        row[label + '_cnr'] = derivative / (model.qS * model.b**2 / (2*model.V))
    row['profile_cnr'] = row['total_cnr'] - row['circulatory_cnr']
    row['analytic_profile_cnr'] = -0.0434 / 3 * (1 - 1/(4*model.n_side**2)) * math.cos(alpha)
    row['profile_error'] = row['profile_cnr'] - row['analytic_profile_cnr']
    result.append(row)
output = Path(__file__).with_suffix('.json')
output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, indent=2))
