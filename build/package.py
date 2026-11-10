"""Builds dist/Sanjeevani-USB-Kit.zip from the repository (what users download).
Also enforces encodings: .ps1/.psm1 = UTF-8 with BOM (needed by Windows PowerShell 5.1
for Marathi text), .ps1/.psm1/.cmd/.txt = CRLF. Ventoy/GRUB files stay LF without BOM."""
import os, shutil, zipfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, 'dist')
OUT = os.path.join(DIST, 'Sanjeevani-USB-Kit')
shutil.rmtree(DIST, ignore_errors=True)
shutil.copytree(os.path.join(ROOT, 'kit'), os.path.join(OUT, 'kit'))
for f in ('SETUP.cmd', 'Setup-Sanjeevani.ps1', 'CLEAN.cmd', 'Clean-Sanjeevani.ps1', 'README.txt', 'README-Marathi.txt', 'README-Hindi.txt'):
    shutil.copy(os.path.join(ROOT, f), OUT)
for dp, _, fs in os.walk(OUT):
    for f in fs:
        p = os.path.join(dp, f); ext = os.path.splitext(f)[1].lower()
        if ext not in ('.ps1', '.psm1', '.cmd', '.txt', '.json', '.html') or f in ('ventoy.json', 'fonts.list', 'theme.txt'):
            continue
        b = open(p, 'rb').read()
        if b.startswith(b'\xef\xbb\xbf'): b = b[3:]
        t = b.decode('utf-8').replace('\r\n', '\n')
        if ext in ('.ps1', '.psm1', '.cmd', '.txt'): t = t.replace('\n', '\r\n')
        bom = ext in ('.ps1', '.psm1') or (ext == '.txt' and any(ord(c) > 127 for c in t))   # Notepad shows मराठी / हिन्दी right
        open(p, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + t.encode('utf-8'))
z = os.path.join(DIST, 'Sanjeevani-USB-Kit.zip')
with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
    for dp, _, fs in os.walk(OUT):
        for f in fs:
            p = os.path.join(dp, f); zf.write(p, os.path.relpath(p, DIST))
print(z, os.path.getsize(z) // 1024, 'KB')
