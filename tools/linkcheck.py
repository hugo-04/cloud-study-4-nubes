import os,re,sys
root=sys.argv[1]
bad=0
for d,_,fs in os.walk(root):
    if '.git' in d: continue
    for f in fs:
        if not f.endswith('.md'): continue
        p=os.path.join(d,f)
        txt=open(p,encoding='utf8').read()
        txt=re.sub(r'```.*?```','',txt,flags=re.S)      # ignora bloques de código
        txt=re.sub(r'`[^`\n]*`','',txt)                  # ignora código en línea
        for m in re.finditer(r'\]\(([^)#\s]+)(#[^)]*)?\)',txt):
            t=m.group(1)
            if t.startswith(('http','mailto')): continue
            if not os.path.exists(os.path.normpath(os.path.join(d,t))):
                print(p,'->',t); bad+=1
print('rotos:',bad)
