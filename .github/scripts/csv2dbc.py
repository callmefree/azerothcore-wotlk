#!/usr/bin/env python3
"""
CSV → DBC binary converter for WOTLK 3.3.5a (WDBC format).

Usage:
  # Convert CSV(s) to DBC (auto-detect types)
  csv2dbc.py output.dbc input.csv [input2.csv ...]

  # Merge existing binary DBC with CSV rows
  csv2dbc.py --merge base.dbc output.dbc extra.csv [--schema schemas.json]

  # Batch convert all CSVs in source dir to output dir
  csv2dbc.py --batch <src-dir> <out-dir> [--schema schemas.json]

Auto-detects int32/float/string columns from CSV data values.
For --merge, a schema is required to decode binary DBC string columns correctly.
"""

import csv, struct, sys, os, io, json, re, glob

WDBC_MAGIC = b'WDBC'


# ── Binary DBC I/O ────────────────────────────────────────────────

def read_dbc(filepath):
    """Read binary DBC → (records: list[list[int]], field_count, string_block: bytes).
    Every field is read as raw int32 (including string offsets).
    """
    with open(filepath, 'rb') as f:
        magic = f.read(4)
        if magic != WDBC_MAGIC:
            raise ValueError(f"Not a WDBC file: {filepath}")
        rec_count = struct.unpack('<I', f.read(4))[0]
        field_count = struct.unpack('<I', f.read(4))[0]
        rec_size = struct.unpack('<I', f.read(4))[0]
        str_block_size = struct.unpack('<I', f.read(4))[0]

        raw = f.read(rec_count * rec_size)
        string_block = f.read(str_block_size)

    records = []
    for i in range(rec_count):
        off = i * rec_size
        fields = list(struct.unpack(f'<{field_count}i', raw[off:off + rec_size]))
        records.append(fields)

    return records, field_count, string_block


def write_dbc(filepath, records, field_types=None):
    """Write records (list[list[any]]) as binary WDBC.
    field_types: list of 'int32' / 'float' / 'string'. If omitted, all int32.
    """
    if not records:
        field_count = field_types and len(field_types) or 0
        rec_size = field_count * 4
        rec_data = b''
        str_block = b'\x00'
        _do_write(filepath, 0, field_count, rec_size, rec_data, str_block)
        return

    field_count = len(records[0])
    if field_types is None:
        field_types = ['int32'] * field_count

    # Build string block
    str_block = b'\x00'
    str_map = {'': 0}

    rec_data = b''
    for rec in records:
        for i in range(field_count):
            val = rec[i] if i < len(rec) else 0
            ft = field_types[i] if i < len(field_types) else 'int32'

            if ft == 'string':
                if isinstance(val, int):
                    # Already an offset from binary DBC read — resolve to actual string
                    s = _resolve_str(str_block, val) if isinstance(val, int) else str(val)
                else:
                    s = str(val) if val else ''
                if s and s not in str_map:
                    str_map[s] = len(str_block)
                    str_block += s.encode('utf-8') + b'\x00'
                rec_data += struct.pack('<i', str_map.get(s, 0))
            elif ft == 'float':
                rec_data += struct.pack('<f', float(val))
            else:
                rec_data += struct.pack('<i', int(val))

    rec_size = field_count * 4
    rec_count = len(records)
    _do_write(filepath, rec_count, field_count, rec_size, rec_data, str_block)


def _do_write(filepath, rec_count, field_count, rec_size, rec_data, str_block):
    with open(filepath, 'wb') as f:
        f.write(WDBC_MAGIC)
        f.write(struct.pack('<I', rec_count))
        f.write(struct.pack('<I', field_count))
        f.write(struct.pack('<I', rec_size))
        f.write(struct.pack('<I', len(str_block)))
        f.write(rec_data)
        f.write(str_block)


def _resolve_str(string_block, offset):
    """Extract null-terminated string from DBC string block at given offset."""
    if offset <= 0 or offset >= len(string_block):
        return ''
    end = string_block.find(b'\x00', offset)
    if end == -1:
        end = len(string_block)
    return string_block[offset:end].decode('utf-8', errors='replace')


# ── CSV parsing ───────────────────────────────────────────────────

def read_csv(filepath):
    """Read CSV → (header: list[str], rows: list[list[str]])."""
    with open(filepath, 'r', encoding='utf-8-sig') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = [list(r) for r in reader]
    # Strip whitespace/quotes from values
    rows = [[c.strip().strip('"') for c in r] for r in rows]
    return header, rows


def detect_field_types(rows, field_count, header=None):
    """Auto-detect int32/float/string for each column from CSV data."""
    types = ['int32'] * field_count
    for row in rows:
        for i in range(min(len(row), field_count)):
            val = row[i].strip()
            if not val:
                continue
            if types[i] == 'int32':
                if not re.match(r'^-?\d+$', val):
                    if re.match(r'^-?\d+\.?\d*(?:[eE][+-]?\d+)?$', val):
                        types[i] = 'float'
                    else:
                        types[i] = 'string'
            elif types[i] == 'float':
                if not re.match(r'^-?\d*\.?\d*(?:[eE][+-]?\d+)?$', val):
                    types[i] = 'string'
    return types


def apply_schema_overrides(dbc_name, types, header, schemas):
    """Apply schema overrides: force known string columns."""
    if not schemas or dbc_name not in schemas:
        return types
    schema = schemas[dbc_name]
    str_cols = schema.get('string_cols', [])
    float_cols = schema.get('float_cols', [])
    for idx in str_cols:
        if idx < len(types):
            types[idx] = 'string'
    for idx in float_cols:
        if idx < len(types):
            types[idx] = 'float'
    return types


# ── Decode binary DBC records with schema ─────────────────────────

def decode_dbc_records(dbc_path, dbc_name, schemas):
    """Read binary DBC, decode fields using schema → list[list[mixed]]."""
    raw_records, field_count, string_block = read_dbc(dbc_path)

    # Resolve schema
    field_types = ['int32'] * field_count
    if schemas and dbc_name in schemas:
        schema = schemas[dbc_name]
        for idx in schema.get('string_cols', []):
            if idx < field_count:
                field_types[idx] = 'string'
        for idx in schema.get('float_cols', []):
            if idx < field_count:
                field_types[idx] = 'float'

    decoded = []
    for rec in raw_records:
        drec = []
        for i, val in enumerate(rec):
            if field_types[i] == 'string':
                s = _resolve_str(string_block, val)
                drec.append(s)
            elif field_types[i] == 'float':
                import struct as _s
                drec.append(_s.unpack('<f', _s.pack('<i', val))[0])
            else:
                drec.append(val)
        decoded.append(drec)
    return decoded, field_types


# ── DBC name from filename ────────────────────────────────────────

def dbc_name_from_path(path):
    """Strip .csv/.dbc → e.g., 'Spell.dbc', 'Map.dbc'."""
    base = os.path.basename(path)
    name, ext = os.path.splitext(base)
    if ext.lower() in ('.csv', '.dbc'):
        return name + '.dbc'
    return name + '.dbc'


def stem_from_csv(path):
    """Get DBC stem from CSV path."""
    base = os.path.basename(path)
    name, ext = os.path.splitext(base)
    return name


# ── Main conversion ───────────────────────────────────────────────

def convert_csvs_to_dbc(csv_paths, dbc_name, schemas=None):
    """Convert one or more CSV files (same DBC type) into DBC records."""
    all_rows = []
    field_count = None
    types = None

    for csv_path in csv_paths:
        header, rows = read_csv(csv_path)
        ncols = len(header)
        if field_count is None:
            field_count = ncols
        elif ncols != field_count:
            print(f"  [WARN] {csv_path}: {ncols} cols, expected {field_count} — padding")
            # Pad shorter rows
            for r in rows:
                while len(r) < field_count:
                    r.append('0')

        all_rows.extend(rows)

    if not all_rows:
        print(f"  [WARN] No data rows in {csv_paths}")
        return [], ['int32'] * (field_count or 0)

    # Auto-detect types from all data
    types = detect_field_types(all_rows, field_count, header)

    # Apply schema overrides
    if schemas:
        types = apply_schema_overrides(dbc_name, types, header, schemas)

    return all_rows, types


def do_batch(src_dir, out_dir, schemas=None, merge_dir=None):
    """Batch convert all CSV files in src_dir → DBC files in out_dir.
    If merge_dir, check for existing .dbc files of the same name and merge.
    """
    os.makedirs(out_dir, exist_ok=True)

    csv_files = sorted(glob.glob(os.path.join(src_dir, '**', '*.csv'), recursive=True))
    if not csv_files:
        print("  No CSV files found.")
        return

    # Group by DBC type (stem)
    groups = {}
    for f in csv_files:
        stem = stem_from_csv(f)
        groups.setdefault(stem, []).append(f)

    for stem, paths in sorted(groups.items()):
        dbc_name = stem + '.dbc'
        out_path = os.path.join(out_dir, dbc_name)
        print(f"  {dbc_name} ← {len(paths)} CSV source(s)")

        # Check for existing binary DBC to merge
        base_records = None
        base_types = None
        if merge_dir:
            merge_candidate = os.path.join(merge_dir, dbc_name)
            if os.path.isfile(merge_candidate):
                print(f"    merging base: {merge_candidate}")
                try:
                    base_records, base_types = decode_dbc_records(merge_candidate, dbc_name, schemas)
                    print(f"    base records: {len(base_records)}")
                except Exception as e:
                    print(f"    [WARN] failed to read base DBC: {e}")

        # Convert CSV rows
        csv_rows, csv_types = convert_csvs_to_dbc(paths, dbc_name, schemas)

        # Merge
        combined = []
        if base_records:
            combined.extend(base_records)
        for row in csv_rows:
            combined.append(row)

        # Determine field types (use CSV types if available, else base)
        final_types = csv_types if csv_rows else base_types

        if combined:
            write_dbc(out_path, combined, final_types)
            print(f"    → {out_path} ({len(combined)} records, {len(final_types)} fields)")
        else:
            print(f"    [SKIP] no records")


def main():
    import argparse
    parser = argparse.ArgumentParser(description='CSV → DBC converter for WOTLK 3.3.5a')
    parser.add_argument('--schema', help='JSON schema file for string column indices')
    parser.add_argument('--merge', metavar='BASE_DBC', help='Merge with existing binary DBC')
    parser.add_argument('--batch', action='store_true', help='Batch mode: <src_dir> <out_dir>')
    parser.add_argument('--merge-dir', help='Directory with binary DBCs to merge for batch mode')
    parser.add_argument('input', nargs='+', help='Input CSV files, or src_dir/out_dir for batch mode')
    args = parser.parse_args()

    # Load schema
    schemas = None
    if args.schema:
        with open(args.schema, 'r', encoding='utf-8') as f:
            schemas = json.load(f)

    if args.batch:
        if len(args.input) < 2:
            print("Batch mode needs: <src_dir> <out_dir>")
            sys.exit(1)
        src_dir = args.input[0]
        out_dir = args.input[1]
        do_batch(src_dir, out_dir, schemas, args.merge_dir)
        return

    # Single conversion
    csv_paths = [p for p in args.input if not p.startswith('--')]
    if not csv_paths:
        print("No input CSV files.")
        sys.exit(1)

    # Last non-flag arg is output
    output = csv_paths[-1]
    csv_inputs = csv_paths[:-1]
    if output.endswith('.csv') or output.startswith('--'):
        print("Last argument must be the output .dbc path")
        sys.exit(1)

    dbc_name = dbc_name_from_path(output)

    # Handle merge
    base_records = None
    base_types = None
    if args.merge:
        print(f"Merging base DBC: {args.merge}")
        base_records, base_types = decode_dbc_records(args.merge, dbc_name, schemas)
        print(f"  Base records: {len(base_records)}, fields: {len(base_types)}")

    csv_rows, csv_types = convert_csvs_to_dbc(csv_inputs, dbc_name, schemas)
    print(f"  CSV rows: {len(csv_rows)}, fields: {len(csv_types)}")

    combined = []
    if base_records:
        combined.extend(base_records)
    for row in csv_rows:
        combined.append(row)

    final_types = csv_types if csv_rows else base_types
    write_dbc(output, combined, final_types)
    print(f"Wrote {os.path.basename(output)}: {len(combined)} records, {len(final_types)} fields")


if __name__ == '__main__':
    main()
