#!/usr/bin/env python3
"""Compila (tsc --noEmit, modo estricto) los bloques ```ts y ```tsx de los .md.
Uso: TSDIR=/tmp/ts python3 tools/tscheck.py archivo.md ...   (TSDIR con typescript, react, @angular/*, rxjs instalados)
Bloques que empiezan con '// nocheck' se saltan; '// archivo: x.ts' fija el nombre del archivo."""
import os, re, sys, json, shutil, subprocess, pathlib
d = pathlib.Path(os.environ.get('TSDIR', '/tmp/ts'))
src = d / 'chk'; shutil.rmtree(src, ignore_errors=True); src.mkdir()
meta, n = {}, 0
for md in sys.argv[1:]:
    for i, m in enumerate(re.finditer(r'```(tsx?)\n(.*?)```', open(md, encoding='utf-8').read(), re.S), 1):
        if m.group(2).lstrip().startswith('// nocheck'): continue
        n += 1; body = m.group(2)
        nom = re.match(r'\s*// archivo: (\S+)', body)   # permite importar un bloque desde otro: import ... from './nombre'
        f = src / (nom.group(1) if nom else f"b{n}.{m.group(1)}")
        if not re.search(r'^\s*(import|export)\s', body, re.M): body += "\nexport {};\n"
        f.write_text(body, encoding='utf-8'); meta[f.name] = f"{md}#{i}"
(d / 'tsconfig.json').write_text(json.dumps({"compilerOptions": {
    "target": "ES2022", "module": "ESNext", "moduleResolution": "bundler", "strict": True, "noEmit": True,
    "jsx": "react-jsx", "lib": ["ES2022", "DOM", "DOM.Iterable"], "experimentalDecorators": True,
    "skipLibCheck": True, "noUnusedLocals": False, "useDefineForClassFields": False}, "include": ["chk"]}))
print(f"{n} bloques TypeScript")
r = subprocess.run([str(d / 'node_modules/.bin/tsc'), '-p', str(d)], capture_output=True, text=True)
if r.returncode == 0: print("OK: todo compila")
else:
    for l in (r.stdout + r.stderr).splitlines():
        mm = re.search(r'chk/([\w.-]+\.tsx?)\((\d+),\d+\): (.*)', l)
        print(f"FALLA {meta.get(mm.group(1),'?')} linea {mm.group(2)}: {mm.group(3)[:160]}" if mm else l[:200])
