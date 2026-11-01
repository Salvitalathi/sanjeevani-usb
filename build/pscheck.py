"""Lightweight PowerShell lexer: checks bracket balance, unterminated strings /
here-strings / block comments, and flags PowerShell-7-only operators.
Not a full parser, but catches the mistakes that would stop a script loading."""
import re, sys

PAIRS = {'(': ')', '{': '}', '[': ']'}
CLOSE = {v: k for k, v in PAIRS.items()}


def check(path):
    src = open(path, encoding='utf-8-sig').read()
    errs, warns = [], []
    stack = []
    i, n, line = 0, len(src), 1
    # mode stack for "..." strings containing $( ... )
    def at(k=0):
        return src[i + k] if i + k < n else ''
    code_chars = []  # (line, text) of code outside strings for operator scan

    def scan_dq(start_line, here=False):
        """scan a double-quoted / here string body; handles $( ) nesting recursively"""
        nonlocal i, line
        while i < n:
            c = src[i]
            if c == '\n':
                line += 1
            if here:
                if c == '\n' and src.startswith('"@', i + 1):
                    i += 3
                    return
            else:
                if c == '`':
                    i += 2
                    continue
                if c == '"':
                    if at(1) == '"':
                        i += 2
                        continue
                    i += 1
                    return
            if c == '$' and at(1) == '(':
                i += 2
                scan_code(until=')')
                continue
            i += 1
        errs.append(f'{path}:{start_line}: unterminated {"here-" if here else ""}string')

    def scan_code(until=None):
        nonlocal i, line
        depth_stack = []
        while i < n:
            c = src[i]
            if c == '\n':
                line += 1; i += 1; continue
            if c == '#':
                while i < n and src[i] != '\n':
                    i += 1
                continue
            if c == '<' and at(1) == '#':
                start = line
                j = src.find('#>', i + 2)
                if j < 0:
                    errs.append(f'{path}:{start}: unterminated block comment'); i = n; return
                line += src.count('\n', i, j); i = j + 2; continue
            if c == '@' and at(1) in ("'", '"') and src[i + 2:i + 3] in ('\n', '\r'):
                q = at(1); start = line
                if q == "'":
                    j = src.find("\n'@", i + 2)
                    if j < 0:
                        errs.append(f'{path}:{start}: unterminated here-string'); i = n; return
                    line += src.count('\n', i, j + 1); i = j + 3; continue
                i += 2
                scan_dq(start, here=True); continue
            if c == "'":
                start = line; i += 1
                while i < n:
                    if src[i] == "'":
                        if at(1) == "'":
                            i += 2; continue
                        break
                    if src[i] == '\n':
                        line += 1
                    i += 1
                if i >= n:
                    errs.append(f'{path}:{start}: unterminated single-quoted string'); return
                i += 1; continue
            if c == '"':
                start = line; i += 1
                scan_dq(start); continue
            if c == '`':
                i += 2; continue
            if c in PAIRS:
                depth_stack.append((c, line)); i += 1; continue
            if c in CLOSE:
                if until == c and not depth_stack:
                    i += 1; return
                if not depth_stack:
                    errs.append(f'{path}:{line}: unexpected {c!r}')
                else:
                    o, ol = depth_stack.pop()
                    if PAIRS[o] != c:
                        errs.append(f'{path}:{line}: {c!r} closes {o!r} opened at line {ol}')
                i += 1; continue
            code_chars.append((line, c))
            i += 1
        for o, ol in depth_stack:
            errs.append(f'{path}:{ol}: unclosed {o!r}')
        if until:
            errs.append(f'{path}: missing {until!r} for $( subexpression')

    scan_code()
    # operator scan on code only
    text_by_line = {}
    for ln, ch in code_chars:
        text_by_line.setdefault(ln, []).append(ch)
    for ln, chars in text_by_line.items():
        t = ''.join(chars)
        for pat, what in [(r'\?\?', '?? (PS7 only)'), (r'\?\.', '?. (PS7 only)'), (r'&&', '&& (PS7 only)'), (r'\|\|', '|| (PS7 only)')]:
            if re.search(pat, t):
                warns.append(f'{path}:{ln}: {what}')
    return errs, warns


if __name__ == '__main__':
    bad = 0
    for p in sys.argv[1:]:
        e, w = check(p)
        for x in e: print('ERROR', x)
        for x in w: print('WARN ', x)
        bad += len(e)
        print(('OK    ' if not e else 'FAIL  ') + p)
    sys.exit(1 if bad else 0)
