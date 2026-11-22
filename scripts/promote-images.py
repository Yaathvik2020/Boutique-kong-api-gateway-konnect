#!/usr/bin/env python3
"""Copy the `images:` block of one kustomization.yaml into another.

    scripts/promote-images.py <source kustomization> <target kustomization>

Only the images block changes in the target; everything else (comments, patches) stays.
"""
import re
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
block = re.compile(r"^images:.*?(?=^\S|\Z)", re.S | re.M)  # from "images:" to the next top-level key

src = open(src_path).read()
dst = open(dst_path).read()
m_src, m_dst = block.search(src), block.search(dst)
if not m_src or not m_dst:
    sys.exit("images: block not found in source or target")

new_block = m_src.group(0)
# keep the target's own comment on the "images:" line
new_block = new_block.replace(new_block.splitlines()[0], m_dst.group(0).splitlines()[0], 1)
open(dst_path, "w").write(dst[: m_dst.start()] + new_block + dst[m_dst.end():])
print(f"images copied: {src_path} -> {dst_path}")
