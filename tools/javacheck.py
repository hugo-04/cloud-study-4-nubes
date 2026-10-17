#!/usr/bin/env python3
"""Compila los bloques ```java de los .md. Uso: javacheck.py [--quarkus] archivo.md ...
Salta bloques listados en skip.txt (formato: ruta.md#N) y los que empiezan con '// nocheck'."""
import re, sys, os, shutil, subprocess, pathlib
SCR = pathlib.Path(__file__).parent
args = sys.argv[1:]
quarkus = False
if args and args[0] == '--quarkus':
    quarkus = True; args = args[1:]
proj = pathlib.Path(os.environ.get('JVQ_DIR', '/tmp/jvq') if quarkus else os.environ.get('JV_DIR', '/tmp/jv'))
src = proj / 'src/main/java/chk'
shutil.rmtree(src, ignore_errors=True); src.mkdir(parents=True)
skip = set()
sk = SCR / 'skip.txt'
if sk.exists(): skip = set(l.strip() for l in sk.read_text().splitlines() if l.strip())
QK = ('io.quarkus','jakarta.ws.rs','org.eclipse.microprofile','io.smallrye','jakarta.enterprise','jakarta.inject','io.vertx','org.jboss')
meta = {}
n = 0
for md in args:
    prel_imports, prel_code = [], []
    text = open(md, encoding='utf-8').read()
    for i, m in enumerate(re.finditer(r'```java\n(.*?)```', text, re.S), 1):
        body = m.group(1)
        key = f"{os.path.relpath(md, str(SCR.parent))}#{i}"
        if key in skip or body.lstrip().startswith('// nocheck'): continue
        is_q = any(q in body for q in QK)
        _first = body.lstrip().splitlines()[0] if body.strip() else ''
        ambos = _first.startswith('// (clase reutilizada') and 'ambos' in _first
        if is_q != quarkus and not ambos: continue
        imports = [l for l in body.splitlines() if re.match(r'\s*import\s', l)]
        rest = '\n'.join(l for l in body.splitlines() if not re.match(r'\s*import\s', l))
        n += 1
        pkg = f"chk.b{n}"
        d = src / f"b{n}"; d.mkdir()
        has_type = re.search(r'^(public\s+|final\s+|abstract\s+|sealed\s+)*(class|interface|record|enum)\s+\w+', rest, re.M) or re.search(r'^@\w+(\(.*\))?\s*\n(public\s+)?(class|interface|record|enum)\s', rest, re.M)
        if has_type:
            code = re.sub(r'^public\s+(?=(final\s+|abstract\s+)?(class|interface|record|enum))', '', rest, flags=re.M)
            name = 'Blk'
        else:
            members = re.search(r'^\s*(@\w+(\(.*\))?\s+)*[\w<>\[\], ?.]+\s+\w+\s*\([^;]*\)\s*(throws [\w, .]+)?\s*\{', rest, re.M) and not re.search(r'^\s*(var|try|for|if|return|new)\b', rest.strip().splitlines()[0] if rest.strip() else '')
            if members:
                code = f"class F{n} {{\n{rest}\n}}"
            else:
                code = f"class F{n} {{ void m() throws Exception {{\n{rest}\n}} }}"
        es_prelude = body.lstrip().startswith('// (clase reutilizada')
        if not es_prelude:
            imports = list(dict.fromkeys(prel_imports + imports))
            code = '\n'.join(prel_code) + "\n" + code if prel_code else code
        else:
            _prev_imports, _prev_code = list(prel_imports), list(prel_code)
            prel_imports += [i for i in imports if i not in prel_imports]
            prel_code.append(re.sub(r'^public\s+(?=(final\s+|abstract\s+)?(class|interface|record|enum))', '', rest, flags=re.M))
            imports = list(dict.fromkeys(_prev_imports + imports))
            if _prev_code: code = '\n'.join(_prev_code) + "\n" + code
        full = f"package {pkg};\n" + '\n'.join(imports) + "\n" + code + "\n"
        (d / f"Blk{n}.java").write_text(full, encoding='utf-8')
        meta[f"b{n}"] = key
print(f"{n} bloques a compilar ({'quarkus' if quarkus else 'spring/azure'})")
r = subprocess.run(['mvn','-q','-B','compile','-Dmaven.compiler.showWarnings=false'], cwd=proj, capture_output=True, text=True)
out = r.stdout + r.stderr
errs = [l for l in out.splitlines() if 'ERROR' in l and '.java' in l]
if r.returncode == 0:
    print("OK: todo compila")
else:
    lines = out.splitlines()
    shown=set()
    for idx,l in enumerate(lines):
        if not ('ERROR' in l and '.java' in l): continue
        mm = re.search(r'/b(\d+)/Blk\d+\.java:\[(\d+),\d+\] (.*)', l)
        if mm:
            k = meta.get('b'+mm.group(1), '?')
            sym = next((x.strip() for x in lines[idx+1:idx+3] if 'symbol:' in x), '')
            msg = f"FALLA {k} linea {mm.group(2)}: {mm.group(3)[:120]} {sym}"
            if msg not in shown:
                shown.add(msg); print(msg)
        else:
            print(l[:200])
    if not errs: print(out[-1500:])
