import importlib.util, json, hashlib
from pathlib import Path
root=Path.cwd(); base=root/'tmp/avanti-pitch-20261110/native-boundaries'
spec=importlib.util.spec_from_file_location('fleet_campaign',root/'research/native-kernel/fleet_campaign.py')
campaign=importlib.util.module_from_spec(spec); spec.loader.exec_module(campaign)
observed=json.loads((base/'pre-observations.json').read_text(encoding='utf-8'))
result=json.loads((base/'fleet-case-results.json').read_text(encoding='utf-8'))
assert result['failures']==[] and len(result['rows'])==2
prior={row['row']['soft_hull']:row for row in observed['rows']}
for row in result['rows']:
    expected=dict(row, expected_refusal_reason=campaign.RUNWAY_START_REASON)
    campaign.validate_refusal(row,expected)
    before=prior[row['soft_hull']]
    for backend in ('reference','native'):
        assert row['startup_proof'][backend] == before[backend]['startup_proof']
component=result['components']['fleet_reference_refusal']
assert component['count']==component['identical']==2
print('AVANTI_FLEET_CONSUMER verdict=pass pairs=2 same_as_pre_observation=2 failures=0')
print('results_sha256',hashlib.sha256((base/'fleet-case-results.json').read_bytes()).hexdigest())
