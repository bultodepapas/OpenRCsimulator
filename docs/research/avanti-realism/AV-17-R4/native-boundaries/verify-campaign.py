import copy, hashlib, importlib.util, json
from pathlib import Path
root = Path.cwd()
spec = importlib.util.spec_from_file_location('fleet_campaign', root/'research/native-kernel/fleet_campaign.py')
campaign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(campaign)
evidence = json.loads((root/'tmp/avanti-pitch-20261110/native-boundaries/pre-observations.json').read_text(encoding='utf-8'))
assert evidence['failures'] == [] and len(evidence['rows']) == 2
negatives = 0
for item in evidence['rows']:
    expected = dict(item['row'], expected_refusal_reason=campaign.RUNWAY_START_REASON)
    actual = dict(expected, status='reference-refused', fingerprint_equal=False, reason=item['reference']['reason'],
                  reference=dict(complete=False, requested='gdscript_reference', phase=item['reference']['phase'], error=item['reference']['reason']),
                  native=dict(complete=False, requested='native', phase=item['native']['phase'], error=item['native']['reason']),
                  startup_proof={k: item[k]['startup_proof'] for k in ('reference', 'native')})
    campaign.validate_refusal(actual, expected)
    for field in ('frame', 'config', 'outcome', 'live_config'):
        forged = copy.deepcopy(actual)
        for proof in forged['startup_proof'].values():
            proof[field + '_bytes_hex'] = '00'
            proof[field + '_sha256'] = hashlib.sha256(b'\0').hexdigest()
            if field == 'frame': proof['before_frame_bytes_hex'] = '00'
            if field == 'live_config': proof['before_live_config_bytes_hex'] = '00'
        try:
            campaign.validate_refusal(forged, expected)
        except campaign.CampaignError:
            negatives += 1
        else:
            raise AssertionError('Coherently forged payload accepted: '+field)
    old = copy.deepcopy(actual)
    for proof in old['startup_proof'].values():
        proof['aircraft_sha256'] = campaign.AVANTI_RUNWAY_V4_HISTORICAL['aircraft_sha256']
    try:
        campaign.validate_refusal(old, expected)
    except campaign.CampaignError:
        negatives += 1
    else:
        raise AssertionError('Historical identity accepted')
print(f'CAMPAIGN_CAPTURE_VERIFY verdict=pass pairs={len(evidence["rows"])} negative_checks={negatives} failures=0')
