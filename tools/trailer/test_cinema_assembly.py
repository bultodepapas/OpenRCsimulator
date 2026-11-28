#!/usr/bin/env python3
"""Focused cache/contract checks and a real two-cut FFmpeg title carry test."""
import contextlib
import copy
import hashlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from PIL import Image

import assemble as editor
import cinema_titles
import shot_plan
import title_plan

REPO = shot_plan.REPO


def media_spec(folder):
    plan = shot_plan.read_json(shot_plan.DEFAULT_PLAN)
    return {'style':'cinema', 'fps':60, 'music':str(folder/'unselected.wav'),
        'title_plan':str(title_plan.DEFAULT_PLAN), 'shot_plan':str(shot_plan.DEFAULT_PLAN),
        'shots':[{'id':s['id'], 'frames':s['out_frame']-s['in_frame'],
                  'kind':'end_card' if s['id']=='R4-45' else 'frames',
                  'source':str(folder/'unfilmed'/s['id']/'%05d.png')}
                 for s in plan['shots']]}


class CinemaAssemblyTests(unittest.TestCase):
    def test_frame_identity_tracks_content_only_in_selected_interval(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for n in range(3): (root/f'{n:05}.png').write_bytes(bytes([n]))
            pattern=root/'%05d.png'
            before=editor.frame_sequence_identity(pattern,0,2)
            (root/'00002.png').write_bytes(b'outside cut')
            self.assertEqual(editor.frame_sequence_identity(pattern,0,2),before)
            (root/'00001.png').write_bytes(b'changed source frame')
            self.assertNotEqual(editor.frame_sequence_identity(pattern,0,2),before)
            with self.assertRaisesRegex(ValueError,'exactly one'):
                editor.frame_sequence_identity(root/'no-number.png',0,2)

    def test_cache_rejects_partial_or_replaced_outputs(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); video=root/'clip.mp4'; audio=root/'clip.wav'; cache=root/'cache.json'
            video.write_bytes(b'complete video'); audio.write_bytes(b'complete audio')
            receipt={'fingerprint':'input-A','video_sha256':editor.sha(video),'audio_sha256':editor.sha(audio)}
            cache.write_text(json.dumps(receipt))
            self.assertTrue(editor.valid_cached_clip(cache,video,audio,'input-A'))
            self.assertFalse(editor.valid_cached_clip(cache,video,audio,'input-B'))
            video.write_bytes(b'partial new encode')
            self.assertFalse(editor.valid_cached_clip(cache,video,audio,'input-A'))
            cache.write_text('{interrupted')
            self.assertFalse(editor.valid_cached_clip(cache,video,audio,'input-A'))

    def test_media_contract_rejects_old_copy_wrong_timing_and_unbound_trial(self):
        spec=media_spec(Path('/not-captured'))
        resolve=lambda value:Path(value)
        loaded=editor.cinema_context(spec,resolve,True)
        self.assertEqual(loaded['title_plan_sha256'],hashlib.sha256(title_plan.DEFAULT_PLAN.read_bytes()).hexdigest())
        for change in ('frames','graphics','endcard'):
            bad=copy.deepcopy(spec)
            if change=='frames':bad['shots'][0]['frames']-=1
            elif change=='graphics':bad['shots'][0]['graphics']={'title':'OLD SLOGAN'}
            else:bad['shots'][-1]['kind']='image'
            with self.subTest(change=change),self.assertRaises(ValueError):
                editor.cinema_context(bad,resolve,True)
        with self.assertRaisesRegex(ValueError,'basis is unresolved'):
            editor.cinema_context(spec,resolve,False)
        spec['trial_basis']='estimated'
        with self.assertRaisesRegex(ValueError,'explicit title'):
            editor.cinema_context(spec,resolve,False)

    def test_graphics_only_uses_the_cinema_card(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); manifest=root/'media.json'; manifest.write_text(json.dumps(media_spec(root)))
            editor.render_graphics_only(manifest,root/'graphics')
            self.assertTrue((root/'graphics/cinema-end-card.png').is_file())
            self.assertFalse((root/'graphics/end-card.png').exists())
            with Image.open(root/'graphics/cinema-end-card.png') as picture:
                self.assertEqual(picture.size,(1920,1080))
                # Warm-white ink is already present at the very first end-card frame.
                self.assertGreater(sum(value>220 for value in picture.crop((400,300,1520,700)).tobytes()),1000)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'FFmpeg and ffprobe are required')
    def test_real_two_cut_label_is_opaque_at_both_sides_of_the_cut(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); spec=media_spec(root); by={s['id']:s for s in spec['shots']}
            for sid,color in [('R4-42b',(25,25,25)),('R4-42c',(45,45,45))]:
                picture=root/f'{sid}.png'; Image.new('RGB',(1920,1080),color).save(picture)
                by[sid].update(kind='image',source=str(picture),grade=False)
            # Available picture plus future audio remains awaiting in prepare-only.
            by['R4-32'].update(kind='image',source=str(root/'R4-42b.png'),audio=str(root/'not-recorded.wav'))
            manifest=root/'media.json'; manifest.write_text(json.dumps(spec))
            output=io.StringIO()
            with contextlib.redirect_stdout(output):
                editor.assemble(manifest,Path(shutil.which('ffmpeg')),Path(shutil.which('ffprobe')),
                                root/'out',root/'work',prepare_only=True)
            self.assertIn('AWAITING_SOURCE R4-01',output.getvalue())
            self.assertIn('AWAITING_SOURCE R4-32',output.getvalue())
            self.assertFalse(list((root/'work').glob('*-R4-32.mp4')))
            self.assertFalse(any(p.is_dir() and '-cinema-' in p.name for p in (root/'work').iterdir()))
            cue=next(c for c in title_plan.load(title_plan.DEFAULT_PLAN)['cues'] if c['id']=='phoenix')
            box=cinema_titles.CinemaCue(cue).ink_boxes[0]
            bright=[]
            for sid in ('R4-42b','R4-42c'):
                clip=next((root/'work').glob(f'*-{sid}.mp4'))
                decoded=root/f'decode-{sid}';decoded.mkdir()
                editor.run(['ffmpeg','-hide_banner','-v','error','-i',clip,'-vf',
                    'select=eq(n\\,0)+eq(n\\,29)','-fps_mode','vfr',decoded/'%02d.png'])
                for file in sorted(decoded.glob('*.png')):
                    with Image.open(file) as image:
                        pixels=image.convert('RGB').crop(box).tobytes()
                        bright.append(sum(r>215 and g>210 and b>200 for r,g,b in zip(pixels[0::3],pixels[1::3],pixels[2::3])))
            self.assertEqual(len(bright),4)
            self.assertGreater(min(bright),500)
            self.assertGreater(min(bright)/max(bright),.96)
            self.assertFalse((root/'work/end-card.png').exists())
            self.assertTrue((root/'work/cinema-end-card-base.png').is_file())
            # Cache receipt attests both completed outputs; the video is exactly 30 frames.
            clip=next((root/'work').glob('*-R4-42b.mp4'))
            editor.check_encoded_clip(clip,'ffprobe',30)
            with self.assertRaisesRegex(ValueError,'requested 1080p60 frames'):
                editor.check_encoded_clip(clip,'ffprobe',31)
            cache=clip.with_suffix('.cache.json');audio=clip.with_suffix('.wav')
            receipt=json.loads(cache.read_text())
            self.assertTrue(editor.valid_cached_clip(cache,clip,audio,receipt['fingerprint']))


if __name__=='__main__':unittest.main()
