#!/usr/bin/env python3
"""Prepare a Luau source file for Lua 5.1 tooling (Prometheus obfuscator).

Transforms (syntax-only, no behavior change):
  1. Strip Luau type annotations in function signatures:
       function f(a: string, b: number?): Color3  ->  function f(a, b)
       local function g(x: Instance): nil          ->  local function g(x)
     Brace-aware so table types like { { a: X, b: Y } } are handled.
  2. Strip typed local declarations:
       local x: {string} = {}  ->  local x = {}
  3. Expand compound assignments:
       a += b  ->  a = a + b     (also -=, *=, /=, ..=)
Usage: python3 prepare_lua51.py <in.luau> <out.lua>
"""
import re
import sys

FUNC_RE = re.compile(r"\bfunction\b")
PARAM_SPLIT_RE = re.compile(r"[,\(\)\[\]{}]")


def skip_string(src: str, i: int) -> int:
    """i points at the opening quote. Return index just past the closing quote."""
    q = src[i]
    i += 1
    n = len(src)
    while i < n:
        if src[i] == "\\":
            i += 2
            continue
        if src[i] == q:
            return i + 1
        i += 1
    return i


def find_next_code_function(src: str, start: int):
    """Find the next 'function' keyword in code (not inside strings or comments)."""
    i = start
    n = len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            i = skip_string(src, i)
        elif c == "-" and src.startswith("--", i):
            # comment: skip to end of line (long comments not used in our style)
            nl = src.find("\n", i)
            i = n if nl == -1 else nl + 1
        else:
            m = FUNC_RE.match(src, i)
            if m:
                return m
            i += 1
    return None


def strip_annotations(src: str) -> str:
    out = []
    i = 0
    while True:
        m = find_next_code_function(src, i)
        if not m:
            out.append(src[i:])
            break
        j = m.end()
        out.append(src[i:j])
        # find the opening paren of the signature
        k = j
        n = len(src)
        while k < n and src[k] not in "(\n":
            k += 1
        if k >= n or src[k] != "(":
            i = max(j, k)
            continue
        # scan to matching close paren
        depth = 0
        end = None
        p = k
        while p < n:
            c = src[p]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    end = p
                    break
            p += 1
        if end is None:
            i = k
            continue
        out.append(src[j:k])  # function name / method qualifiers
        # split params on top-level commas
        params_src = src[k + 1 : end]
        parts = []
        depth = 0
        cur = 0
        for idx, c in enumerate(params_src):
            if c in "{([":
                depth += 1
            elif c in "})]":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append(params_src[cur:idx])
                cur = idx + 1
        parts.append(params_src[cur:])
        cleaned = []
        for part in parts:
            part = part.strip()
            if not part:
                continue
            d = 0
            cut = None
            for idx, c in enumerate(part):
                if c in "{([":
                    d += 1
                elif c in "})]":
                    d -= 1
                elif c == ":" and d == 0:
                    cut = idx
                    break
            if cut is not None:
                part = part[:cut].strip()
            cleaned.append(part)
        out.append("(" + ", ".join(cleaned) + ")")
        # return annotation after the close paren?
        r = end + 1
        ret_end = r
        while ret_end < n and src[ret_end] not in "\n;":
            ret_end += 1
        tail = src[r:ret_end]
        if re.match(r"\s*:", tail):
            i = ret_end  # skip the return annotation entirely
        else:
            i = r
    return "".join(out)


def strip_typed_locals(src: str) -> str:
    return re.sub(
        r"(\blocal\s+[A-Za-z_]\w*)\s*:\s*[^=\n]+=",
        r"\1 =",
        src,
    )


def expand_compound(src: str) -> str:
    return re.sub(
        r"^(\s*[\w.\[\]\"':]+(?:\([^()]*\))?)\s*([+\-*/]|\.\.)=\s*(.+?)\s*$",
        lambda m: f"{m.group(1)} = {m.group(1)} {m.group(2)} {m.group(3)}",
        src,
        flags=re.MULTILINE,
    )


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        src = f.read()
    src = strip_annotations(src)
    src = strip_typed_locals(src)
    src = expand_compound(src)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(src)
    print(f"wrote {sys.argv[2]} ({len(src)} chars)")


if __name__ == "__main__":
    main()
