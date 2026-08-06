import sys
for path in sys.argv[1:]:
    data = open(path, 'r', encoding='utf-8').read()
    stack = []
    pairs = {')': '(', ']': '[', '}': '{'}
    i = 0
    in_str = False
    in_char = False
    in_block = False
    line = 1
    while i < len(data):
        ch = data[i]
        if ch == '\n':
            line += 1
        if in_block:
            if ch == '*' and i + 1 < len(data) and data[i+1] == '/':
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if ch == '\\':
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if in_char:
            if ch == '\\':
                i += 2
                continue
            if ch == "'":
                in_char = False
            i += 1
            continue
        if ch == '/' and i + 1 < len(data) and data[i+1] == '/':
            j = data.find('\n', i)
            if j < 0:
                break
            i = j
            continue
        if ch == '/' and i + 1 < len(data) and data[i+1] == '*':
            in_block = True
            i += 2
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "'":
            in_char = True
            i += 1
            continue
        if ch in '([{':
            stack.append((ch, line))
            i += 1
            continue
        if ch in ')]}':
            if not stack or stack[-1][0] != pairs[ch]:
                print(path, 'MISMATCH at line', line, 'char', ch, 'stack-top', stack[-1] if stack else None)
                sys.exit(1)
            stack.pop()
            i += 1
            continue
        i += 1
    if in_str:
        print(path, 'UNTERMINATED string')
        sys.exit(1)
    if stack:
        print(path, 'UNCLOSED brackets:', stack[-10:])
        sys.exit(1)
    print(path, 'brackets OK')
