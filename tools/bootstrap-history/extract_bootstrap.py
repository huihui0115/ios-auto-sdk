import sys

path = r'Sources\AutoSDK\AutoBootstrapScript.m'
src = open(path, 'r', encoding='utf-8-sig', errors='replace').read()
start = src.find('return @"')
assert start >= 0
i = start + len('return @"')  # points at char right after opening "
n = len(src)
out = []
mode = 'str'  # we are already inside the first literal
while i < n:
    c = src[i]
    if mode == 'code':
        if c == '"':
            mode = 'str'
            i += 1
        elif c == ';':
            break
        else:
            i += 1
    else:
        if c == '\\':
            nxt = src[i+1] if i+1 < n else ''
            mp = {'n':'\n','t':'\t','r':'\r','"':'"','\\':'\\','0':'\0',"'":"'"}
            out.append(mp.get(nxt, nxt))
            i += 2
        elif c == '"':
            mode = 'code'
            i += 1
        else:
            out.append(c)
            i += 1
js = ''.join(out)
open(sys.argv[2], 'w', encoding='utf-8', newline='\n').write(js)
print(f'extracted {len(js)} chars -> {sys.argv[2]}')
