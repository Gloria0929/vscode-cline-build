import re, sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
marker = '<div className="mb-[5px]">'
start = content.index(marker)
depth = 0
for m in re.finditer(r'<div\b|</div>', content[start:]):
    if m.group(0) == '<div':
        depth += 1
    else:
        depth -= 1
        if depth == 0:
            end = start + m.end()
            break
with open(path, 'w') as f:
    f.write(content[:start] + content[end:])
