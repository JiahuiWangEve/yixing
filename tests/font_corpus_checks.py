import importlib.util,tempfile,pathlib,shutil
p=pathlib.Path(__file__).resolve().parents[1]/'scripts/font_subset.py';spec=importlib.util.spec_from_file_location('f',p);f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
with tempfile.TemporaryDirectory() as d:
 f.ROOT=pathlib.Path(d); f.GAME=f.ROOT/'game'; f.GAME.mkdir(); f.MANIFEST=f.GAME/'font-subset.json'
 script=f.GAME/'demo.gd';script.write_text('var x="将军\\u9A6C"\nvar y=char(0x8F66)\n')
 points,_=f.corpus();assert all(ord(c) in points for c in '将军马车');assert all(c in points for c in range(32,127))
 script.write_text('var x=char(from_server)')
 try:f.corpus();assert False
 except ValueError:pass
 print('PASS font corpus guard: literals, Unicode escapes, numeric codepoints, ASCII, rejects unknown dynamic chars')
