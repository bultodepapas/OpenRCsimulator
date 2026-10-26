from pathlib import Path
import json, statistics

work = Path(__file__).resolve().parent
names = ['pinned-a1', 'pinned-b1', 'pinned-b2', 'pinned-a2']
reports = {name: json.loads((work/(name+'.json')).read_text()) for name in names}
rows = []
for aircraft_index, aircraft in enumerate(reports['pinned-a1']['aircraft']):
    for case_index, case in enumerate(aircraft['cases']):
        cases = {name: report['aircraft'][aircraft_index]['cases'][case_index] for name, report in reports.items()}
        for current in cases.values():
            for key in ['case_id', 'weather_configuration', 'setup_start_state', 'queries_per_accepted_tick_untimed', 'final_state_sha256_per_batch']:
                assert current[key] == case[key], (aircraft['id'], key)
            assert current['accepted_timed_ticks'] == 1440 and current['accepted_warmup_ticks'] == 720
            assert current['reset_checks_passed'] == current['reset_checks_expected'] == 8
            assert current['final_states_repeatable']
        before = [v for name in ['pinned-a1','pinned-a2'] for v in cases[name]['samples_us_per_tick']]
        after = [v for name in ['pinned-b1','pinned-b2'] for v in cases[name]['samples_us_per_tick']]
        a, b = statistics.median(before), statistics.median(after)
        rows.append({'aircraft': aircraft['id'], 'case': case['case_id'],
                     'baseline_us_per_tick_median_of_six_batch_means': a,
                     'candidate_us_per_tick_median_of_six_batch_means': b,
                     'observed_reduction_pct': 100*(1-b/a),
                     'baseline_range_us': [min(before), max(before)],
                     'candidate_range_us': [min(after), max(after)],
                     'provider_queries_per_tick': case['queries_per_accepted_tick_untimed'],
                     'all_final_states_identical': True,
                     'state_sha256': case['final_state_sha256_per_batch'][0],
                     'run_medians_us': {name: c['median_us_per_tick'] for name,c in cases.items()}})
report = {'timing_qualification': 'observational; other host work uncontrolled; no deadline or causal end-to-end speedup established',
          'cases': rows, 'total_timed_ticks': 4*6*1440, 'total_warmup_ticks': 4*6*720}
(work/'comparison-summary.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
for row in rows:
    print(row['aircraft'], row['case'], round(row['baseline_us_per_tick_median_of_six_batch_means'],1),
          round(row['candidate_us_per_tick_median_of_six_batch_means'],1), round(row['observed_reduction_pct'],1), flush=True)
