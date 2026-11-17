#!/usr/bin/env python3
"""Lint Dart dependency direction and cycles during the MVVM migration. GPL-3.0."""
import argparse
import json
from pathlib import Path, PurePosixPath
import posixpath
import sys

ROOT = Path(__file__).resolve().parents[1]
PLATFORM_PACKAGES = {'file_selector', 'printing', 'share_plus', 'url_launcher'}


def tokens(source):
    """Read identifiers, strings and punctuation, ignoring nested Dart comments."""
    at = 0
    while at < len(source):
        if source.startswith('//', at):
            end = source.find('\n', at)
            at = len(source) if end < 0 else end
        elif source.startswith('/*', at):
            depth, at = 1, at + 2
            while at < len(source) and depth:
                if source.startswith('/*', at): depth, at = depth + 1, at + 2
                elif source.startswith('*/', at): depth, at = depth - 1, at + 2
                else: at += 1
            if depth: raise ValueError('unterminated comment')
        elif source[at].isspace():
            at += 1
        elif source[at] in "\"'" or (source[at] == 'r' and at + 1 < len(source) and source[at + 1] in "\"'"):
            raw = source[at] == 'r'
            if raw: at += 1
            quote = source[at]
            delimiter = quote * (3 if source.startswith(quote * 3, at) else 1)
            at += len(delimiter)
            value = ''
            while at < len(source) and not source.startswith(delimiter, at):
                if not raw and source[at] == '\\':
                    at += 1
                    if at == len(source): break
                value += source[at]
                at += 1
            if at == len(source): raise ValueError('unterminated string')
            at += len(delimiter)
            yield 'string', value
        elif source[at].isalpha() or source[at] in '_$':
            end = at + 1
            while end < len(source) and (source[end].isalnum() or source[end] in '_$'): end += 1
            yield 'id', source[at:end]
            at = end
        else:
            yield 'punctuation', source[at]
            at += 1


def header(source):
    stream = iter(tokens(source))
    result, kinds = [], []
    token = next(stream, None)
    while token is not None:
        while token == ('punctuation', '@'):
            token = next(stream, None)
            if token is None or token[0] != 'id': raise ValueError('invalid directive metadata')
            token = next(stream, None)
            while token == ('punctuation', '.'):
                token = next(stream, None)
                if token is None or token[0] != 'id': raise ValueError('invalid directive metadata')
                token = next(stream, None)
            for opening, closing in [('<', '>'), ('(', ')')]:
                if token != ('punctuation', opening): continue
                depth = 1
                while depth:
                    token = next(stream, None)
                    if token is None: raise ValueError('unterminated directive metadata')
                    if token == ('punctuation', opening): depth += 1
                    if token == ('punctuation', closing): depth -= 1
                token = next(stream, None)
        if token is None: break
        kind, value = token
        if kind != 'id' or value not in {'import', 'export', 'part', 'library'}:
            return result, False
        declaration = []
        for token in stream:
            if token == ('punctuation', ';'): break
            declaration.append(token)
        token = next(stream, None)
        if value == 'library': continue
        kinds.append(value)
        if declaration and declaration[0] == ('id', 'of'): continue
        depth = 0
        for k, v in declaration:
            if (k, v) == ('punctuation', '('): depth += 1
            if (k, v) == ('punctuation', ')'): depth -= 1
            if k == 'string' and depth == 0: result.append((value, v))
    return result, bool(kinds) and all(k == 'export' for k in kinds)


def directives(source):
    return header(source)[0]


def resolve(source, uri):
    if uri.startswith('package:erp_client/'):
        return 'lib/' + uri[len('package:erp_client/'):]
    if ':' in uri: return None
    return posixpath.normpath(posixpath.join(posixpath.dirname(source), uri))


def role(path, legacy):
    parts = PurePosixPath(path).parts
    if path == 'lib/main.dart' or parts[:2] == ('lib', 'app'): return 'app', None
    if len(parts) >= 4 and parts[:2] == ('lib', 'core') and parts[2] in {'models', 'services', 'ui'}:
        return parts[2], None
    if len(parts) >= 5 and parts[:2] == ('lib', 'features'):
        feature, layer = parts[2:4]
        if layer == 'presentation':
            return ('view_model' if path.endswith('_view_model.dart') else 'view'), feature
        if layer in {'models', 'domain'}: return layer, feature
        if layer == 'data':
            return ('services' if path.endswith('_service.dart') else 'data'), feature
    if path in legacy:
        # The concrete authenticated adapter remains a service during rollout.
        if path == 'lib/erp_api.dart': return 'services', None
        return 'legacy', None
    return 'unknown', None


def allowed(source_role, target_role, target):
    layer, feature = source_role
    other, other_feature = target_role
    if layer == 'app': return True
    if other in {'unknown', 'legacy', 'app'}: return False
    if layer == 'services': return other == 'models' or other == 'services'
    if layer == 'ui': return other in {'ui', 'models'} and other_feature is None
    if layer == 'models': return other == 'models' and other_feature in {None, feature}
    if layer == 'domain': return other in {'models', 'domain', 'data'} and other_feature in {None, feature}
    if layer == 'data': return other == 'services' or (other in {'models', 'data'} and other_feature in {None, feature})
    if layer == 'view_model':
        return other in {'models', 'domain', 'data'} and other_feature in {None, feature} and not (other == 'data' and PurePosixPath(target).name.startswith('erp_'))
    if layer == 'view': return other in {'models', 'ui', 'view', 'view_model'} and other_feature in {None, feature}
    return False


def external_allowed(source_role, uri, source=None):
    layer = source_role[0]
    if layer in {'legacy', 'app'}: return True
    if layer == 'services':
        # Logo decoding uses ImageDescriptor, never Flutter widgets or layout.
        if uri == 'dart:ui':
            return source == 'lib/features/invoices/data/invoice_logo_service.dart'
        if uri.startswith('package:flutter/'):
            return uri in {'package:flutter/foundation.dart', 'package:flutter/services.dart'}
        return True
    if uri in {'dart:io', 'dart:ffi', 'dart:ui'}: return layer in {'ui', 'view'} and uri == 'dart:ui'
    if uri.startswith('package:flutter/'):
        return layer in {'view', 'ui'} or (layer == 'view_model' and uri == 'package:flutter/foundation.dart')
    if uri.startswith('package:') and uri.split('/')[0][8:] in PLATFORM_PACKAGES: return False
    return True


def cycles(graph):
    index, indices, low, stack, active, found = 0, {}, {}, [], set(), []
    def visit(node):
        nonlocal index
        indices[node] = low[node] = index
        index += 1
        stack.append(node)
        active.add(node)
        for target in graph[node]:
            if target not in indices:
                visit(target)
                low[node] = min(low[node], low[target])
            elif target in active: low[node] = min(low[node], indices[target])
        if low[node] == indices[node]:
            group = []
            while True:
                target = stack.pop()
                active.remove(target)
                group.append(target)
                if target == node: break
            if len(group) > 1 or node in graph[node]: found.append(frozenset(group))
    for node in graph:
        if node not in indices: visit(node)
    return found


def lint(root, baseline):
    sources = {'lib/' + p.relative_to(root / 'lib').as_posix(): p.read_text()
               for p in (root / 'lib').rglob('*.dart')}
    legacy = {f['path']: f for f in baseline['files'] if f['path'].startswith('lib/')}
    headers = {p: header(s) for p, s in sources.items()}
    imports = {p: h[0] for p, h in headers.items()}
    graph = {p: set() for p in sources}
    errors = []
    facades = {p for p, h in headers.items() if p in legacy and h[1]}
    def destinations(target, seen=None):
        seen = set() if seen is None else seen
        if target not in facades or target in seen: return {target}
        seen.add(target)
        return {d for _, uri in imports[target] for n in [resolve(target, uri)]
                for d in (destinations(n, seen.copy()) if n else {uri})}
    for source in sources:
        source_role = role(source, legacy)
        if source_role[0] == 'unknown': errors.append(f'{source}: unknown architectural layer; use app/, core/ or features/<name>/<layer>/')
        original = set(d for text in legacy.get(source, {}).get('directives', []) for d in directives(text))
        for kind, uri in imports[source]:
            target = resolve(source, uri)
            if target is None:
                if source in legacy and (kind, uri) in original: continue
                if not external_allowed(source_role, uri, source): errors.append(f'{source}: forbidden dependency on {uri}')
                continue
            if target not in sources:
                errors.append(f'{source}: missing local dependency {uri}')
                continue
            graph[source].add(target)
            if source in legacy and ((kind, uri) in original or source in facades): continue
            for destination in destinations(target):
                valid = (allowed(source_role, role(destination, legacy), destination)
                         if destination in sources else external_allowed(source_role, destination, source))
                if not valid:
                    label = 'new legacy dependency' if source in legacy else 'forbidden dependency'
                    errors.append(f'{source}: {label} on {destination} via {uri}')
    existing = {frozenset(c) for c in baseline['graph']['cycles']}
    current = cycles(graph)
    for group in current:
        if group not in existing: errors.append('dependency cycle: ' + ' -> '.join(sorted(group)))
    return errors, len(sources), sum(c in existing for c in current)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT / 'apps/erp_client')
    parser.add_argument('--baseline', type=Path, default=ROOT / 'docs/architecture/2026-11-16-baseline-inventory.json')
    args = parser.parse_args()
    try:
        errors, count, residual = lint(args.root, json.loads(args.baseline.read_text()))
    except (OSError, ValueError, KeyError) as error:
        print('Architecture lint could not run: ' + str(error), file=sys.stderr)
        return 2
    if errors:
        print('\n'.join(errors))
        return 1
    print(f'Architecture lint passed: {count} source files; {residual} existing import cycles remain under migration.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
