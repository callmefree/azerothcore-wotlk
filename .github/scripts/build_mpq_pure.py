#!/usr/bin/env python3
"""
Pure Python MPQ v1.0 builder — no external dependencies.

Creates WoW 3.3.5a compatible MPQ archives for client patches.

Usage:
  build_mpq_pure.py <source_dir> <output_mpq>
  build_mpq_pure.py --config patches.json --out-dir dist/
"""

import argparse, json, os, struct, hashlib, sys

MPQ_MAGIC = b'\x4d\x50\x51\x1a\x1a\x00\x00\x00'  # MPQ\x1a\x1a\x00\x00
HASH_TABLE_KEY = 0xC3AF3770
BLOCK_TABLE_KEY = 0xEC83B3A3
SECTOR_SIZE = 0x1000  # 4KB sectors

# File flags
FLAG_IMPLODE   = 0x00000100
FLAG_COMPRESS  = 0x00000200
FLAG_ENCRYPT   = 0x00010000
FLAG_FIX_KEY   = 0x00020000
FLAG_SINGLE    = 0x01000000
FLAG_EXISTS    = 0x80000000

# Stock hash seed table for MPQ encryption
def _make_crypt_table():
    table = [0] * 1280
    seed = 0x00100001
    for i in range(256):
        for j in range(5):
            seed = (seed * 125 + 3) & 0xFFFFFFFF
            table[i + j * 256] = seed
    return table

CRYPT_TABLE = _make_crypt_table()

def hash_filename(name, hash_type):
    """Hash a filename using MPQ hash function."""
    name = name.upper().replace('/', '\\')
    seed1 = 0x7FED7FED
    seed2 = 0xEEEEEEEE
    for c in name:
        ch = ord(c)
        seed1 = (CRYPT_TABLE[hash_type * 256 + ch] ^ (seed1 + seed2)) & 0xFFFFFFFF
        seed2 = (ch + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1, seed2

def decrypt_block(data, key):
    """Decrypt/encrypt an MPQ block (XOR with crypt table stream)."""
    result = bytearray()
    seed = key
    for i in range(0, len(data), 4):
        seed = (seed * 0x6A1C7B7 + 0x2D77B9) & 0xFFFFFFFF
        chunk = struct.unpack_from('<I', data, i)[0]
        struct.pack_into('<I', bytearray(4), 0, chunk ^ seed)
        result.extend(struct.pack('<I', chunk ^ seed))
    return bytes(result)

def encrypt_block(data, key):
    """Encrypt block (same as decrypt for XOR stream)."""
    return decrypt_block(data, key)

def _hash_table_key(name):
    return hash_filename("(hash table)", 0)[0] ^ HASH_TABLE_KEY

def _block_table_key(block_count):
    return hash_filename("(block table)", 0)[0] ^ BLOCK_TABLE_KEY

class MPQBuilder:
    """Build an MPQ v1.0 archive."""

    def __init__(self):
        self.files = []  # [(archive_name, data_bytes)]
        self.file_index = {}  # archive_name -> index

    def add_file(self, archive_path, data):
        """Add a file with its virtual path inside the MPQ."""
        path = archive_path.replace('/', '\\').upper()
        if path in self.file_index:
            self.files[self.file_index[path]] = (path, data)
        else:
            self.file_index[path] = len(self.files)
            self.files.append((path, data))

    def add_directory(self, vfs_root, source_dir):
        """Add all files from source_dir, mapping to vfs_root inside MPQ."""
        for root, dirs, files in os.walk(source_dir):
            for fname in files:
                full = os.path.join(root, fname)
                rel = os.path.relpath(full, source_dir)
                vfs_path = f"{vfs_root}/{rel}".replace('\\', '/')
                with open(full, 'rb') as f:
                    self.add_file(vfs_path, f.read())

    def save(self, output_path):
        """Write the MPQ file."""
        if not self.files:
            raise ValueError("No files to add")

        block_count = len(self.files)
        hash_entry_count = self._next_pow2(block_count * 4)

        # Build file data blocks
        file_data = b''
        # Will fill in offsets after we know sizes
        blocks = []
        for i, (name, data) in enumerate(self.files):
            # For simplicity, store without compression
            flags = FLAG_EXISTS | FLAG_SINGLE
            offset = len(file_data)
            file_data += data
            blocks.append((offset, len(data), len(data), flags))

        # Build hash table
        hash_table = [b'\xff' * 16] * hash_entry_count
        for i, (name, _) in enumerate(self.files):
            h1, h2 = hash_filename(name, 0)
            idx = h1 & (hash_entry_count - 1)
            # Find empty slot
            while True:
                entry_offset = idx * 16
                if hash_table[idx] == b'\xff' * 16:
                    hash_entry = struct.pack('<IIHBBi', h1, h2, 0, 0, 0, i)
                    hash_table[idx] = hash_entry
                    break
                idx = (idx + 1) & (hash_entry_count - 1)

        # Fix up: hash table and block table go AFTER file data
        data_offset = 0  # files start at the beginning (after header)
        # Actually in MPQ v1, data starts after header (32 bytes)
        # We'll place hash and block tables after all file data

        header_size = 32
        hash_table_offset = header_size + len(file_data)
        block_table_offset = hash_table_offset + hash_entry_count * 16

        raw_hash = b''.join(hash_table)
        raw_block = b''.join(struct.pack('<IIII', *b) for b in blocks)

        # Encrypt hash and block tables
        enc_hash = encrypt_block(raw_hash, _hash_table_key(''))
        enc_block = encrypt_block(raw_block, _block_table_key(block_count))

        # Write file
        with open(output_path, 'wb') as f:
            # 1. Header
            header = struct.pack(
                '<IIIHHIIII',
                0x1A51504D,  # MPQ magic
                header_size,  # header size
                0,  # archive size (filled later)
                0,  # format version (v1)
                12,  # sector size shift (4KB)
                hash_table_offset,  # hash table offset
                block_table_offset,  # block table offset
                hash_entry_count,  # hash table entries
                block_count,  # block table entries
            )
            f.write(header)

            # 2. File data
            f.write(file_data)

            # 3. Hash table
            f.write(enc_hash)

            # 4. Block table
            f.write(enc_block)

            # Patch archive size in header
            total_size = f.tell()
            f.seek(8)
            f.write(struct.pack('<I', total_size))
            f.seek(0, os.SEEK_END)

        file_count = len(self.files)
        size_mb = os.path.getsize(output_path) / 1024 / 1024
        print(f"    Wrote {output_path}: {file_count} files, {size_mb:.1f} MB")
        return output_path

    @staticmethod
    def _next_pow2(n):
        p = 1
        while p < n:
            p <<= 1
        return p


def auto_build(base_dir, out_dir):
    """Auto-build patches from mod source directories."""
    os.makedirs(out_dir, exist_ok=True)

    # ── Delves patch-4.mpq ──
    delves_mpq = os.path.join(base_dir, 'delves-src', 'MPQ')
    if os.path.isdir(delves_mpq):
        builder = MPQBuilder()
        mappings = [
            ('Interface/Glues/LoadingScreens', 'Interface/Glues/LoadingScreens'),
            ('Sound/Delves', 'Sound/Delves'),
            ('textures/minimap', 'textures/minimap'),
            ('world/maps', 'world/maps'),
        ]
        for vfs, sub in mappings:
            src = os.path.join(delves_mpq, sub.replace('/', os.sep))
            if os.path.isdir(src):
                builder.add_directory(vfs, src)
        # Star wars assets
        sw = os.path.join(delves_mpq, 'starwars')
        if os.path.isdir(sw):
            builder.add_directory('starwars', sw)

        if builder.files:
            print(f"  [Delves] Building patch-4.mpq ({len(builder.files)} files)...")
            builder.save(os.path.join(out_dir, 'patch-4.mpq'))
        else:
            print("  [Delves] No files found, skipping")

    # ── ClassScrolls patch-5.mpq ──
    cs_icons = os.path.join(base_dir, 'classscrolls-src', 'Interface', 'Icons')
    if os.path.isdir(cs_icons):
        builder = MPQBuilder()
        builder.add_directory('Interface/Icons', cs_icons)
        if builder.files:
            print(f"  [ClassScrolls] Building patch-5.mpq ({len(builder.files)} files)...")
            builder.save(os.path.join(out_dir, 'patch-5.mpq'))
        else:
            print("  [ClassScrolls] No files found, skipping")


def main():
    parser = argparse.ArgumentParser(description='Pure Python MPQ builder')
    parser.add_argument('--auto', action='store_true', help='Auto-build from default source dirs')
    parser.add_argument('--out-dir', default='.', help='Output directory')
    parser.add_argument('--config', help='JSON config')
    parser.add_argument('source', nargs='?', help='Source directory')
    parser.add_argument('output', nargs='?', help='Output MPQ path')
    args = parser.parse_args()

    if args.auto:
        base = os.environ.get('ACOREMODS_ROOT', os.getcwd())
        auto_build(base, args.out_dir)
        return

    if args.config:
        with open(args.config) as f:
            config = json.load(f)
        for entry in config.get('patches', []):
            name = entry.get('name', '?')
            print(f"  [{name}] Building {entry['output']}...")
            builder = MPQBuilder()
            for mapping in entry.get('mappings', []):
                builder.add_directory(mapping['vfs'], mapping['source_dir'])
            builder.save(os.path.join(args.out_dir, entry['output']))
        return

    if args.source and args.output:
        builder = MPQBuilder()
        builder.add_directory('', args.source)
        builder.save(args.output)
        return

    parser.print_help()


if __name__ == '__main__':
    main()
