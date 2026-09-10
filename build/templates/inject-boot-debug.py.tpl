#!/usr/bin/env python3
"""Insert the boot-debug overlay script before the module script tag in
WebviewProvider.ts's HTML template. Usage: inject-boot-debug.py <provider.ts> <snippet.html>"""
import re
import sys

provider_path, snippet_path = sys.argv[1], sys.argv[2]

with open(provider_path, encoding="utf-8") as f:
    src = f.read()
with open(snippet_path, encoding="utf-8") as f:
    snippet = f.read()

if "__dbg_boot" in src:
    print("overlay already present, skipping")
    sys.exit(0)

# The template literal embeds the module script tag; anchor on it.
anchor = '<script type="module" nonce="${nonce}" src="${scriptUrl}"></script>'
if anchor not in src:
    print("ANCHOR NOT FOUND")
    sys.exit(1)

# @@NONCE@@ becomes ${nonce} — a runtime interpolation in the TS template literal.
snippet = snippet.replace("@@NONCE@@", "${nonce}")

# Re-indent: the anchor sits inside a tab-indented template literal; give each
# inserted line the same base indent as the anchor line.
m = re.search(r"(?:\n)([\t ]+)" + re.escape(anchor), src)
indent = m.group(1) if m else "\t\t\t\t\t"
body = "\n".join(indent + line if line.strip() else line for line in snippet.rstrip().split("\n"))
src = src.replace(anchor, body + "\n" + indent + anchor, 1)

with open(provider_path, "w", encoding="utf-8") as f:
    f.write(src)
print("INJECTED")
