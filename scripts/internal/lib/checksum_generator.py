#!/usr/bin/env python3
# * UNCLASSIFIED                 UNCLASSIFIED                 UNCLASSIFIED *
# ==============================================================================
# Author: Nima Shafie [DS] (N56332)
# Script Name : checksum_generator.py
# Target Platforms: RHEL/Rocky 8/9/10 (bash), Windows 10/11 (Git Bash / native Python)
# Compatibility : Python 3.6+ (standard library only, zero pip dependencies)
# ==============================================================================
"""Cross-platform file integrity manifest generator.

Recursively walks a directory tree, computes a CRC32 + cryptographic hash for
every file, and writes three artifacts into the output directory:

    checksums.txt   human-readable report grouped by directory
    checksums.csv   flat spreadsheet data (Excel-safe ="VALUE" wrapping)
    summary.txt     80-char aggregate receipt (counts, timing, delta metrics)

Supports delta comparison against a prior manifest (--baseline) and an
integrity gate that fails the process on drift (--verify / --fail-on-modified).
"""
import argparse
import csv
import fnmatch
import hashlib
import os
import subprocess
import sys
import time
import zlib

__version__ = "2.0.0"

# Exit codes
EXIT_OK = 0
EXIT_LOCK_ERRORS = 2      # one or more files could not be read (degrade to UNSTABLE)
EXIT_VERIFY_DRIFT = 3     # --verify found added/modified/deleted files
EXIT_FAIL_ON_MODIFIED = 4  # --fail-on-modified found modified/deleted files

# Repeated literals
COL_FILE_PATH = "FILE PATH"
CURSOR_SHOW = "\x1b[?25h"   # ANSI: show terminal cursor
CURSOR_HIDE = "\x1b[?25l"   # ANSI: hide terminal cursor


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        prog="checksum_generator",
        description="Generate CRC32 + hash manifests for a directory tree, "
                    "with optional delta comparison against a baseline.",
    )
    parser.add_argument("--root", default=".",
                        help="Directory tree to scan (default: current directory).")
    parser.add_argument("--out-dir", default="checksums",
                        help="Directory to write manifest artifacts into "
                             "(default: ./checksums).")
    parser.add_argument("--ci", action="store_true",
                        help="CI mode: emit machine-readable metrics, suppress "
                             "the interactive progress bar.")
    parser.add_argument("--baseline", metavar="PATH", default="",
                        help="Prior manifest (.csv or .txt) to compute deltas "
                             "against. Does not affect exit code on its own.")
    parser.add_argument("--verify", metavar="PATH", default="",
                        help="Like --baseline, but exit non-zero if any file was "
                             "added, modified, or deleted relative to the manifest.")
    parser.add_argument("--fail-on-modified", action="store_true",
                        help="Exit non-zero if any baseline file was modified or "
                             "deleted (additions allowed).")
    parser.add_argument("--exclude", metavar="GLOB", action="append", default=[],
                        help="Glob of paths to skip (repeatable), e.g. '*.log'.")
    parser.add_argument("--include", metavar="GLOB", action="append", default=[],
                        help="If given, only paths matching one of these globs "
                             "are scanned (repeatable).")
    parser.add_argument("--algorithm", default="sha256",
                        choices=["sha256", "sha1", "sha512", "md5"],
                        help="Cryptographic hash algorithm (default: sha256). "
                             "CRC32 is always included.")
    parser.add_argument("--version", action="version",
                        version=f"%(prog)s {__version__}")
    return parser.parse_args(argv)


def _win_gateway():
    """Parse the default gateway from Windows `route print` output."""
    out = subprocess.check_output(["route", "print", "0.0.0.0"],
                                  stderr=subprocess.DEVNULL).decode("utf-8", "ignore")
    for line in out.splitlines():
        cols = line.split()
        if len(cols) >= 5 and cols[0] == "0.0.0.0":
            return cols[2]
    return None


def _unix_gateway():
    """Parse the default gateway from Linux `ip route` output."""
    out = subprocess.check_output(["ip", "route"],
                                  stderr=subprocess.DEVNULL).decode("utf-8", "ignore")
    for line in out.splitlines():
        if line.startswith("default"):
            parts = line.split()
            if "via" in parts:
                return parts[parts.index("via") + 1]
    return None


def detect_gateway():
    """Best-effort default-gateway lookup across Linux and Windows."""
    try:
        gateway = _win_gateway() if sys.platform.startswith("win") else _unix_gateway()
        if gateway:
            return gateway
    except Exception:
        pass
    return "unknown-gateway"


def compute_output_paths(out_dir):
    """Return (txt, csv, summary) paths, versioned per build when in Jenkins."""
    txt = os.path.join(out_dir, "checksums.txt")
    csv_path = os.path.join(out_dir, "checksums.csv")
    summary = os.path.join(out_dir, "summary.txt")

    build_number = os.environ.get("BUILD_NUMBER")
    if build_number:
        branch = os.environ.get("BRANCH_NAME") or os.environ.get("GIT_BRANCH") or "local"
        safe_branch = "".join(c if c.isalnum() or c in "_-" else "_" for c in branch)
        suffix = f"-{safe_branch}-b{build_number}"
        txt = os.path.join(out_dir, f"checksums{suffix}.txt")
        csv_path = os.path.join(out_dir, f"checksums{suffix}.csv")
        summary = os.path.join(out_dir, f"summary{suffix}.txt")
    return txt, csv_path, summary


def _unwrap(cell):
    """Strip the Excel-safe ="VALUE" wrapper produced in the CSV output."""
    cell = cell.strip()
    if cell.startswith('="') and cell.endswith('"'):
        cell = cell[2:-1]
    # A leading '/' guard is added to values that begin with a spreadsheet
    # control character; drop it so the stored path round-trips cleanly.
    if cell.startswith("/") and len(cell) > 1 and cell[1] in "0=+-":
        cell = cell[1:]
    return cell


def _is_baseline_metadata(stripped):
    """True for blank/comment/header lines that carry no manifest entry."""
    if not stripped or stripped.startswith("#") or stripped.startswith("="):
        return True
    return (COL_FILE_PATH in stripped or "Cross-Platform" in stripped
            or "Generated:" in stripped or "Gateway:" in stripped)


def _parse_csv_baseline_row(stripped):
    """Return (path, crc, sha) from an Excel-safe CSV line, or None."""
    row = next(csv.reader([stripped]))
    if len(row) < 3:
        return None
    return _unwrap(row[0]), _unwrap(row[1]), _unwrap(row[2])


def _parse_text_baseline_row(stripped):
    """Return (path, crc, sha) from a whitespace-aligned text line, or None.

    Parsed from the right so paths containing spaces survive intact.
    """
    body = stripped
    # Drop a trailing "[STATUS]" tag if present.
    if body.endswith("]") and "[" in body:
        body = body[:body.rfind("[")].rstrip()
    try:
        left, sha = body.rsplit(None, 1)
        path, crc = left.rstrip().rsplit(None, 1)
        return path.strip(), crc, sha
    except ValueError:
        return None


def parse_baseline(baseline_file):
    """Parse a prior manifest into {clean_path: {'crc':..., 'sha':...}}.

    Handles both the Excel-safe CSV format and the whitespace-aligned text
    format.
    """
    manifests = {}
    if not baseline_file or not os.path.isfile(baseline_file):
        return manifests

    is_csv = baseline_file.lower().endswith(".csv")
    try:
        with open(baseline_file, "r", encoding="utf-8", errors="ignore") as bf:
            for line in bf:
                stripped = line.strip()
                if _is_baseline_metadata(stripped):
                    continue
                parsed = _parse_csv_baseline_row(stripped) if is_csv \
                    else _parse_text_baseline_row(stripped)
                if not parsed:
                    continue
                path, crc, sha = parsed
                if path:
                    manifests[path] = {"crc": crc, "sha": sha}
    except Exception as e:
        print(f"Pipeline Warning: Error parsing baseline manifest: {e}",
              file=sys.stderr)
    return manifests


def should_scan(rel_path, includes, excludes):
    """Apply --include / --exclude glob filters to a forward-slash rel path."""
    if excludes and any(fnmatch.fnmatch(rel_path, pat) for pat in excludes):
        return False
    if includes and not any(fnmatch.fnmatch(rel_path, pat) for pat in includes):
        return False
    return True


def _detect_ci_mode(args):
    """True when running under CI (explicit flag or well-known env vars)."""
    return args.ci or bool(
        os.environ.get("JENKINS_URL") or os.environ.get("GITHUB_ACTIONS")
        or os.environ.get("CI"))


def _prepare_out_dir(out_dir, artifact_files):
    """Create the output directory and remove any stale artifacts."""
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    for stale in artifact_files:
        if os.path.isfile(stale):
            os.remove(stale)


def _is_output_artifact(name, out_basenames):
    """True when name is one of this run's own manifest artifacts."""
    if name in out_basenames:
        return True
    return ((name.startswith("checksums") and name.endswith((".txt", ".csv")))
            or (name.startswith("summary") and name.endswith(".txt")))


def _scannable_files(dir_root, root, files, out_basenames, includes, excludes):
    """Return the forward-slash clean paths in one directory that pass the
    output-artifact and include/exclude filters."""
    out = []
    for name in files:
        clean_path = os.path.relpath(os.path.join(dir_root, name), root).replace("\\", "/")
        if _is_output_artifact(name, out_basenames):
            continue
        if should_scan(clean_path, includes, excludes):
            out.append(clean_path)
    return out


def _is_out_subtree(rel_dir, norm_out):
    """True when rel_dir is the output directory or lives beneath it."""
    return rel_dir != "." and (rel_dir == norm_out or rel_dir.startswith(norm_out + "/"))


def _bucket_files(clean_paths, rel_dir, root_files, folder_map):
    """Sort each path into root_files (rel_dir == '.') or folder_map, returning
    the longest path length seen (0 when empty)."""
    longest = 0
    for clean_path in clean_paths:
        longest = max(longest, len(clean_path))
        if rel_dir == ".":
            root_files.append(clean_path)
        else:
            folder_map.setdefault(rel_dir, []).append(clean_path)
    return longest


def _scan_tree(root, out_dir, out_basenames, includes, excludes):
    """Walk root, returning (final_file_list, sorted_folders, unique_folders,
    max_path_len). Output artifacts and the out-dir subtree are skipped."""
    root_files = []
    folder_map = {}
    unique_folders = set()
    max_path_len = len(COL_FILE_PATH)

    norm_out = out_dir.replace("\\", "/").rstrip("/")
    for dir_root, dirs, files in os.walk(root):
        if ".git" in dirs:
            dirs.remove(".git")

        rel_dir = os.path.relpath(dir_root, root).replace("\\", "/")
        if _is_out_subtree(rel_dir, norm_out):
            dirs[:] = []
            continue
        if rel_dir != ".":
            unique_folders.add(rel_dir)

        scannable = _scannable_files(dir_root, root, files, out_basenames, includes, excludes)
        max_path_len = max(max_path_len, _bucket_files(scannable, rel_dir, root_files, folder_map))

    root_files.sort(key=str.lower)
    sorted_folders = sorted(folder_map.keys(), key=str.lower)
    for folder in sorted_folders:
        folder_map[folder].sort(key=str.lower)

    final_file_list = root_files + [p for f in sorted_folders for p in folder_map[f]]
    return final_file_list, sorted_folders, unique_folders, max_path_len


def _build_layout(max_path_len, hash_hex_len, hash_label, has_baseline_context):
    """Return (col_width, separator_line, header_columns, csv_headers)."""
    col_width = max_path_len + 4
    separator_line = "=" * (col_width + 10 + hash_hex_len + 2)
    header_columns = f'{COL_FILE_PATH:<{col_width}} {"CRC32":<10} {hash_label}\n'
    if has_baseline_context:
        csv_headers = [COL_FILE_PATH, "CRC32", hash_label, "DELTA STATUS"]
    else:
        csv_headers = [COL_FILE_PATH, "CRC32", hash_label]
    return col_width, separator_line, header_columns, csv_headers


def _hash_one(path, algorithm):
    """Return (crc_hex, sha_hex) for a single file, streamed in 64 KiB chunks."""
    hasher = hashlib.new(algorithm)
    crc = 0
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            hasher.update(chunk)
            crc = zlib.crc32(chunk, crc)
    return f"{crc & 0xffffffff:08x}", hasher.hexdigest()


def _delta_status(clean_path, sha_str, baseline_manifests, metrics):
    """Classify a file against the baseline; update metrics and return
    (status_tag, csv_status)."""
    if clean_path not in baseline_manifests:
        metrics["added"] += 1
        return " [ADDED]", "ADDED"
    if baseline_manifests[clean_path]["sha"] == sha_str:
        metrics["unchanged"] += 1
        return " [UNCHANGED]", "UNCHANGED"
    metrics["modified"] += 1
    return " [MODIFIED]", "MODIFIED"


def _process_entry(clean_path, root, args, col_width, has_baseline_context,
                   baseline_manifests, metrics):
    """Hash one file and return (line_item, csv_row, failed)."""
    try:
        crc_str, sha_str = _hash_one(os.path.join(root, clean_path), args.algorithm)
        status_tag, csv_status = "", None
        if has_baseline_context:
            status_tag, csv_status = _delta_status(clean_path, sha_str,
                                                    baseline_manifests, metrics)
        line_item = f"{clean_path:<{col_width}} {crc_str:<10} {sha_str}{status_tag}"

        # Excel-safe wrapping. Guard control-char leads without corrupting the value.
        safe_path = f'="{clean_path}"'
        if clean_path[:1] in ("0", "=", "+", "-"):
            safe_path = f'="\'{clean_path}"'
        row = [safe_path, f'="{crc_str}"', f'="{sha_str}"']
        if has_baseline_context:
            row.append(f'="{csv_status}"')
        return line_item, row, False
    except Exception as e:
        line_item = f'{clean_path:<{col_width}} {"[FAILED]":<10} [ERROR: FILE ACCESS LOCK]'
        row = [f'="{clean_path}"', '="FAILED"', '="ERROR: FILE ACCESS LOCK"']
        if has_baseline_context:
            row.append('="ACCESS_DENIED"')
        print(f"Pipeline Alert: Could not hash target path -> {clean_path}. "
              f"Reason: {e}", file=sys.stderr)
        return line_item, row, True


def _route_line_item(structured_report, clean_path, line_item):
    """Append line_item under its parent directory bucket (or 'root')."""
    parent_dir = os.path.dirname(clean_path).replace("\\", "/")
    if parent_dir and parent_dir != "." and parent_dir in structured_report:
        structured_report[parent_dir].append(line_item)
    else:
        structured_report["root"].append(line_item)


def _render_progress(idx, total_files, start_time, current_time, clean_path,
                     last_refresh_time, is_ci_mode):
    """Emit one progress line. Returns the (possibly updated) last_refresh_time."""
    if is_ci_mode:
        if idx % max(1, total_files // 10) == 0 or idx == total_files:
            print(f"Pipeline Progress: Processing files... [{idx}/{total_files}] "
                  f"({int((idx / total_files) * 100)}%)")
        return last_refresh_time
    if (current_time - last_refresh_time >= 0.5) or idx == total_files:
        disp = clean_path if len(clean_path) <= 25 else "..." + clean_path[-22:]
        elapsed = int(current_time - start_time) or 1
        left = int(((elapsed * total_files) / idx) - elapsed)
        left_str = f"{left}s" if left < 60 else f"{left // 60}m {left % 60}s"
        elapsed_str = f"{elapsed}s" if elapsed < 60 else f"{elapsed // 60}m {elapsed % 60}s"
        sys.stdout.write(
            f"\r\x1b[2KProgress: [{idx}/{total_files}] | Time: {elapsed_str} "
            f"| Left: {left_str} | Target: {disp}")
        sys.stdout.flush()
        return current_time
    return last_refresh_time


def _run_core_loop(final_file_list, sorted_folders, root, args, col_width,
                   has_baseline_context, baseline_manifests, is_ci_mode,
                   start_time, total_files):
    """Hash every file, building the structured report and CSV rows. Returns
    (structured_report, csv_data_rows, has_failures, metrics, processed_paths)."""
    structured_report = {"root": []}
    for folder in sorted_folders:
        structured_report[folder] = []
    csv_data_rows = []
    has_failures = False
    processed_paths = set()
    metrics = {"added": 0, "modified": 0, "deleted": 0, "unchanged": 0}
    last_refresh_time = 0.0

    for idx, clean_path in enumerate(final_file_list, 1):
        processed_paths.add(clean_path)
        last_refresh_time = _render_progress(idx, total_files, start_time, time.time(),
                                             clean_path, last_refresh_time, is_ci_mode)
        line_item, row, failed = _process_entry(clean_path, root, args, col_width,
                                                 has_baseline_context, baseline_manifests,
                                                 metrics)
        csv_data_rows.append(row)
        has_failures = has_failures or failed
        _route_line_item(structured_report, clean_path, line_item)

    return structured_report, csv_data_rows, has_failures, metrics, processed_paths


def _collect_deleted(baseline_manifests, processed_paths, col_width, metrics, csv_data_rows):
    """Record baseline files absent this run as DELETED. Returns text lines and
    appends matching CSV rows."""
    deleted_items = []
    for old_path, meta in baseline_manifests.items():
        if old_path in processed_paths:
            continue
        metrics["deleted"] += 1
        deleted_items.append(
            f'{old_path:<{col_width}} {meta["crc"]:<10} {meta["sha"]} [DELETED]')
        csv_data_rows.append(
            [f'="{old_path}"', f'="{meta["crc"]}"', f'="{meta["sha"]}"', '="DELETED"'])
    return deleted_items


def _write_empty_manifests(paths, header_columns, separator_line, standard_80_line,
                           col_width, csv_headers, timestamp, default_gateway):
    """Write placeholder manifests for an empty directory tree."""
    output_file, csv_output_file, summary_output_file = paths
    with open(output_file, "w", newline="", encoding="utf-8") as f:
        f.write(separator_line + "\n")
        f.write(header_columns)
        f.write(separator_line + "\n")
        f.write(f'{"  [No target files detected in this directory tree]":<{col_width}}\n')
        f.write(separator_line + "\n")
    with open(csv_output_file, "w", newline="", encoding="utf-8") as cf:
        csv.writer(cf).writerow(csv_headers)
    with open(summary_output_file, "w", newline="", encoding="utf-8") as sf:
        sf.write(standard_80_line + "\n")
        sf.write("Streamed Cross-Platform Checksum Summary\n")
        sf.write(f"Generated:               {timestamp}\n")
        sf.write(f"Gateway:                 {default_gateway}\n")
        sf.write(standard_80_line + "\n")
        sf.write("Execution Summary Manifest\n")
        sf.write("Total Folders Traversed: 0\n")
        sf.write("Total Files Processed:   0\n")
        sf.write(standard_80_line + "\n")


def _write_text_report(output_file, structured_report, sorted_folders, deleted_items,
                       separator_line, header_columns):
    """Write the human-readable grouped-by-directory checksum report."""
    with open(output_file, "w", newline="", encoding="utf-8") as f:
        if structured_report["root"]:
            f.write("# DIRECTORY: Root Workspace Cluster [.]\n")
            f.write(f'# Context Summary: Contains {len(structured_report["root"])} files direct\n')
            f.write(separator_line + "\n")
            f.write(header_columns)
            f.write(separator_line + "\n")
            f.write("\n".join(structured_report["root"]) + "\n")

        for folder in sorted_folders:
            if structured_report[folder]:
                sub_count = sum(1 for sf in sorted_folders if sf.startswith(folder + "/"))
                f.write(f"\n\n# DIRECTORY: {folder}\n")
                f.write(f"# Context Summary: Contains {len(structured_report[folder])} "
                        f"target files | {sub_count} nested sub-folders\n")
                f.write(separator_line + "\n")
                f.write(header_columns)
                f.write(separator_line + "\n")
                f.write("\n".join(structured_report[folder]) + "\n")

        if deleted_items:
            f.write("\n\n# REMOVED/DELETED FILE MANIFEST ENTRIES\n")
            f.write(f"# Context Summary: Contains {len(deleted_items)} missing "
                    f"elements mapped out of workspace\n")
            f.write(separator_line + "\n")
            f.write(header_columns)
            f.write(separator_line + "\n")
            f.write("\n".join(deleted_items) + "\n")


def _write_summary(summary_output_file, timestamp, default_gateway, has_baseline_context,
                   baseline_file, duration_str, total_folders, total_files, metrics,
                   standard_80_line):
    """Write the 80-char aggregate summary receipt."""
    with open(summary_output_file, "w", newline="", encoding="utf-8") as sf:
        sf.write(standard_80_line + "\n")
        sf.write("Streamed Cross-Platform Checksum Summary\n")
        sf.write(f"Generated:               {timestamp}\n")
        sf.write(f"Gateway:                 {default_gateway}\n")
        if has_baseline_context:
            sf.write(f"Baseline Mapped Source:  {os.path.basename(baseline_file)}\n")
        sf.write(standard_80_line + "\n")
        sf.write("Execution Summary Manifest\n")
        sf.write(f"Total Execution Time:    {duration_str}\n")
        sf.write(f"Total Folders Traversed: {total_folders}\n")
        sf.write(f"Total Files Processed:   {total_files}\n")
        if has_baseline_context:
            sf.write(f'Delta Metrics Summary:   [Added: {metrics["added"]} | '
                     f'Modified: {metrics["modified"]} | Deleted: {metrics["deleted"]} '
                     f'| Unchanged: {metrics["unchanged"]}]\n')
        sf.write(standard_80_line + "\n")


def _finalize_progress(total_files, start_time):
    """Print the terminal completion line and restore the cursor."""
    elapsed = int(time.time() - start_time) or 1
    elapsed_str = f"{elapsed}s" if elapsed < 60 else f"{elapsed // 60}m {elapsed % 60}s"
    sys.stdout.write(
        f"\r\x1b[2KProgress: [{total_files}/{total_files}] | Total Time: "
        f"{elapsed_str} | Left: 0s | Target: Execution finalized\n")
    sys.stdout.flush()
    sys.stdout.write(CURSOR_SHOW)


def _emit_ci_metrics(output_file, csv_output_file, summary_output_file,
                     has_baseline_context, metrics, has_failures):
    """Print machine-readable KEY=VALUE metrics for CI consumption."""
    print(f"OUTPUT_METRICS_TARGET_FILE={output_file}")
    print(f"OUTPUT_METRICS_CSV_FILE={csv_output_file}")
    print(f"OUTPUT_METRICS_SUMMARY_FILE={summary_output_file}")
    print(f"OUTPUT_METRICS_HAS_BASELINE={'true' if has_baseline_context else 'false'}")
    print(f"OUTPUT_METRICS_DELTA_ADDED={metrics['added']}")
    print(f"OUTPUT_METRICS_DELTA_MODIFIED={metrics['modified']}")
    print(f"OUTPUT_METRICS_DELTA_DELETED={metrics['deleted']}")
    print(f"OUTPUT_METRICS_HAS_LOCK_ERRORS={'true' if has_failures else 'false'}")


def _final_exit_code(has_failures, verify_mode, fail_on_modified, metrics):
    """Map the run outcome to a process exit code, logging gate failures."""
    if has_failures:
        return EXIT_LOCK_ERRORS
    if verify_mode and (metrics["added"] or metrics["modified"] or metrics["deleted"]):
        print("Verification failed: manifest drift detected "
              f"(added={metrics['added']} modified={metrics['modified']} "
              f"deleted={metrics['deleted']}).", file=sys.stderr)
        return EXIT_VERIFY_DRIFT
    if fail_on_modified and (metrics["modified"] or metrics["deleted"]):
        print("Integrity gate failed: baseline files were modified or deleted "
              f"(modified={metrics['modified']} deleted={metrics['deleted']}).",
              file=sys.stderr)
        return EXIT_FAIL_ON_MODIFIED
    return EXIT_OK


def main(argv=None):
    args = parse_args(argv)
    start_time = time.time()
    is_ci_mode = _detect_ci_mode(args)

    root = args.root
    out_dir = args.out_dir
    output_file, csv_output_file, summary_output_file = compute_output_paths(out_dir)

    # --verify is --baseline with a drift gate.
    baseline_file = args.verify or args.baseline
    verify_mode = bool(args.verify)

    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    default_gateway = detect_gateway()

    _prepare_out_dir(out_dir, (output_file, csv_output_file, summary_output_file))

    hasher_probe = hashlib.new(args.algorithm)
    hash_hex_len = hasher_probe.digest_size * 2
    hash_label = "SHA256 CHECKSUM" if args.algorithm == "sha256" \
        else f"{args.algorithm.upper()} CHECKSUM"

    out_basenames = {os.path.basename(output_file), os.path.basename(csv_output_file),
                     os.path.basename(summary_output_file),
                     os.path.basename(baseline_file) if baseline_file else ""}

    if not is_ci_mode:
        sys.stdout.write(CURSOR_HIDE)
    print(f"Scanning directory tree... Target Manifest Repository Folder: ./{out_dir}/")

    final_file_list, sorted_folders, unique_folders, max_path_len = _scan_tree(
        root, out_dir, out_basenames, args.include, args.exclude)
    total_files = len(final_file_list)
    total_folders = len(unique_folders)

    standard_80_line = "=" * 80
    has_baseline_context = bool(baseline_file and os.path.isfile(baseline_file))
    col_width, separator_line, header_columns, csv_headers = _build_layout(
        max_path_len, hash_hex_len, hash_label, has_baseline_context)

    # ------------------------------------------------------- Empty tree short-circuit
    if total_files == 0:
        _write_empty_manifests(
            (output_file, csv_output_file, summary_output_file),
            header_columns, separator_line, standard_80_line, col_width,
            csv_headers, timestamp, default_gateway)
        if not is_ci_mode:
            sys.stdout.write(CURSOR_SHOW)
        return EXIT_OK

    baseline_manifests = parse_baseline(baseline_file) if has_baseline_context else {}

    structured_report, csv_data_rows, has_failures, metrics, processed_paths = _run_core_loop(
        final_file_list, sorted_folders, root, args, col_width,
        has_baseline_context, baseline_manifests, is_ci_mode, start_time, total_files)

    deleted_items = []
    if has_baseline_context:
        deleted_items = _collect_deleted(baseline_manifests, processed_paths,
                                         col_width, metrics, csv_data_rows)

    _write_text_report(output_file, structured_report, sorted_folders,
                       deleted_items, separator_line, header_columns)

    with open(csv_output_file, "w", newline="", encoding="utf-8") as cf:
        writer = csv.writer(cf)
        writer.writerow(csv_headers)
        writer.writerows(csv_data_rows)

    elapsed_total = int(time.time() - start_time) or 1
    duration_str = f"{elapsed_total}s" if elapsed_total < 60 \
        else f"{elapsed_total // 60}m {elapsed_total % 60}s"
    _write_summary(summary_output_file, timestamp, default_gateway, has_baseline_context,
                   baseline_file, duration_str, total_folders, total_files, metrics,
                   standard_80_line)

    if not is_ci_mode:
        _finalize_progress(total_files, start_time)

    if is_ci_mode:
        _emit_ci_metrics(output_file, csv_output_file, summary_output_file,
                         has_baseline_context, metrics, has_failures)

    return _final_exit_code(has_failures, verify_mode, args.fail_on_modified, metrics)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stdout.write(CURSOR_SHOW)
        sys.exit(1)
# * UNCLASSIFIED                 UNCLASSIFIED                 UNCLASSIFIED *
