"""Sync reviewed Verse sources to a discovered editor mount, then compile."""

import argparse
import asyncio
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from mcp import Client
from uefn_mcp import json_value, local_endpoint


async def run(args):
    source = Path(args.source).resolve()
    if not source.is_dir() or not args.mount.startswith('/'):
        raise ValueError('An existing source directory and discovered absolute Verse mount are required')
    async with Client(local_endpoint(args.url), mode='legacy') as client:
        snapshot = []
        for path in sorted(source.glob('*.verse')):
            content = path.read_text(encoding='utf-8-sig')
            result = json_value(await client.call_tool('call_tool', {
                'toolset_name': 'VerseToolset.VerseToolset', 'tool_name': 'WriteFile',
                'arguments': {'path': args.mount.rstrip('/') + '/' + path.name,
                              'content': content, 'bCreateIfMissing': True}}))
            if result.get('isError'):
                raise RuntimeError('Editor rejected source: ' + path.name)
            print('synced', path.name, flush=True)
            snapshot.append({'file': path.name, 'sha256_utf8_lf': hashlib.sha256(content.encode('utf-8')).hexdigest()})
        result = json_value(await client.call_tool('call_tool', {
            'toolset_name': 'VerseToolset.VerseToolset', 'tool_name': 'BuildAll', 'arguments': {}}))
        result['syncEvidence'] = {'mount': args.mount, 'sourceSnapshot': snapshot, 'buildObservedAtUtc': datetime.now(timezone.utc).isoformat(), 'scope': 'Files sent before this BuildAll result. Compilation is separate from runtime and publication.'}
        Path(args.result).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        for item in result.get('content', []):
            if item.get('type') == 'text':
                print(item['text'], flush=True)
                decoded = json.loads(item['text'])
                if isinstance(decoded, dict) and decoded.get('returnValue'):
                    raise RuntimeError('Build diagnostics require review')
        if result.get('isError'):
            raise RuntimeError('Editor reported a build error')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', required=True)
    parser.add_argument('--mount', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--result', required=True)
    args = parser.parse_args()
    try:
        asyncio.run(run(args))
    except Exception:
        print('Sync/build did not complete. Inspect the saved result and editor state before retrying.', file=sys.stderr)
        raise SystemExit(1)
