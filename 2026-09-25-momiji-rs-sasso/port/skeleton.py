#!/usr/bin/env python3
"""Generate the BAML declaration skeleton of the sasso port.

    python3 port/skeleton.py <sasso-checkout> <baml-project> [--force]

For every Rust module under src/ it writes the mapped .baml file (see
PORTING_GUIDE.md §1) containing every item with its doc comments, complete
type declarations (classes, enums, interfaces, aliases) and every function /
method signature, with bodies stubbed as `root.std.todo()`. The mapping rules
are the guide's; applying them mechanically keeps names and signatures
consistent across modules that are later filled in by different porters.

Rust types the translator cannot map are emitted as `unknown /* PORT-TYPE: … */`.
"""
import os
import re
import sys
from collections import defaultdict

SASSO = sys.argv[1]
PROJECT = sys.argv[2]
FORCE = '--force' in sys.argv
SRC = os.path.join(SASSO, 'src')

BAML_RESERVED = set('''in client test match self function generator template_string let if
else for while return break continue throw throws catch catch_all spawn await implements
interface true false null is enum class const defer testset retry_policy instanceof requires
extends'''.split())

INT_TYPES = {'i8', 'i16', 'i32', 'i64', 'isize', 'u8', 'u16', 'u32', 'usize', 'u64'}
BIGINT_U64_MODULES = {'root.fxhash', 'root.ryu', 'root.ryu_tables', 'root.musl_math',
                      'root.musl_math_tables', 'root.builtins.colorspace.matrices'}


def safe(name):
    return name + '_' if name in BAML_RESERVED else name


def pascal(s):
    return ''.join(p[:1].upper() + p[1:] for p in s.split('_'))


# --------------------------------------------------------------------------
# Lexing helpers

def blank_comments_strings(src):
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif src.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('/*', j):
                    depth += 1
                    j += 2
                elif src.startswith('*/', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            for k in range(i, j):
                if out[k] != '\n':
                    out[k] = ' '
            i = j
        elif (c == 'r' or c == 'b') and re.match(r'(b?r#*"|b")', src[i:i + 12]) and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            m = re.match(r'b?r(#*)"', src[i:])
            if m:
                hashes = m.group(1)
                end = src.find('"' + hashes, i + len(m.group(0)))
                end = n if end < 0 else end + 1 + len(hashes)
                for k in range(i + len(m.group(0)), end - 1 - len(hashes)):
                    if out[k] != '\n':
                        out[k] = ' '
                i = end
            else:  # b"..."
                j = i + 2
                while j < n and src[j] != '"':
                    j += 2 if src[j] == '\\' else 1
                for k in range(i + 2, j):
                    if out[k] != '\n':
                        out[k] = ' '
                i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            for k in range(i + 1, j):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif c == "'":
            m = re.match(r"'(\\u\{[0-9a-fA-F]+\}|\\x[0-9a-fA-F]{2}|\\.|[^\\'\n])'", src[i:])
            if m:
                for k in range(i + 1, i + len(m.group(0)) - 1):
                    out[k] = ' '
                i += len(m.group(0))
            else:
                i += 1
        else:
            i += 1
    return ''.join(out)


def match_close(s, i, open_ch='{', close_ch='}'):
    depth = 0
    while i < len(s):
        if s[i] == open_ch:
            depth += 1
        elif s[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(s) - 1


def segments(clean, lo, hi):
    """Split [lo, hi) into top-level item segments."""
    segs = []
    start = lo
    depth = 0
    i = lo
    while i < hi:
        c = clean[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0 and c == '}':
                # A braced item ends here unless a `;`/`=`-continuation follows
                # (e.g. `const X: T = T { .. };`, `use a::{b};`).
                j = i + 1
                while j < hi and clean[j] in ' \t\r\n':
                    j += 1
                header = clean[start:i]
                if j < hi and clean[j] == ';' and re.search(r'\b(const|static|use|type|let)\b', header[:header.find('{') if '{' in header else len(header)]):
                    i = j
                    segs.append((start, i + 1))
                    start = i + 1
                elif re.match(r'\s*(#\[[^\]]*\]\s*)*(pub(\([^)]*\))?\s+)?(const|static)\b', header) and '=' in header:
                    pass  # `const X: T = S { .. }` continues to `;`
                else:
                    segs.append((start, i + 1))
                    start = i + 1
        elif c == ';' and depth == 0:
            segs.append((start, i + 1))
            start = i + 1
        i += 1
    if clean[start:hi].strip():
        segs.append((start, hi))
    return segs


def split_top(s, sep=','):
    """Split on `sep` at depth 0 of () [] {} <> (ignoring `->`)."""
    parts, depth, cur = [], 0, []
    i = 0
    while i < len(s):
        c = s[i]
        if c in '([{<':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == '>':
            if i > 0 and s[i - 1] == '-':
                pass
            else:
                depth -= 1
        if c == sep and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    parts.append(''.join(cur))
    return [p for p in parts]


def leading_comments(src, clean, lo, kw_pos):
    """The comment lines (and attributes) in src[lo:kw_pos] -> BAML comment lines."""
    text = src[lo:kw_pos]
    lines = []
    for line in text.split('\n'):
        st = line.strip()
        if st.startswith('///') or st.startswith('//!'):
            lines.append('///' + st[3:] if st.startswith('///') else '//' + st[3:])
        elif st.startswith('//'):
            lines.append(st)
    return lines


# --------------------------------------------------------------------------
# Module discovery

def module_of(rel):
    if rel == 'builtins/colorspace_matrices.rs':
        return 'root.builtins.colorspace.matrices'
    parts = rel[:-3].split('/')
    if parts[-1] == 'mod':
        parts = parts[:-1]
    if parts in (['lib'], ['main']):
        return 'root'
    return 'root.' + '.'.join(parts)


def baml_file_of(rel):
    if rel == 'builtins/colorspace_matrices.rs':
        return 'baml_src/ns_builtins/ns_colorspace/ns_matrices/colorspace_matrices.baml'
    parts = rel[:-3].split('/')
    if parts == ['lib']:
        return 'baml_src/lib.baml'
    if parts == ['main']:
        return 'baml_src/main.baml'
    if parts[-1] == 'mod':
        return 'baml_src/' + '/'.join('ns_' + p for p in parts[:-1]) + '/mod.baml'
    return 'baml_src/' + '/'.join('ns_' + p for p in parts) + '/' + parts[-1] + '.baml'


# --------------------------------------------------------------------------
# Item model

class Item:
    def __init__(self, **kw):
        self.__dict__.update(kw)


ITEM_KW = re.compile(r'^\s*((?:#!?\[(?:[^\[\]]|\[[^\]]*\])*\]\s*)*)(?:pub(?:\s*\([^)]*\))?\s+)?(?:unsafe\s+)?(?:(const\s+fn|async\s+fn|fn|struct|enum|trait|type|const|static|impl|mod|use|extern\s+crate|thread_local!|macro_rules!)\b)?')


def parse_items(src, clean, lo, hi):
    items = []
    for (a, b) in segments(clean, lo, hi):
        seg = clean[a:b]
        m = ITEM_KW.match(seg)
        if not m:
            continue
        attrs = src[a + m.start(1):a + m.end(1)] if m.group(1) else ''
        kw = m.group(2)
        kw_pos = a + (m.start(2) if kw else m.end(1))
        if not kw:
            # macro invocation or stray `;`
            txt = seg.strip()
            if txt and txt != ';':
                items.append(Item(kind='macro', a=a, b=b, kw_pos=kw_pos, attrs=attrs, text=src[a:b].strip()))
            continue
        kw = re.sub(r'\s+', ' ', kw)
        items.append(Item(kind=kw, a=a, b=b, kw_pos=kw_pos, attrs=attrs))
    return items


def is_test(attrs):
    a = attrs.replace(' ', '')
    return '#[test]' in a or (not cfg_ok_attrs(attrs, test=False) and cfg_ok_attrs(attrs, test=True))


CFG_TRUE = {'unix'}


def cfg_eval(expr, test=False):
    """Evaluate a cfg predicate for the port's target: a unix release build
    (not windows, not wasm, no debug_assertions) of the default features."""
    expr = expr.strip()
    m = re.match(r'^(all|any|not)\s*\((.*)\)$', expr, re.S)
    if m:
        args = [a for a in split_top(m.group(2)) if a.strip()]
        vals = [cfg_eval(a, test) for a in args]
        if m.group(1) == 'all':
            return all(vals)
        if m.group(1) == 'any':
            return any(vals)
        return not vals[0]
    m = re.match(r'^([a-z_]+)\s*=\s*"([^"]*)"$', expr)
    if m:
        k, v = m.groups()
        if k == 'feature':
            return v == 'cli-clock'
        if k == 'target_os':
            return v in ('macos', 'linux')
        if k == 'target_family':
            return v == 'unix'
        if k == 'target_arch':
            return v not in ('wasm32', 'wasm64')
        if k == 'target_pointer_width':
            return v == '64'
        if k == 'target_env':
            return False
        return False
    if expr == 'test':
        return test
    if expr in ('unix',):
        return True
    if expr in ('windows', 'debug_assertions', 'miri', 'doc', 'doctest', 'fuzzing'):
        return False
    return False


def cfg_ok_attrs(attrs, test=False):
    for m in re.finditer(r'#\[cfg\((.*?)\)\]\s*(?=#|$)', attrs.replace('\n', ' ') + ' ', re.S):
        if not cfg_eval(m.group(1), test):
            return False
    for m in re.finditer(r'#\[cfg\((.*)\)\]', attrs):
        pass
    return True


def cfg_excluded(attrs):
    a = attrs.replace(' ', '')
    if '#[test]' in a:
        return True
    return not cfg_ok_attrs(attrs, test=False)


# --------------------------------------------------------------------------
# Global symbol tables

class FileInfo:
    pass


files = {}          # rel -> FileInfo
type_defs = defaultdict(list)   # name -> [(module, kind, rel)]
enum_kind = {}      # (module, name) -> 'DATA'|'CLIKE'
generic_arity = {}  # (module, name) -> [type params]
struct_fields = {}  # (module, name) -> set(field names)
trait_defs = {}     # (module, name)
aliases = {}        # (module, name) -> rust type text


def type_params_of(header, name):
    m = re.search(re.escape(name) + r'\s*<', header)
    if not m:
        return []
    start = m.end() - 1
    end = match_close(header, start, '<', '>')
    inner = header[start + 1:end]
    ps = []
    for p in split_top(inner):
        p = p.strip()
        if not p or p.startswith("'"):
            continue
        if p.startswith('const '):
            continue
        ps.append(re.split(r'[:=\s]', p)[0])
    return ps


def collect():
    for d, _, fs in os.walk(SRC):
        for f in fs:
            if not f.endswith('.rs'):
                continue
            rel = os.path.relpath(os.path.join(d, f), SRC)
            src = open(os.path.join(SRC, rel)).read()
            clean = blank_comments_strings(src)
            fi = FileInfo()
            fi.rel = rel
            fi.src = src
            fi.clean = clean
            fi.module = module_of(rel)
            fi.items = parse_items(src, clean, 0, len(src))
            fi.uses = {}
            fi.globs = []
            files[rel] = fi
            for it in fi.items:
                if cfg_excluded(it.attrs):
                    continue
                head = clean[it.kw_pos:it.b]
                if it.kind in ('struct', 'enum', 'trait', 'type'):
                    m = re.match(r'(?:struct|enum|trait|type)\s+([A-Za-z_][A-Za-z0-9_]*)', head)
                    if not m:
                        continue
                    name = m.group(1)
                    type_defs[name].append((fi.module, it.kind, rel))
                    hdr = head[:head.find('{')] if '{' in head else head
                    generic_arity[(fi.module, name)] = type_params_of(hdr, name)
                    if it.kind == 'enum':
                        body = head[head.find('{') + 1:head.rfind('}')]
                        data = False
                        for v in split_top(body):
                            v = re.sub(r'#\[[^\]]*\]', '', v).strip()
                            if '(' in v or '{' in v:
                                data = True
                        enum_kind[(fi.module, name)] = 'DATA' if data else 'CLIKE'
                    if it.kind == 'trait':
                        trait_defs[(fi.module, name)] = True
                    if it.kind == 'type':
                        mm = re.match(r'type\s+[A-Za-z_0-9]+\s*(<[^=]*>)?\s*=\s*(.*);', ' '.join(head.split()))
                        if mm:
                            aliases[(fi.module, name)] = mm.group(2)
                elif it.kind == 'use':
                    parse_use(fi, ' '.join(head.split()))
    # struct field names (for method/field clash detection)
    for rel, fi in files.items():
        for it in fi.items:
            if it.kind != 'struct' or cfg_excluded(it.attrs):
                continue
            head = fi.clean[it.kw_pos:it.b]
            m = re.match(r'struct\s+([A-Za-z_][A-Za-z0-9_]*)', head)
            if not m:
                continue
            fields = set()
            if '{' in head:
                body = head[head.find('{') + 1:head.rfind('}')]
                for f in split_top(body):
                    f = re.sub(r'#\[[^\]]*\]', '', f).strip()
                    fm = re.match(r'(?:pub(?:\([^)]*\))?\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:', f)
                    if fm:
                        fields.add(fm.group(1))
            struct_fields[(fi.module, m.group(1))] = fields


def parse_use(fi, text):
    text = text.strip().rstrip(';')
    text = re.sub(r'^(pub(\([^)]*\))?\s+)?use\s+', '', text)

    def walk(prefix, t):
        t = t.strip()
        if t.startswith('{') and t.endswith('}'):
            for part in split_top(t[1:-1]):
                if part.strip():
                    walk(prefix, part)
            return
        m = re.match(r'^([A-Za-z_0-9]+(?:::[A-Za-z_0-9]+)*)(::\{(.*)\}|::\*)?(\s+as\s+([A-Za-z_0-9]+))?$', t, re.S)
        if not m:
            return
        path = prefix + m.group(1).split('::')
        if m.group(2) == '::*':
            fi.globs.append(path)
            return
        if m.group(3) is not None:
            walk(path, '{' + m.group(3) + '}')
            return
        local = m.group(5) or path[-1]
        if local == 'self':
            local = path[-2]
            path = path[:-1]
        fi.uses[local] = path
    walk([], text)


def resolve_module_path(fi, path):
    """Rust path segments (without the item) relative to fi -> 'root.x.y' or None."""
    mod = fi.module.split('.')
    # the module that child `mod x;` declarations hang from
    base = mod[:]
    out = None
    segs = list(path)
    if not segs:
        return fi.module
    if segs[0] == 'crate':
        out = ['root']
        segs = segs[1:]
    elif segs[0] == 'super':
        out = base[:]
        while segs and segs[0] == 'super':
            out = out[:-1] if len(out) > 1 else out
            segs = segs[1:]
    elif segs[0] == 'self':
        out = base[:]
        segs = segs[1:]
    elif segs[0] in ('std', 'core', 'alloc', 'sasso'):
        if segs[0] == 'sasso':
            out = ['root']
            segs = segs[1:]
        else:
            return None
    else:
        # relative child module (`use binop::*` inside eval/mod.rs)
        out = base[:]
    return '.'.join(out + segs)


def lookup_type(fi, name, extra_scope=None):
    """Resolve a bare type name used in fi -> (module, kind) or None."""
    defs = type_defs.get(name, [])
    # 1. same module
    for (mod, kind, rel) in defs:
        if mod == fi.module:
            return mod, kind
    # 2. `use` imports
    if name in fi.uses:
        path = fi.uses[name]
        modpath = resolve_module_path(fi, path[:-1])
        orig = path[-1]
        if modpath is not None:
            for (mod, kind, rel) in type_defs.get(orig, []):
                if mod == modpath:
                    return mod, kind
            # re-export: pick any definition of the original name
            cands = type_defs.get(orig, [])
            if len(cands) >= 1:
                pref = [c for c in cands if c[0].startswith(modpath)]
                c = (pref or cands)[0]
                return c[0], c[1]
    # 3. glob imports
    for g in fi.globs:
        modpath = resolve_module_path(fi, g)
        for (mod, kind, rel) in defs:
            if mod == modpath:
                return mod, kind
    # 4. parent modules (child modules see `super::*` items)
    mod = fi.module
    while '.' in mod:
        mod = mod.rsplit('.', 1)[0]
        for (m2, kind, rel) in defs:
            if m2 == mod:
                return m2, kind
    # 5. unique global / nearest
    if len(defs) == 1:
        return defs[0][0], defs[0][1]
    if defs:
        top = fi.module.split('.')[:2]
        for (m2, kind, rel) in defs:
            if m2.split('.')[:2] == top:
                return m2, kind
        return defs[0][0], defs[0][1]
    return None


def qualify(fi, module, name):
    if module == fi.module:
        return name
    return module + '.' + name


# --------------------------------------------------------------------------
# Type parsing / translation

TOKEN = re.compile(r"\s*(->|::|'[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*|[0-9][A-Za-z0-9_]*|[<>()\[\];,&*!=+?])")


def tokenize(t):
    toks = []
    i = 0
    t = t.strip()
    while i < len(t):
        m = TOKEN.match(t, i)
        if not m:
            i += 1
            continue
        toks.append(m.group(1))
        i = m.end()
    return toks


class TP:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else None

    def next(self):
        tok = self.peek()
        self.i += 1
        return tok

    def eat(self, tok):
        if self.peek() == tok:
            self.i += 1
            return True
        return False

    def parse_type(self):
        tok = self.peek()
        if tok is None:
            return ('infer',)
        if tok == '&':
            self.next()
            if self.peek() and self.peek().startswith("'"):
                self.next()
            mut = self.eat('mut')
            return ('ref', mut, self.parse_type())
        if tok == '*':
            self.next()
            self.eat('const') or self.eat('mut')
            return ('ptr', self.parse_type())
        if tok == '(':
            self.next()
            elems = []
            while self.peek() not in (')', None):
                elems.append(self.parse_type())
                if not self.eat(','):
                    break
            self.eat(')')
            return ('tuple', elems)
        if tok == '[':
            self.next()
            inner = self.parse_type()
            if self.eat(';'):
                while self.peek() not in (']', None):
                    self.next()
            self.eat(']')
            return ('slice', inner)
        if tok == '!':
            self.next()
            return ('never',)
        if tok == '_':
            self.next()
            return ('infer',)
        if tok in ('dyn', 'impl'):
            self.next()
            bounds = self.parse_bounds()
            return (tok, bounds)
        if tok == 'fn':
            self.next()
            self.eat('(')
            params = []
            while self.peek() not in (')', None):
                params.append(self.parse_type())
                if not self.eat(','):
                    break
            self.eat(')')
            ret = ('tuple', [])
            if self.eat('->'):
                ret = self.parse_type()
            return ('fn', params, ret)
        if tok and tok.startswith("'"):
            self.next()
            return ('lifetime',)
        return self.parse_path()

    def parse_bounds(self):
        bounds = []
        while True:
            if self.peek() and self.peek().startswith("'"):
                self.next()
            elif self.peek() == '?':
                self.next()
                self.parse_path()
            else:
                p = self.parse_path()
                bounds.append(p)
            if not self.eat('+'):
                break
        return bounds

    def parse_path(self):
        segs = []
        args = []
        fn_args = None
        fn_ret = None
        assoc = {}
        while True:
            tok = self.next()
            if tok is None:
                break
            segs.append(tok)
            if self.peek() == '<':
                self.next()
                args = []
                assoc = {}
                while self.peek() not in ('>', None):
                    if self.peek() and self.peek().startswith("'"):
                        self.next()
                    elif self.peek(1) == '=' and re.match(r'[A-Za-z_]', self.peek() or ''):
                        k = self.next()
                        self.next()
                        assoc[k] = self.parse_type()
                    else:
                        args.append(self.parse_type())
                    if not self.eat(','):
                        break
                self.eat('>')
            elif self.peek() == '(' and tok in ('Fn', 'FnMut', 'FnOnce'):
                self.next()
                fn_args = []
                while self.peek() not in (')', None):
                    fn_args.append(self.parse_type())
                    if not self.eat(','):
                        break
                self.eat(')')
                fn_ret = ('tuple', [])
                if self.eat('->'):
                    fn_ret = self.parse_type()
            if not self.eat('::'):
                break
        return ('path', segs, args, assoc, fn_args, fn_ret)


PRIM = {'bool': 'bool', 'f32': 'float', 'f64': 'float', 'char': 'string', 'str': 'string',
        'String': 'string'}
WRAPPERS = {'Box', 'Rc', 'Arc', 'RefCell', 'Cell', 'Mutex', 'RwLock', 'ManuallyDrop', 'Pin',
            'OnceCell', 'Reverse', 'Wrapping'}
VECS = {'Vec', 'VecDeque', 'SmallVec', 'BinaryHeap', 'LinkedList'}
MAPS = {'HashMap', 'FxHashMap', 'BTreeMap', 'IndexMap'}
SETS = {'HashSet', 'FxHashSet', 'BTreeSet', 'IndexSet'}
STRINGLIKE = {'string'}


class Ctx:
    def __init__(self, fi, self_type=None, generics=None, fn_bounds=None, field_name=None):
        self.fi = fi
        self.self_type = self_type
        self.generics = generics or []
        self.fn_bounds = fn_bounds or {}   # generic name -> translated type
        self.field_name = field_name


def is_u8(t):
    return t[0] == 'path' and t[1][-1] == 'u8' and not t[2]


def tr(t, ctx, pos='value'):
    """Translate a parsed Rust type into BAML type text."""
    k = t[0]
    if k == 'ref':
        return tr(t[2], ctx, pos)
    if k == 'ptr':
        return 'int'
    if k == 'lifetime':
        return 'unknown'
    if k == 'never':
        return 'never'
    if k == 'infer':
        return 'unknown'
    if k == 'tuple':
        elems = t[1]
        if not elems:
            return 'void' if pos == 'ret' else 'null'
        if len(elems) == 1:
            return tr(elems[0], ctx)
        if len(elems) > 6:
            return 'unknown /* PORT-TYPE: tuple>6 */'
        return f'root.std.Tuple{len(elems)}<' + ', '.join(tr(e, ctx) for e in elems) + '>'
    if k == 'slice':
        if is_u8(t[1]):
            return 'uint8array'
        return arr(tr(t[1], ctx))
    if k == 'fn':
        return fn_type([tr(p, ctx) for p in t[1]], tr(t[2], ctx, 'ret'))
    if k in ('dyn', 'impl'):
        for b in t[1]:
            name = b[1][-1]
            if name in ('Fn', 'FnMut', 'FnOnce') and b[4] is not None:
                return fn_type([tr(p, ctx) for p in b[4]], tr(b[5], ctx, 'ret'))
            if name in ('Iterator', 'IntoIterator', 'DoubleEndedIterator', 'ExactSizeIterator'):
                item = b[3].get('Item')
                return arr(tr(item, ctx)) if item else 'unknown[]'
            if name == 'Any':
                return 'unknown'
            if name in ('Into', 'AsRef', 'ToString', 'Display', 'Borrow') and (b[2] or name in ('ToString', 'Display')):
                if name in ('ToString', 'Display'):
                    return 'string'
                return tr(b[2][0], ctx)
        for b in t[1]:
            name = b[1][-1]
            if name in ('Send', 'Sync', 'Debug', 'Clone', 'Copy', 'Sized', 'Unpin', 'PartialEq', 'Eq', 'Hash'):
                continue
            r = lookup_type(ctx.fi, name)
            if r:
                return qualify(ctx.fi, r[0], name)
        return 'unknown /* PORT-TYPE: ' + ' '.join(str(x) for x in t[1]) + ' */'
    if k == 'path':
        return tr_path(t, ctx, pos)
    return 'unknown'


def arr(inner):
    if inner.endswith('?') or ' ' in inner and not inner.startswith('root.std.Tuple') and not inner.startswith('map<'):
        return '(' + inner + ')[]'
    if inner.startswith('(') and '->' in inner:
        return '(' + inner + ')[]'
    return inner + '[]'


def opt(inner):
    if inner == 'void':
        return 'null'
    if inner.endswith('?'):
        return 'root.std.Some<' + inner + '>?'
    if inner == 'null' or inner == 'unknown' or inner.startswith('unknown '):
        return inner
    if '->' in inner and not inner.startswith('('):
        return '(' + inner + ')?'
    if ' | ' in inner:
        return '(' + inner + ')?'
    return inner + '?'


def fn_type(params, ret):
    return '(' + ', '.join(params) + ') -> ' + ret + ' throws unknown'


def tr_path(t, ctx, pos):
    _, segs, args, assoc, fn_args, fn_ret = t
    name = segs[-1]
    fi = ctx.fi
    if name in ('Fn', 'FnMut', 'FnOnce') and fn_args is not None:
        return fn_type([tr(p, ctx) for p in fn_args], tr(fn_ret, ctx, 'ret'))
    if name in PRIM:
        return PRIM[name]
    if name in INT_TYPES:
        if name == 'u64' and (fi.module in BIGINT_U64_MODULES or (ctx.field_name and re.search(r'hash|digest|bits', ctx.field_name))):
            return 'bigint'
        return 'int'
    if name in ('u128', 'i128'):
        return 'bigint'
    if name == 'Self' and ctx.self_type:
        return ctx.self_type
    if len(segs) == 1 and name in ctx.fn_bounds:
        return ctx.fn_bounds[name]
    if len(segs) == 1 and name in ctx.generics:
        return name
    if name == 'Option':
        return opt(tr(args[0], ctx)) if args else 'unknown?'
    if name == 'Result':
        if pos == 'ret':
            return tr(args[0], ctx, 'ret') if args else 'void'
        a = tr(args[0], ctx) if args else 'null'
        e = tr(args[1], ctx) if len(args) > 1 else 'root.error.Error'
        if a == 'void':
            a = 'null'
        return f'root.std.Ok<{a}> | root.std.Err<{e}>'
    if name in VECS:
        if args and is_u8(args[0]) and name == 'Vec':
            return 'uint8array'
        return arr(tr(args[0], ctx)) if args else 'unknown[]'
    if name == 'Weak':
        return opt(tr(args[0], ctx)) if args else 'unknown?'
    if name == 'Cow':
        return tr(args[0], ctx) if args else 'string'
    if name in WRAPPERS:
        if not args:
            return 'unknown'
        inner = args[0]
        if inner[0] == 'path' and inner[1][-1] == 'str':
            return 'string'
        if inner[0] == 'slice':
            return tr(inner, ctx)
        return tr(inner, ctx, pos)
    if name in MAPS:
        if len(args) >= 2:
            key = tr(args[0], ctx)
            v = tr(args[1], ctx)
            note = '' if key in ('string',) else f' /* key: {key} */'
            return f'map<string, {v}>{note}'
        return 'map<string, unknown>'
    if name in SETS:
        if args:
            key = tr(args[0], ctx)
            note = '' if key == 'string' else f' /* key: {key} */'
            return f'map<string, bool>{note}'
        return 'map<string, bool>'
    if name in ('PathBuf', 'Path', 'OsStr', 'OsString'):
        return 'string'
    if name == 'Ordering' and ('cmp' in segs or len(segs) == 1 and 'Ordering' not in type_defs):
        return 'baml.ops.Ordering'
    if name in ('AtomicUsize', 'AtomicU32', 'AtomicU64', 'AtomicIsize', 'AtomicPtr', 'NonNull'):
        return 'int'
    if name == 'AtomicBool':
        return 'bool'
    if name in ('Instant', 'SystemTime'):
        return 'bigint'
    if name == 'Duration':
        return 'baml.time.Duration'
    if name == 'ExitCode':
        return 'int'
    if name == 'Error' and ('io' in segs):
        return 'baml.errors.Io'
    if name == 'Any':
        return 'unknown'
    if name in ('Chars', 'CharIndices', 'Bytes'):
        return 'string[]'
    if name in ('Iter', 'IntoIter', 'Peekable', 'Rev', 'Enumerate', 'Split', 'Lines'):
        return arr(tr(args[0], ctx)) if args else 'unknown[]'
    if name in ('Layout',):
        return 'int'
    if name == 'Range' and args:
        return 'root.std.Tuple2<int, int>'
    if name in ('Formatter', 'Arguments'):
        return 'unknown'
    # user types
    if len(segs) > 1 and segs[0] in ('crate', 'super', 'self', 'sasso'):
        modpath = resolve_module_path(fi, segs[:-1])
        cands = type_defs.get(name, [])
        hit = None
        for (m, kind, rel) in cands:
            if m == modpath:
                hit = (m, kind)
        if not hit and cands:
            pref = [c for c in cands if c[0].startswith(modpath or '')] or cands
            hit = (pref[0][0], pref[0][1])
        r = hit
    else:
        r = lookup_type(fi, name)
    if r is None:
        # FxHashMap alias etc.
        if name in fi.uses:
            orig = fi.uses[name][-1]
            if orig != name:
                return tr_path(('path', [orig], args, assoc, fn_args, fn_ret), ctx, pos)
        return f'unknown /* PORT-TYPE: {"::".join(segs)} */'
    mod, kind = r
    if kind == 'type' and (mod, name) in aliases and generic_arity.get((mod, name)):
        # generic alias: BAML has none; expand it
        text = aliases[(mod, name)]
        params = generic_arity[(mod, name)]
        sub = {p: tr(a, ctx) for p, a in zip(params, args)}
        ctx2 = Ctx(files_by_module(mod), fn_bounds=sub, generics=list(sub))
        return tr(TP(tokenize(text)).parse_type(), ctx2, pos)
    q = qualify(fi, mod, name)
    gp = generic_arity.get((mod, name), [])
    targs = [a for a in args if a[0] != 'lifetime']
    if gp and targs:
        q += '<' + ', '.join(tr(a, ctx) for a in targs) + '>'
    return q


def files_by_module(mod):
    for fi in files.values():
        if fi.module == mod:
            return fi
    return None


def translate(text, ctx, pos='value'):
    text = text.strip()
    if not text:
        return 'void' if pos == 'ret' else 'unknown'
    t = TP(tokenize(text)).parse_type()
    return tr(t, ctx, pos)


def translate_param_type(text, ctx):
    t = TP(tokenize(text)).parse_type()
    if t[0] == 'ref' and t[1]:  # &mut X
        inner = t[2]
        if inner[0] == 'path':
            n = inner[1][-1]
            if n == 'String':
                return 'root.std.StrBuf'
            if n in INT_TYPES or n in ('f64', 'f32', 'bool', 'char', 'Option', 'u128', 'i128') or n in ctx.generics:
                return 'root.std.Cell<' + tr(inner, ctx) + '>'
            if n == 'str':
                return 'root.std.StrBuf'
            r = lookup_type(ctx.fi, n) if n not in PRIM and n not in VECS and n not in MAPS and n not in SETS and n not in WRAPPERS else None
            if r and r[1] == 'enum' and enum_kind.get((r[0], n)) == 'CLIKE':
                return 'root.std.Cell<' + tr(inner, ctx) + '>'
            if r and r[1] == 'enum' and enum_kind.get((r[0], n)) == 'DATA':
                return 'root.std.Cell<' + tr(inner, ctx) + '>'
        if inner[0] == 'tuple':
            return 'root.std.Cell<' + tr(inner, ctx) + '>'
        return tr(inner, ctx)
    return tr(t, ctx)


# --------------------------------------------------------------------------
# Signature parsing

def parse_fn(header):
    """header: clean text from `fn` to before the body. Returns dict."""
    h = ' '.join(header.split())
    m = re.search(r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)', h)
    name = m.group(1)
    i = m.end()
    generics_txt = ''
    if i < len(h) and h[i] == '<':
        j = match_close(h, i, '<', '>')
        generics_txt = h[i + 1:j]
        i = j + 1
    while i < len(h) and h[i] != '(':
        i += 1
    j = match_close(h, i, '(', ')')
    params_txt = h[i + 1:j]
    rest = h[j + 1:]
    ret = ''
    where = ''
    wm = re.search(r'\bwhere\b', rest)
    if wm:
        where = rest[wm.end():]
        rest = rest[:wm.start()]
    rm = re.match(r'\s*->\s*(.*)$', rest)
    if rm:
        ret = rm.group(1).strip()
    return dict(name=name, generics=generics_txt, params=params_txt, ret=ret, where=where)


def generic_info(fn, ctx_fi, outer_generics):
    """-> (type param names kept, bounds map name->baml type)."""
    names = []
    bounds_txt = {}
    for p in split_top(fn['generics']):
        p = p.strip()
        if not p or p.startswith("'") or p.startswith('const '):
            continue
        nm = re.split(r'[:=\s]', p)[0]
        names.append(nm)
        if ':' in p:
            bounds_txt[nm] = p.split(':', 1)[1]
    for w in split_top(fn['where']):
        w = w.strip()
        if ':' in w:
            nm, b = w.split(':', 1)
            nm = nm.strip()
            if nm in names:
                bounds_txt[nm] = (bounds_txt.get(nm, '') + ' + ' + b) if nm in bounds_txt else b
    kept = []
    fb = {}
    base_ctx = Ctx(ctx_fi, generics=outer_generics + names)
    # resolve bounds that do not mention other params first
    names = sorted(names, key=lambda n: sum(1 for o in names if o != n and re.search(r'\b' + o + r'\b', bounds_txt.get(n, ''))))
    for nm in names:
        base_ctx = Ctx(ctx_fi, generics=outer_generics + names, fn_bounds=fb)
        b = bounds_txt.get(nm, '')
        bt = TP(tokenize(b)).parse_bounds() if b.strip() else []
        mapped = None
        for bb in bt:
            bn = bb[1][-1]
            if bn in ('Fn', 'FnMut', 'FnOnce') and bb[4] is not None:
                mapped = fn_type([tr(x, base_ctx) for x in bb[4]], tr(bb[5], base_ctx, 'ret'))
            elif bn in ('Into', 'AsRef', 'Borrow') and bb[2]:
                mapped = tr(bb[2][0], base_ctx)
            elif bn in ('ToString', 'Display'):
                mapped = 'string'
            elif bn in ('IntoIterator', 'Iterator'):
                item = bb[3].get('Item')
                if item is not None:
                    mapped = arr(tr(item, Ctx(ctx_fi, generics=outer_generics + names, fn_bounds=fb)))
        if mapped:
            fb[nm] = mapped
        else:
            kept.append(nm)
    return kept, fb


def fmt_params(fn, ctx, is_method_ok=True):
    params = []
    has_self = False
    idx = 0
    for p in split_top(fn['params']):
        p = p.strip()
        if not p:
            continue
        p = re.sub(r'#\[[^\]]*\]\s*', '', p)
        if re.match(r'^(&\s*(\'[a-z_]+\s+)?)?(mut\s+)?self\b', p):
            has_self = True
            continue
        if ':' not in p:
            continue
        pat, ty = p.split(':', 1)
        pat = pat.strip()
        pat = re.sub(r'^(ref\s+)?(mut\s+)?', '', pat)
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', pat):
            nm = pat
            if nm == '_':
                nm = f'unused_{idx}'
            elif nm.startswith('_') and len(nm) > 1:
                nm = nm.lstrip('_') or f'unused_{idx}'
                nm = 'unused_' + nm
        else:
            nm = f'arg_{idx}'
        params.append(f'{safe(nm)}: {translate_param_type(ty, ctx)}')
        idx += 1
    return has_self, params


# --------------------------------------------------------------------------
# Emission

class Out:
    def __init__(self):
        self.lines = []

    def emit(self, s='', ind=0):
        if s == '':
            self.lines.append('')
        else:
            for line in s.split('\n'):
                self.lines.append(('    ' * ind + line) if line else '')

    def comments(self, cl, ind=0):
        for c in cl:
            self.emit(c, ind)


STUB = 'root.std.todo()'


def fn_decl(fi, it_src_header, ctx, ind, name_override=None, static_ok=True, in_interface=False, stub=True, force_self=None, rename_map=None):
    fn = parse_fn(it_src_header)
    kept, fb = generic_info(fn, fi, ctx.generics)
    c2 = Ctx(fi, self_type=ctx.self_type, generics=ctx.generics + kept, fn_bounds={**ctx.fn_bounds, **fb})
    has_self, params = fmt_params(fn, c2)
    ret = translate(fn['ret'], c2, 'ret') if fn['ret'] else 'void'
    if fn['ret'].strip() == 'Self' and ctx.self_type:
        ret = ctx.self_type
    name = name_override or safe(fn['name'])
    if name in ('to_json', 'to_string', 'from_json'):
        name = name + '_'
    if rename_map and fn['name'] in rename_map:
        name = rename_map[fn['name']]
    g = ('<' + ', '.join(kept) + '>') if kept else ''
    plist = (['self'] if has_self else []) + params
    sig = f'function {name}{g}({", ".join(plist)}) -> {ret}'
    if in_interface:
        sig += ' throws ' + (in_interface if isinstance(in_interface, str) else 'unknown')
    return fn, has_self, sig


def returns_result(hdr):
    fn = parse_fn(hdr)
    return bool(re.match(r'^(std::result::|io::|fmt::)?Result\b', fn['ret'].strip()))


STUB_THROWS = 'root.std.todo_throws()'


def emit_fn(out, sig, ind, body=STUB, interface_only=False):
    if interface_only:
        out.emit(sig, ind)
        return
    out.emit(sig + ' {', ind)
    out.emit(body, ind + 1)
    out.emit('}', ind)


LITERAL_NUM = re.compile(r'^-?(0x[0-9a-fA-F_]+|0b[01_]+|0o[0-7_]+|[0-9][0-9_]*(\.[0-9_]*)?([eE][+-]?[0-9_]+)?)(u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|isize|f32|f64)?$')


def split_top_spans(clean):
    """Like split_top(',') but returns (start, end) spans."""
    spans, depth, st = [], 0, 0
    for i, c in enumerate(clean):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            spans.append((st, i))
            st = i + 1
    spans.append((st, len(clean)))
    return spans


def strip_comments(txt):
    out = []
    for line in txt.split('\n'):
        out.append(line)
    return '\n'.join(out)


def tr_const_expr(expr, bty, clean=None):
    """Best-effort translation of a const initializer. None if not simple.
    `clean` is `expr` with comments/strings blanked (same offsets)."""
    if clean is None:
        clean = blank_comments_strings(expr)
    lo = len(clean) - len(clean.lstrip())
    hi = len(clean.rstrip())
    e_src, e_cl = expr[lo:hi], clean[lo:hi]
    if bty in ('int', 'bigint', 'float', 'bool', 'string'):
        return tr_scalar(e_src, bty)
    if bty.endswith('[]') and e_cl.startswith('[') and e_cl.endswith(']'):
        elem = bty[:-2]
        if elem.startswith('(') and elem.endswith(')'):
            elem = elem[1:-1]
        inner_src, inner_cl = e_src[1:-1], e_cl[1:-1]
        spans = split_top_spans(inner_cl)
        outp = []
        for (a, b) in spans:
            p_cl = inner_cl[a:b]
            if not p_cl.strip():
                continue
            if ';' in p_cl and len(spans) == 1:
                return None
            p_src = inner_src[a:b]
            l2 = len(p_cl) - len(p_cl.lstrip())
            h2 = len(p_cl.rstrip())
            p_src, p_cl = p_src[l2:h2], p_cl[l2:h2]
            v = tr_scalar(p_src, elem)
            if v is None:
                if elem.endswith('[]') and p_cl.startswith('['):
                    v = tr_const_expr(p_src, elem, p_cl)
                elif elem.startswith('root.std.Tuple') and p_cl.startswith('('):
                    inner = elem[elem.find('<') + 1:-1]
                    tys = [x.strip() for x in split_top(inner)]
                    vs = [sp for sp in split_top_spans(p_cl[1:-1]) if p_cl[1:-1][sp[0]:sp[1]].strip()]
                    if len(tys) == len(vs):
                        fields = []
                        for n_, (ty_, (va, vb)) in enumerate(zip(tys, vs)):
                            tv = tr_const_expr(p_src[1:-1][va:vb], ty_, p_cl[1:-1][va:vb])
                            if tv is None:
                                return None
                            fields.append(f'_{n_}: {tv}')
                        v = 'root.std.Tuple' + str(len(tys)) + ' { ' + ', '.join(fields) + ' }'
            if v is None:
                return None
            outp.append(v)
        if len(outp) > 8 or any('\n' in x for x in outp):
            return '[\n' + ''.join('    ' + x.replace('\n', '\n    ') + ',\n' for x in outp) + ']'
        return '[' + ', '.join(outp) + ']'
    return None


def tr_scalar(e, bty):
    e = e.strip()
    if bty == 'bool' and e in ('true', 'false'):
        return e
    if bty == 'string':
        if re.match(r'^"(?:[^"\\]|\\.)*"$', e, re.S) or re.match(r'^r(#*)".*"\1$', e, re.S):
            return rust_str_to_baml(e)
        m = re.match(r"^'(\\u\{[0-9a-fA-F]+\}|\\x[0-9a-fA-F]{2}|\\.|[^\\'])'$", e)
        if m:
            return rust_str_to_baml('"' + m.group(1).replace('"', '\\"') + '"')
        return None
    if bty in ('int', 'bigint', 'float'):
        neg = e.startswith('-')
        body = e[1:].strip() if neg else e
        m = LITERAL_NUM.match(body)
        if not m:
            fb = re.match(r'^f64::from_bits\((0x[0-9a-fA-F_]+)(?:u64)?\)$', body)
            if fb and bty == 'float':
                return f'root.std.f64_from_bits({fb.group(1)}n)'
            if body in ('f64::INFINITY', 'f64::NEG_INFINITY', 'f64::NAN', 'f64::EPSILON', 'f64::MAX', 'f64::MIN_POSITIVE'):
                return f'root.std.F64_{body.split("::")[1]}()'
            if body in ('usize::MAX', 'u64::MAX', 'i64::MAX'):
                return 'root.std.INT_MAX()'
            if body == 'u32::MAX':
                return '4294967295'
            return None
        num = m.group(1)
        if re.match(r'^0[xX]', num):
            # hex digits include `f`: only `u..`/`i..` can be a suffix here
            num = re.sub(r'(u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|isize)$', '', num)
        else:
            num = re.sub(r'(u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|isize|f32|f64)$', '', num)
        num = num.rstrip('_')
        if bty == 'float':
            if re.match(r'^0[xbo]', num):
                return None
            if '.' not in num and 'e' not in num.lower():
                num += '.0'
            if num.endswith('.'):
                num += '0'
        elif bty == 'bigint':
            num += 'n'
        else:
            if '.' in num:
                return None
            # BAML int is 63-bit
            try:
                v = int(num.replace('_', ''), 0)
                if v >= 2 ** 62:
                    return None
            except ValueError:
                pass
        return ('-' if neg else '') + num
    return None


def rust_str_value(lit):
    """Decode a Rust string literal (normal or raw) to its value."""
    m = re.match(r'^b?r(#*)"(.*)"\1$', lit, re.S)
    if m:
        return m.group(2)
    body = lit[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c != '\\':
            out.append(c)
            i += 1
            continue
        n = body[i + 1]
        if n == '\n':
            i += 2
            while i < len(body) and body[i] in ' \t\n\r':
                i += 1
            continue
        simple = {'n': '\n', 't': '\t', 'r': '\r', '0': '\0', '\\': '\\', '"': '"', "'": "'"}
        if n in simple:
            out.append(simple[n])
            i += 2
        elif n == 'x':
            out.append(chr(int(body[i + 2:i + 4], 16)))
            i += 4
        elif n == 'u':
            j = body.index('}', i)
            out.append(chr(int(body[i + 3:j], 16)))
            i = j + 1
        else:
            out.append(n)
            i += 2
    return ''.join(out)


def baml_str(value):
    """Encode a Python string as a BAML expression (string literal, or a
    concatenation with `root.std.chr_unchecked` for characters BAML string
    literals cannot spell)."""
    esc = {'\n': '\\n', '\t': '\\t', '\r': '\\r', '\0': '\\0', '\b': '\\b', '\v': '\\v', '\f': '\\f', '\\': '\\\\', '"': '\\"'}
    parts = []
    cur = []
    for ch in value:
        cp = ord(ch)
        if ch in esc:
            cur.append(esc[ch])
        elif cp < 0x20 or cp == 0x7f or 0x80 <= cp < 0xa0 or cp in (0xfeff, 0x200b, 0x200c, 0x200d, 0x2028, 0x2029, 0xad) or 0xd800 <= cp <= 0xdfff or 0xe000 <= cp <= 0xf8ff or cp >= 0xf0000:
            parts.append('"' + ''.join(cur) + '"')
            cur = []
            parts.append(f'root.std.chr_unchecked({hex(cp)})')
        else:
            cur.append(ch)
    if cur or not parts:
        parts.append('"' + ''.join(cur) + '"')
    parts = [p for p in parts if p != '""'] or ['""']
    return ' + '.join(parts)


def rust_str_to_baml(lit):
    return baml_str(rust_str_value(lit))


def emit_struct(out, fi, it, impls, trait_impls):
    head_clean = fi.clean[it.kw_pos:it.b]
    head_src = fi.src[it.kw_pos:it.b]
    m = re.match(r'struct\s+([A-Za-z_][A-Za-z0-9_]*)', head_clean)
    name = m.group(1)
    gps = generic_arity.get((fi.module, name), [])
    self_type = name + (('<' + ', '.join(gps) + '>') if gps else '')
    ctx = Ctx(fi, self_type=self_type, generics=gps)
    out.comments(leading_comments(fi.src, fi.clean, it.a, it.kw_pos))
    out.emit(f'class {name}{"<" + ", ".join(gps) + ">" if gps else ""} {{')
    fields = []
    brace = head_clean.find('{')
    paren = head_clean.find('(')
    if brace >= 0 and (paren < 0 or brace < paren or head_clean[:brace].count('(') == 0):
        body_lo = it.kw_pos + brace + 1
        body_hi = it.kw_pos + head_clean.rfind('}')
        parts = split_top(fi.clean[body_lo:body_hi])
        off = body_lo
        for p in parts:
            p_src = fi.src[off:off + len(p)]
            off += len(p) + 1
            cm = leading_comments(p_src, p, 0, len(p_src) - len(p_src.lstrip('\n')) if False else None) if False else None
            fm = re.match(r'\s*((?:#\[[^\]]*\]\s*)*)(?:pub(?:\s*\([^)]*\))?\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)$', p, re.S)
            if not fm:
                continue
            if cfg_excluded(fm.group(1) or ''):
                continue
            # comments for the field
            fstart = p.find(fm.group(2), len(fm.group(1) or '')) if False else None
            lines = []
            for line in p_src.split('\n'):
                st = line.strip()
                if st.startswith('///'):
                    lines.append(st)
                elif st.startswith('//'):
                    lines.append(st)
            fname = fm.group(2)
            fty = translate(fm.group(3), Ctx(fi, self_type=self_type, generics=gps, field_name=fname))
            fields.append(fname)
            out.comments(lines, 1)
            out.emit(f'{safe(fname)}: {fty},', 1)
    elif paren >= 0:
        j = match_close(head_clean, paren, '(', ')')
        parts = split_top(head_clean[paren + 1:j])
        k = 0
        for p in parts:
            p = re.sub(r'#\[[^\]]*\]', '', p).strip()
            p = re.sub(r'^pub(\s*\([^)]*\))?\s+', '', p)
            if not p:
                continue
            out.emit(f'_{k}: {translate(p, ctx)},', 1)
            fields.append(f'_{k}')
            k += 1
    rename = {}
    fset = set(fields)
    # methods from inherent impls
    for imp in impls:
        emit_impl_methods(out, fi, imp, ctx, fset, rename, ind=1)
    for timp in trait_impls:
        emit_trait_impl(out, fi, timp, ctx, fset, rename, ind=1)
    out.emit('}')
    out.emit('')
    return rename


def impl_method_items(fi, imp):
    head = fi.clean[imp.kw_pos:imp.b]
    lo = imp.kw_pos + head.find('{') + 1
    hi = imp.kw_pos + head.rfind('}')
    return parse_items(fi.src, fi.clean, lo, hi)


def emit_impl_methods(out, fi, imp, ctx, fset, rename, ind, mode='class', enum_name=None, statics=None):
    """mode: class (methods + static fns in class body), interface-default (enum
    interface with default bodies; statics collected), clike (implements block;
    statics collected), split-iface / split-impl."""
    for m in impl_method_items(fi, imp):
        if cfg_excluded(m.attrs):
            continue
        cl = leading_comments(fi.src, fi.clean, m.a, m.kw_pos)
        head = fi.clean[m.kw_pos:m.b]
        if m.kind in ('fn', 'const fn'):
            hdr = head[:head.find('{')] if '{' in head else head.rstrip(';')
            fn = parse_fn(hdr)
            has_self = bool(re.search(r'(^|[(,\s])(&\s*(\'[a-z_]+\s+)?)?(mut\s+)?self\s*(,|\)|:)', fn['params'].strip() + ')'))
            nm = safe(fn['name'])
            if has_self and fn['name'] in fset:
                nm = fn['name'] + '_'
                rename[fn['name']] = nm
            if not has_self and statics is not None:
                statics.append((cl, hdr, m))
                continue
            if mode == 'interface-default':
                thr = 'unknown' if returns_result(hdr) else 'never'
            elif mode in ('split-iface', 'clike-iface'):
                thr = 'unknown'
            else:
                thr = None
            _, _, sig = fn_decl(fi, hdr, ctx, ind, name_override=nm, in_interface=thr)
            out.comments(cl, ind)
            if mode in ('split-iface', 'clike-iface'):
                emit_fn(out, sig, ind, interface_only=True)
            elif thr == 'unknown':
                emit_fn(out, sig, ind, body=STUB_THROWS)
            else:
                emit_fn(out, sig, ind)
            out.emit('')
        elif m.kind == 'const':
            mm = re.match(r'const\s+([A-Za-z_0-9]+)\s*:\s*(.*?)=(.*);?$', ' '.join(head.split()).rstrip(';'), re.S)
            if mm:
                if statics is not None:
                    statics.append((cl, None, m))
                    continue
                bty = translate(mm.group(2), ctx)
                val = tr_const_expr(' '.join(fi.src[m.kw_pos:m.b].split()).split('=', 1)[1].rstrip(';'), bty)
                out.comments(cl, ind)
                emit_fn(out, f'function {mm.group(1)}() -> {bty}', ind, body=val or STUB)
                out.emit('')
        elif m.kind == 'type':
            out.comments(cl, ind)
            out.emit('// PORT: associated type ' + ' '.join(head.split()), ind)


def emit_trait_impl(out, fi, timp, ctx, fset, rename, ind):
    head = ' '.join(fi.clean[timp.kw_pos:timp.b].split())
    hdr = head[:head.find('{')]
    tm = re.match(r'impl(?:<[^>]*>)?\s+(.*?)\s+for\s+', hdr)
    trait = tm.group(1).strip() if tm else '?'
    tname = re.sub(r'<.*', '', trait).split('::')[-1]
    methods = [m for m in impl_method_items(fi, timp) if not cfg_excluded(m.attrs)]
    cl = leading_comments(fi.src, fi.clean, timp.a, timp.kw_pos)
    out.comments(cl, ind)
    if tname == 'Display':
        out.emit('implements baml.ToString {', ind)
        out.emit('function to_string(self) -> string {', ind + 1)
        out.emit(STUB, ind + 2)
        out.emit('}', ind + 1)
        out.emit('}', ind)
        out.emit('')
        return
    if tname == 'PartialEq':
        out.emit('implements baml.ops.Equals {', ind)
        out.emit(f'function eq(self, other: {ctx.self_type}) -> bool {{', ind + 1)
        out.emit(STUB, ind + 2)
        out.emit('}', ind + 1)
        out.emit('}', ind)
        out.emit('')
        return
    if tname in ('Debug', 'Eq', 'Hash', 'Clone', 'Copy', 'Send', 'Sync', 'PartialOrd', 'Ord', 'Error'):
        out.emit(f'// PORT: `impl {trait}` dropped (derive-like / not needed in BAML).', ind)
        out.emit('')
        return
    if tname == 'Default':
        out.emit(f'function default() -> {ctx.self_type} {{', ind)
        out.emit(STUB, ind + 1)
        out.emit('}', ind)
        out.emit('')
        return
    r = lookup_type(fi, tname)
    if r and r[1] == 'trait':
        iface = qualify(fi, r[0], tname)
        out.emit(f'implements {iface} {{', ind)
        for m in methods:
            mcl = leading_comments(fi.src, fi.clean, m.a, m.kw_pos)
            mh = fi.clean[m.kw_pos:m.b]
            if m.kind in ('fn', 'const fn'):
                mhdr = mh[:mh.find('{')] if '{' in mh else mh
                _, _, sig = fn_decl(fi, mhdr, ctx, ind + 1)
                out.comments(mcl, ind + 1)
                emit_fn(out, sig, ind + 1)
        out.emit('}', ind)
        out.emit('')
        return
    # other std traits (Hasher, Drop, Deref, GlobalAlloc, ...): plain methods
    out.emit(f'// PORT: `impl {trait}` — methods kept as plain methods.', ind)
    for m in methods:
        mcl = leading_comments(fi.src, fi.clean, m.a, m.kw_pos)
        mh = fi.clean[m.kw_pos:m.b]
        if m.kind in ('fn', 'const fn'):
            mhdr = mh[:mh.find('{')] if '{' in mh else mh
            fn = parse_fn(mhdr)
            nm = safe(fn['name'])
            if fn['name'] in fset:
                nm = fn['name'] + '_'
            _, _, sig = fn_decl(fi, mhdr, ctx, ind, name_override=nm)
            out.comments(mcl, ind)
            emit_fn(out, sig, ind)
            out.emit('')
        elif m.kind == 'type':
            out.emit('// PORT: ' + ' '.join(mh.split()), ind)


def emit_enum(out, fi, it, impls, trait_impls):
    head_clean = fi.clean[it.kw_pos:it.b]
    m = re.match(r'enum\s+([A-Za-z_][A-Za-z0-9_]*)', head_clean)
    name = m.group(1)
    kind = enum_kind[(fi.module, name)]
    gps = generic_arity.get((fi.module, name), [])
    out.comments(leading_comments(fi.src, fi.clean, it.a, it.kw_pos))
    body_lo = it.kw_pos + head_clean.find('{') + 1
    body_hi = it.kw_pos + head_clean.rfind('}')
    parts = split_top(fi.clean[body_lo:body_hi])
    variants = []
    off = body_lo
    for p in parts:
        p_src = fi.src[off:off + len(p)]
        off += len(p) + 1
        vm = re.match(r'\s*((?:#\[[^\]]*\]\s*)*)([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$', p, re.S)
        if not vm:
            continue
        if cfg_excluded(vm.group(1)):
            continue
        cl = [('///' + l.strip()[3:]) if l.strip().startswith('///') else l.strip() for l in p_src.split('\n') if l.strip().startswith('//')]
        variants.append((vm.group(2), vm.group(3).strip(), cl, '#[default]' in vm.group(1).replace(' ', '')))
    statics = []
    if kind == 'CLIKE':
        out.emit(f'enum {name} {{')
        for vn, rest, cl, dflt in variants:
            out.comments(cl, 1)
            out.emit(f'{vn},', 1)
        out.emit('}')
        out.emit('')
        methods_exist = False
        for imp in impls:
            for mi in impl_method_items(fi, imp):
                if mi.kind in ('fn', 'const fn') and not cfg_excluded(mi.attrs):
                    hh = fi.clean[mi.kw_pos:mi.b]
                    fnp = parse_fn(hh[:hh.find('{')] if '{' in hh else hh)
                    if re.search(r'\bself\b', fnp['params']):
                        methods_exist = True
        ctx = Ctx(fi, self_type=name)
        if methods_exist:
            out.emit(f'interface {name}Methods {{')
            dummy = []
            for imp in impls:
                emit_impl_methods(out, fi, imp, ctx, set(), {}, ind=1, mode='clike-iface', statics=dummy)
            out.emit('}')
            out.emit('')
            out.emit(f'implements {name}Methods for {name} {{')
            for imp in impls:
                emit_impl_methods(out, fi, imp, ctx, set(), {}, ind=1, mode='clike', statics=statics)
            out.emit('}')
            out.emit('')
        else:
            for imp in impls:
                emit_impl_methods(out, fi, imp, ctx, set(), {}, ind=0, mode='clike', statics=statics)
        for vn, rest, cl, dflt in variants:
            if dflt:
                out.emit(f'/// derive(Default): `{name}::{vn}`.')
                out.emit(f'function {name}_default() -> {name} {{')
                out.emit(f'{name}.{vn}', 1)
                out.emit('}')
                out.emit('')
        for timp in trait_impls:
            emit_enum_trait_impl(out, fi, timp, name, kind)
    else:
        g = ('<' + ', '.join(gps) + '>') if gps else ''
        self_type = name + g
        ctx = Ctx(fi, self_type=self_type, generics=gps)
        out.emit(f'interface {name}{g} {{')
        for imp in impls:
            emit_impl_methods(out, fi, imp, ctx, set(), {}, ind=1, mode='interface-default', statics=statics)
        for timp in trait_impls:
            head = ' '.join(fi.clean[timp.kw_pos:timp.b].split())
            tm = re.match(r'impl(?:<[^>]*>)?\s+(.*?)\s+for\s+', head)
            tname = re.sub(r'<.*', '', tm.group(1)).split('::')[-1] if tm else '?'
            if tname in ('Display', 'PartialEq', 'Default'):
                out.emit(f'// PORT: `impl {tname} for {name}` — see the variant classes / free fns.', 1)
            elif tname not in ('Debug', 'Eq', 'Hash', 'Clone', 'Copy'):
                for mi in impl_method_items(fi, timp):
                    if mi.kind in ('fn', 'const fn'):
                        hh = fi.clean[mi.kw_pos:mi.b]
                        hh2 = hh[:hh.find('{')] if '{' in hh else hh
                        thr = 'unknown' if returns_result(hh2) else 'never'
                        _, _, sig = fn_decl(fi, hh2, ctx, 1, in_interface=thr)
                        out.comments(leading_comments(fi.src, fi.clean, mi.a, mi.kw_pos), 1)
                        emit_fn(out, sig, 1, body=STUB_THROWS if thr == 'unknown' else STUB)
        out.emit('}')
        out.emit('')
        for vn, rest, cl, dflt in variants:
            cname = f'{name}_{vn}'
            out.comments(cl)
            out.emit(f'class {cname}{g} {{')
            if rest.startswith('('):
                j = match_close(rest, 0, '(', ')')
                k = 0
                for p in split_top(rest[1:j]):
                    if p.strip():
                        out.emit(f'_{k}: {translate(p, ctx)},', 1)
                        k += 1
            elif rest.startswith('{'):
                j = match_close(rest, 0, '{', '}')
                # map back to src for comments
                vstart = fi.clean.find(rest[:j + 1], body_lo)
                for p in split_top(rest[1:j]):
                    fm = re.match(r'\s*((?:#\[[^\]]*\]\s*)*)([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)$', p, re.S)
                    if fm:
                        out.emit(f'{safe(fm.group(2))}: {translate(fm.group(3), Ctx(fi, self_type=self_type, generics=gps, field_name=fm.group(2)))},', 1)
            out.emit(f'implements {self_type} {{}}', 1)
            out.emit('}')
            out.emit('')
        if any(d for *_, d in variants):
            for vn, rest, cl, dflt in variants:
                if dflt:
                    out.emit(f'/// derive(Default): `{name}::{vn}`.')
                    out.emit(f'function {name}_default() -> {self_type} {{')
                    out.emit(STUB, 1)
                    out.emit('}')
                    out.emit('')
    # associated fns / consts -> free functions `<Enum>_<fn>`
    ctx = Ctx(fi, self_type=name + (('<' + ', '.join(gps) + '>') if gps else ''), generics=gps)
    for cl, hdr, m in statics:
        if hdr is None:
            head = fi.clean[m.kw_pos:m.b]
            mm = re.match(r'const\s+([A-Za-z_0-9]+)\s*:\s*(.*?)=(.*)$', ' '.join(head.split()).rstrip(';'), re.S)
            if mm:
                bty = translate(mm.group(2), ctx)
                val = tr_const_expr(' '.join(fi.src[m.kw_pos:m.b].split()).split('=', 1)[1].rstrip(';'), bty)
                out.comments(cl)
                emit_fn(out, f'function {name}_{mm.group(1)}() -> {bty}', 0, body=val or STUB)
                out.emit('')
            continue
        fn = parse_fn(hdr)
        _, _, sig = fn_decl(fi, hdr, ctx, 0, name_override=f'{name}_{fn["name"]}')
        out.comments(cl)
        emit_fn(out, sig, 0)
        out.emit('')


def emit_enum_trait_impl(out, fi, timp, name, kind):
    head = ' '.join(fi.clean[timp.kw_pos:timp.b].split())
    tm = re.match(r'impl(?:<[^>]*>)?\s+(.*?)\s+for\s+', head)
    tname = re.sub(r'<.*', '', tm.group(1)).split('::')[-1] if tm else '?'
    out.emit(f'// PORT: `impl {tname} for {name}` — handled at the use sites.')
    out.emit('')


def emit_split_impl(out, fi, imps, tname, tmod):
    """impl blocks for a type defined in another module."""
    iface = tname + pascal(fi.module.split('.')[-1])
    gps = generic_arity.get((tmod, tname), [])
    q = qualify(fi, tmod, tname)
    ctx = Ctx(fi, self_type=q, generics=gps)
    kind = enum_kind.get((tmod, tname))
    fset = struct_fields.get((tmod, tname), set())
    statics = []
    out.emit(f'interface {iface} {{')
    for imp in imps:
        emit_impl_methods(out, fi, imp, ctx, fset, {}, ind=1, mode='split-iface', statics=statics)
    out.emit('}')
    out.emit('')
    out.emit(f'implements {iface} for {q} {{')
    for imp in imps:
        emit_impl_methods(out, fi, imp, ctx, fset, {}, ind=1, mode='split-impl', statics=[])
    out.emit('}')
    out.emit('')
    for cl, hdr, m in statics:
        if hdr is None:
            continue
        fn = parse_fn(hdr)
        _, _, sig = fn_decl(fi, hdr, ctx, 0, name_override=f'{tname}_{fn["name"]}')
        out.comments(cl)
        emit_fn(out, sig, 0)
        out.emit('')


def impl_target(fi, it):
    head = ' '.join(fi.clean[it.kw_pos:it.b].split())
    hdr = head[:head.find('{')]
    hdr = re.sub(r'^unsafe\s+', '', hdr)
    m = re.match(r'impl\s*(<[^{]*?>)?\s*(.*)$', hdr)
    rest = m.group(2).strip()
    trait = None
    if re.search(r'\sfor\s', ' ' + rest + ' '):
        trait, target = re.split(r'\s+for\s+', rest, maxsplit=1)
    else:
        target = rest
    target = re.sub(r'<.*', '', target).strip().split('::')[-1]
    target = re.sub(r'\s*where.*', '', target)
    return trait, target


def emit_file(fi):
    out = Out()
    # file header: //! docs
    first = fi.src.split('\n')
    hdr = []
    for line in first:
        st = line.strip()
        if st.startswith('//!'):
            hdr.append('//' + st[3:])
        elif st == '' and not hdr:
            continue
        else:
            break
    out.emit(f'// Ported from sasso `src/{fi.rel}` (namespace `{fi.module}`).')
    if hdr:
        out.emit('//')
        out.comments(hdr)
    out.emit('')
    # group impls by target
    inherent = defaultdict(list)
    traits = defaultdict(list)
    for it in fi.items:
        if it.kind != 'impl' or cfg_excluded(it.attrs):
            continue
        trait, target = impl_target(fi, it)
        if trait:
            traits[target].append(it)
        else:
            inherent[target].append(it)
    local_types = set()
    for it in fi.items:
        if it.kind in ('struct', 'enum') and not cfg_excluded(it.attrs):
            mm = re.match(r'(?:struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)', fi.clean[it.kw_pos:it.b])
            if mm:
                local_types.add(mm.group(1))
    emitted_split = set()
    for it in fi.items:
        if cfg_excluded(it.attrs):
            if it.kind == 'mod' or is_test(it.attrs):
                continue
            out.comments(leading_comments(fi.src, fi.clean, it.a, it.kw_pos))
            out.emit('// PORT: cfg-excluded item (windows/wasm/test) not ported: ' + ' '.join(fi.clean[it.kw_pos:it.b].split())[:120])
            out.emit('')
            continue
        k = it.kind
        head_clean = fi.clean[it.kw_pos:it.b]
        cl = leading_comments(fi.src, fi.clean, it.a, it.kw_pos)
        if k == 'struct':
            name = re.match(r'struct\s+([A-Za-z_][A-Za-z0-9_]*)', head_clean).group(1)
            emit_struct(out, fi, it, inherent.get(name, []), traits.get(name, []))
        elif k == 'enum':
            name = re.match(r'enum\s+([A-Za-z_][A-Za-z0-9_]*)', head_clean).group(1)
            emit_enum(out, fi, it, inherent.get(name, []), traits.get(name, []))
        elif k == 'impl':
            trait, target = impl_target(fi, it)
            if target in local_types:
                continue  # emitted with the type
            if trait:
                tn = re.sub(r'<.*', '', trait).split('::')[-1]
                r = lookup_type(fi, target)
                out.comments(cl)
                out.emit(f'// PORT: `impl {trait} for {target}` (type defined elsewhere) — methods:')
                if r:
                    ctx = Ctx(fi, self_type=qualify(fi, r[0], target))
                    rt = lookup_type(fi, tn)
                    if rt and rt[1] == 'trait':
                        out.emit(f'implements {qualify(fi, rt[0], tn)} for {qualify(fi, r[0], target)} {{')
                        for m in impl_method_items(fi, it):
                            if m.kind in ('fn', 'const fn') and not cfg_excluded(m.attrs):
                                mh = fi.clean[m.kw_pos:m.b]
                                _, _, sig = fn_decl(fi, mh[:mh.find('{')] if '{' in mh else mh, ctx, 1)
                                out.comments(leading_comments(fi.src, fi.clean, m.a, m.kw_pos), 1)
                                emit_fn(out, sig, 1)
                        out.emit('}')
                out.emit('')
                continue
            if target in emitted_split:
                continue
            r = lookup_type(fi, target)
            if r is None:
                out.emit(f'// PORT: impl for unknown type {target}')
                continue
            emitted_split.add(target)
            out.comments(cl)
            emit_split_impl(out, fi, inherent[target], target, r[0])
        elif k in ('fn', 'const fn'):
            hdr = head_clean[:head_clean.find('{')] if '{' in head_clean else head_clean.rstrip(';')
            ctx = Ctx(fi)
            _, _, sig = fn_decl(fi, hdr, ctx, 0)
            out.comments(cl)
            emit_fn(out, sig, 0)
            out.emit('')
        elif k in ('const', 'static'):
            h = ' '.join(head_clean.split()).rstrip(';')
            mm = re.match(r'(?:const|static)\s+(?:mut\s+)?([A-Za-z_0-9]+)\s*:\s*(.*?)\s*=\s*(.*)$', h, re.S)
            out.comments(cl)
            if not mm:
                out.emit('// PORT: ' + h[:200])
                out.emit('')
                continue
            cname = mm.group(1)
            if cname == '_':
                out.emit('// PORT: compile-time assertion dropped: ' + h[:160])
                out.emit('')
                continue
            ty = mm.group(2)
            if re.search(r'\bAtomic|Mutex|RwLock|OnceLock|OnceCell', ty) or (k == 'static' and 'mut' in h.split()[1:2]):
                out.emit(f'// PORT: mutable static `{cname}: {ty}` — BAML has no globals; see PORTING_GUIDE.md §11.')
                out.emit('')
                continue
            bty = translate(ty, Ctx(fi))
            raw = fi.src[it.kw_pos:it.b]
            eq = fi.clean[it.kw_pos:it.b].find('=')
            src_expr = raw[eq + 1:].strip().rstrip(';').strip() if eq >= 0 else ''
            cl_expr = fi.clean[it.kw_pos:it.b][eq + 1:].strip().rstrip(';').strip() if eq >= 0 else ''
            val = tr_const_expr(src_expr, bty, cl_expr) if len(src_expr) == len(cl_expr) else tr_const_expr(src_expr, bty)
            emit_fn(out, f'function {cname}() -> {bty}', 0, body=val or STUB)
            out.emit('')
        elif k == 'type':
            h = ' '.join(head_clean.split()).rstrip(';')
            mm = re.match(r'type\s+([A-Za-z_0-9]+)\s*(<[^=]*>)?\s*=\s*(.*)$', h)
            out.comments(cl)
            if mm and not generic_arity.get((fi.module, mm.group(1))):
                out.emit(f'type {mm.group(1)} = {translate(mm.group(3), Ctx(fi))}')
            else:
                out.emit('// PORT: generic type alias expanded at use sites: ' + h)
            out.emit('')
        elif k == 'trait':
            name = re.match(r'trait\s+([A-Za-z_][A-Za-z0-9_]*)', head_clean).group(1)
            out.comments(cl)
            out.emit(f'interface {name} {{')
            lo = it.kw_pos + head_clean.find('{') + 1
            hi = it.kw_pos + head_clean.rfind('}')
            ctx = Ctx(fi, self_type=name)
            for m in parse_items(fi.src, fi.clean, lo, hi):
                if m.kind in ('fn', 'const fn'):
                    mh = fi.clean[m.kw_pos:m.b]
                    has_body = '{' in mh
                    hdr = mh[:mh.find('{')] if has_body else mh.rstrip(';')
                    thr = ('unknown' if returns_result(hdr) else 'never') if has_body else 'unknown'
                    _, _, sig = fn_decl(fi, hdr, ctx, 1, in_interface=thr)
                    out.comments(leading_comments(fi.src, fi.clean, m.a, m.kw_pos), 1)
                    if has_body:
                        emit_fn(out, sig, 1, body=STUB_THROWS if thr == 'unknown' else STUB)
                    else:
                        out.emit(sig, 1)
                    out.emit('')
            out.emit('}')
            out.emit('')
        elif k == 'mod':
            h = ' '.join(head_clean.split())
            out.comments(cl)
            mm = re.match(r'mod\s+([A-Za-z_0-9]+)', h)
            if mm:
                out.emit(f'// mod {mm.group(1)} → namespace `{fi.module if fi.module != "root" else "root"}.{mm.group(1)}`'.replace('root.root', 'root'))
            out.emit('')
        elif k == 'use':
            continue
        elif k == 'macro':
            out.comments(cl)
            out.emit('// PORT: macro item: ' + ' '.join(it.text.split())[:160])
            out.emit('')
        else:
            out.comments(cl)
            out.emit(f'// PORT: unhandled item kind {k}')
            out.emit('')
    text = '\n'.join(out.lines)
    text = re.sub(r'\n{3,}', '\n\n', text).rstrip() + '\n'
    return text


def main():
    collect()
    written = []
    for rel, fi in sorted(files.items()):
        path = os.path.join(PROJECT, baml_file_of(rel))
        if os.path.exists(path) and not FORCE:
            print('skip (exists):', path)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        text = emit_file(fi)
        with open(path, 'w') as f:
            f.write(text)
        written.append(path)
    print(f'wrote {len(written)} files')


main()
