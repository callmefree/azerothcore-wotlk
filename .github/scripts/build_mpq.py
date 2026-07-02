#!/usr/bin/env python3
"""
MPQ patch builder for WoW WOTLK 3.3.5a client assets.

Builds patch MPQ files from a source directory of client assets.
Uses smpq (MIT-licensed StormLib CLI tool) for actual MPQ packing.

Usage:
  # Build a single patch MPQ from a directory
  build_mpq.py <source_dir> <output_mpq>

  # Build multiple patches from a config JSON
  build_mpq.py --config patches.json --out-dir dist/

  # Build Delves and ClassScrolls patches in one command
  build_mpq.py --auto

The --auto mode looks for:
  - E:/delves-src/MPQ/  → patch-4.mpq (Delves: loading screens, sounds, starwars, maps, minimaps)
  - E:/classscrolls-src/Interface/  → patch-5.mpq (ClassScrolls: 20 BLP icons)
"""

import argparse, json, os, shutil, subprocess, sys, urllib.request, zipfile, glob, tempfile

SMPQ_URL = 'https://github.com/arithon/smpq/releases/download/v1.6/smpq-win64.zip'
SMPQ_EXE = 'smpq.exe'
SMPQ_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.smpq_cache')


# ── smpq management ────────────────────────────────────────────────

def _ensure_smpq():
    """Ensure smpq.exe is available, download if needed."""
    # Check PATH first
    which = shutil.which(SMPQ_EXE)
    if which:
        return which

    # Check local cache
    local = os.path.join(SMPQ_DIR, SMPQ_EXE)
    if os.path.isfile(local):
        return local

    # Download
    print(f"  [MPQ] Downloading {SMPQ_EXE} from {SMPQ_URL}...")
    os.makedirs(SMPQ_DIR, exist_ok=True)
    zip_path = os.path.join(SMPQ_DIR, 'smpq.zip')
    try:
        urllib.request.urlretrieve(SMPQ_URL, zip_path)
        with zipfile.ZipFile(zip_path, 'r') as zf:
            zf.extractall(SMPQ_DIR)
        os.remove(zip_path)
        if os.path.isfile(local):
            os.chmod(local, 0o755)
            return local
    except Exception as e:
        print(f"  [WARN] Failed to download smpq: {e}", file=sys.stderr)

    return None


def build_mpq(sources, output_mpq, patch_prefix='patch'):
    """Build an MPQ file from a source directory or file list.

    Args:
        sources: either a dict {vfs_prefix: dir_path} or a list of (archive_path, file_path) tuples
        output_mpq: path to output .mpq file
        patch_prefix: prefix for patch numbering
    """
    smpq = _ensure_smpq()
    if not smpq:
        # Fallback: just copy files to a structured directory
        print(f"  [MPQ] smpq not available, creating directory structure at {output_mpq}.dir/")
        _fallback_copy(sources, output_mpq)
        return

    os.makedirs(os.path.dirname(output_mpq) or '.', exist_ok=True)

    # Build file list for smpq
    filelist = []
    temp_list = None

    if isinstance(sources, dict):
        # sources = {vfs_prefix: dir_path}
        for vfs_prefix, src_dir in sources.items():
            if not os.path.isdir(src_dir):
                print(f"  [WARN] Source dir not found: {src_dir}")
                continue
            for root, dirs, files in os.walk(src_dir):
                for fname in files:
                    full = os.path.join(root, fname)
                    rel = os.path.relpath(full, src_dir)
                    # Map to VFS path: prefix/relative/path
                    vfs_path = f"{vfs_prefix}/{rel}".replace('\\', '/')
                    filelist.append((full, vfs_path))
    elif isinstance(sources, list):
        filelist = sources

    if not filelist:
        print(f"  [WARN] No files to pack for {output_mpq}")
        return

    # Write filelist to a temp file for smpq
    fd, temp_list = tempfile.mkstemp(suffix='.txt', text=True)
    try:
        with os.fdopen(fd, 'w') as f:
            for full, vfs_path in filelist:
                vfs_path = vfs_path.lstrip('/')
                f.write(f'"{full}" "{vfs_path}"\n')

        # Build smpq command
        # smpq -c create MPQ, -a add files from list
        if not os.path.isfile(output_mpq):
            cmd = [smpq, '-c', output_mpq]
            print(f"    Running: {' '.join(cmd)}")
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if r.returncode != 0:
                print(f"    [WARN] smpq create failed: {r.stderr.strip()}")
                _fallback_copy(sources, output_mpq)
                return
            print(f"    Created: {output_mpq}")

        cmd = [smpq, '-a', output_mpq, f'@{temp_list}']
        print(f"    Running: {' '.join(cmd)}")
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            print(f"    [WARN] smpq add failed: {r.stderr.strip()}")
            _fallback_copy(sources, output_mpq)
            return

    finally:
        if temp_list and os.path.isfile(temp_list):
            os.unlink(temp_list)

    # Verify
    size = os.path.getsize(output_mpq)
    print(f"    {output_mpq}: {len(filelist)} files, {_fmt_size(size)}")


def _fallback_copy(sources, output_mpq):
    """Fallback: copy files to directory structure when smpq unavailable."""
    out_dir = output_mpq + '.dir'
    os.makedirs(out_dir, exist_ok=True)

    if isinstance(sources, dict):
        for vfs_prefix, src_dir in sources.items():
            if not os.path.isdir(src_dir):
                continue
            for root, dirs, files in os.walk(src_dir):
                for fname in files:
                    full = os.path.join(root, fname)
                    rel = os.path.relpath(full, src_dir)
                    dest = os.path.join(out_dir, vfs_prefix, rel)
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    shutil.copy2(full, dest)
    elif isinstance(sources, list):
        for full, vfs_path in sources:
            dest = os.path.join(out_dir, vfs_path.lstrip('/'))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copy2(full, dest)

    count = sum(len(files) for _, _, files in os.walk(out_dir))
    print(f"    Copied {count} files to {out_dir}")


def _fmt_size(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


# ── Automatic mode ──────────────────────────────────────────────────

def auto_build(base_dir, out_dir):
    """Auto-discover and build all patch MPQs from the new mod source dirs.

    base_dir: the acore-full checkout root (contains delves-src/, classscrolls-src/)
    out_dir: where to write the patch MPQs
    """
    patches = []

    # ── Delves ─────────────────────────────────────────────────────
    delves_mpq = os.path.join(base_dir, 'delves-src', 'MPQ')
    if os.path.isdir(delves_mpq):
        output = os.path.join(out_dir, 'patch-4.mpq')
        sources = {
            'Interface/Glues/LoadingScreens': os.path.join(delves_mpq, 'Interface', 'Glues', 'LoadingScreens'),
            'Sound/Delves': os.path.join(delves_mpq, 'Sound', 'Delves'),
            'textures/minimap': os.path.join(delves_mpq, 'textures', 'minimap'),
            'world/maps': os.path.join(delves_mpq, 'world', 'maps'),
        }

        # Star Wars assets (M2, WMO, BLP) — map to root of MPQ
        starwars_dir = os.path.join(delves_mpq, 'starwars')
        if os.path.isdir(starwars_dir):
            sources['starwars'] = starwars_dir

        patches.append(('Delves', sources, output))

    # ── ClassScrolls ───────────────────────────────────────────────
    cs_icons = os.path.join(base_dir, 'classscrolls-src', 'Interface', 'Icons')
    if os.path.isdir(cs_icons):
        output = os.path.join(out_dir, 'patch-5.mpq')
        sources = {
            'Interface/Icons': cs_icons,
        }
        patches.append(('ClassScrolls', sources, output))

    # Build
    for name, sources, output in patches:
        print(f"\n  [{name}] Building {os.path.basename(output)}...")
        build_mpq(sources, output)

    return patches


# ── CLI ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='WoW MPQ patch builder')
    parser.add_argument('--auto', action='store_true',
                        help='Auto-build all patches from delves-src/ and classscrolls-src/')
    parser.add_argument('--out-dir', default='.',
                        help='Output directory for MPQ files (default: .)')
    parser.add_argument('--config', help='JSON config file with patch definitions')
    parser.add_argument('source', nargs='?', help='Source directory to pack')
    parser.add_argument('output', nargs='?', help='Output MPQ file path')
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)

    if args.auto:
        # Use environment variable or CWD as base
        base = os.environ.get('ACOREMODS_ROOT', os.getcwd())
        auto_build(base, args.out_dir)
        return

    if args.config:
        with open(args.config, 'r') as f:
            config = json.load(f)
        for entry in config.get('patches', []):
            print(f"\n  [{entry.get('name', '?')}] Building {entry.get('output', '?')}...")
            if 'source_dir' in entry:
                build_mpq(entry['source_mapping'], os.path.join(args.out_dir, entry['output']))
        return

    if args.source and args.output:
        # Single directory → single MPQ
        sources = {'': args.source}
        build_mpq(sources, args.output)
        return

    parser.print_help()


if __name__ == '__main__':
    main()
