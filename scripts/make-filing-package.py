#!/usr/bin/env python3
"""Build and lint the ethereum/ERCs submission package for the Swarm AI Framework proposal.

Source of truth: ERCS/erc-sai.md and assets/erc-sai/{contracts,schemas,examples,vectors}. The package
mirrors the ERCs repository layout:

    <out>/ERCS/erc-<N>.md
    <out>/assets/erc-<N>/contracts/...   (links inside the ERC text are written ../assets/eip-<N>/...,
    <out>/assets/erc-<N>/schemas/...      because the ERCs site build renames erc-* to eip-*)
    <out>/assets/erc-<N>/examples/...
    <out>/assets/erc-<N>/vectors/...

Usage:
    python3 scripts/make-filing-package.py --allow-tbd                       # dry run with the placeholder number
    python3 scripts/make-filing-package.py --discussions https://ethereum-magicians.org/t/<slug>/<id>
    python3 scripts/make-filing-package.py --number 8NNN --discussions https://ethereum-magicians.org/t/<slug>/<id>

The script exits non-zero when any lint fails. The lints approximate the ERCs CI (eipw + HTMLProofer) and
the repository rule "no Chinese in any shipped file"; they are not a substitute for CI. For the real eipw,
run eipw-lint-js 0.11.0 with the ERCs repository's config/eipw.toml over the produced file.
"""
import argparse, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_MD = os.path.join(ROOT, "ERCS", "erc-sai.md")
SRC_ASSETS = os.path.join(ROOT, "assets", "erc-sai")
PLACEHOLDER = "9999"   # working number carried by the source files until the editors assign one
ASSET_SUBDIRS = ("contracts", "schemas", "examples", "vectors")

# Companion drafts not merged into ethereum/ERCs: a literal "ERC-N" would need a link to a file that does
# not exist there (HTMLProofer 404) or be flagged by eipw's link-first rule. Refer to them descriptively.
UNMERGED = {"8338", "8414", "8419", "8434"}
REQUIRED_SECTIONS = ["Abstract", "Motivation", "Specification", "Rationale", "Backwards Compatibility",
                     "Test Cases", "Reference Implementation", "Security Considerations", "Copyright"]
CJK = re.compile("[\\u3000-\\u303f\\u3400-\\u4dbf\\u4e00-\\u9fff\\uff00-\\uffef]")
RFC2119 = re.compile(r"\b(MUST|MUST NOT|REQUIRED|SHALL|SHALL NOT|SHOULD|SHOULD NOT|RECOMMENDED|NOT RECOMMENDED|MAY|OPTIONAL)\b")
SMART_QUOTES = re.compile("[\\u201c\\u201d\\u2018\\u2019]")


def fail(msgs):
    for m in msgs:
        print("LINT FAIL:", m)
    sys.exit(1)


def strip_code(body):
    """Remove fenced code blocks and inline code spans (eipw link lints look at link nodes only)."""
    body = re.sub(r"```.*?```", "", body, flags=re.S)
    return re.sub(r"`[^`\n]*`", "", body)


def lint_erc(text, number, discussions_ok):
    errors = []
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return ["preamble block missing"], ""
    pre = dict(line.split(": ", 1) for line in m.group(1).splitlines() if ": " in line)
    order = [line.split(":", 1)[0] for line in m.group(1).splitlines()]
    expected = ["eip", "title", "description", "author", "discussions-to", "status", "type", "category", "created", "requires"]
    if order != expected:
        errors.append(f"preamble field order {order} != {expected}")
    if pre.get("eip") != number:
        errors.append(f"eip field is {pre.get('eip')}, expected {number}")
    title = pre.get("title", "")
    if len(title) > 44:
        errors.append(f"title longer than 44 characters ({len(title)})")
    if re.search(r"standar", title, re.I):
        errors.append("title must not contain 'standard'")
    desc = pre.get("description", "")
    if len(desc) > 140:
        errors.append(f"description longer than 140 characters ({len(desc)})")
    if re.search(r"\b(EIP|ERC)\b", desc) or ":" in desc or re.search(r"standar", desc, re.I):
        errors.append("description must not contain 'EIP', 'ERC', 'standard' or a colon")
    d = pre.get("discussions-to", "")
    if not re.match(r"^https://ethereum-magicians\.org/t/[^/]+/[0-9]+$", d) or d.endswith("/0"):
        if not discussions_ok:
            errors.append("discussions-to must be a real Ethereum Magicians thread URL (pass --discussions)")
    nums = [int(x) for x in re.findall(r"\d+", pre.get("requires", ""))]
    if nums != sorted(nums):
        errors.append("requires must be sorted ascending")
    body = text[m.end():]
    heads = re.findall(r"^## (.+)$", body, re.M)
    idx = [heads.index(h) for h in REQUIRED_SECTIONS if h in heads]
    missing = [h for h in REQUIRED_SECTIONS if h not in heads]
    if missing:
        errors.append(f"missing sections: {missing}")
    if idx != sorted(idx):
        errors.append("required sections out of order")
    extra = [h for h in heads if h not in REQUIRED_SECTIONS]
    if extra:
        errors.append(f"extra top-level sections: {extra}")
    if not body.rstrip().endswith("Copyright and related rights waived via [CC0](../LICENSE.md)."):
        errors.append("file must end with the CC0 copyright line")
    if SMART_QUOTES.search(body):
        errors.append("smart quotes present (eipw markdown-no-smart-quotes)")
    prose = strip_code(body)
    for url in re.findall(r"\]\((https?://[^)\s]+)\)", prose):
        if url.startswith("https://www.rfc-editor.org/rfc/"):
            continue
        errors.append(f"external link in body: {url}")
    for url in re.findall(r"https?://[^\s)\]`]+", prose):
        if url.startswith("https://www.rfc-editor.org/rfc/"):
            continue
        errors.append(f"external URL in prose: {url}")
    for n in UNMERGED:
        if re.search(rf"\b(EIP|ERC)-{n}\b", body):
            errors.append(f"literal ERC-{n} mention: unmerged draft, refer to it descriptively")
    seen = set()
    for mm in re.finditer(r"(\[)?(EIP|ERC)-(\d+)(\]\(\./eip-(\d+)\.md\))?", prose):
        n = mm.group(3)
        if n in seen:
            continue
        seen.add(n)
        if not (mm.group(1) and mm.group(4) and mm.group(5) == n):
            errors.append(f"first mention of {mm.group(2)}-{n} is not a link to ./eip-{n}.md")
    for span in re.findall(r"`([^`\n]*)`", re.sub(r"```.*?```", "", body, flags=re.S)):
        if re.search(r"(?i)(eip|erc)-[0-9]+", span):
            errors.append(f"proposal reference inside backticks (eipw markdown-no-backticks): `{span}`")
    for bad in re.findall(r"\b(?:EIP|ERC)\s*[0-9]+\b|\b(?:EIP|ERC)[0-9]+\b", prose):
        errors.append(f"proposal reference without dash: {bad}")
    sec = re.search(r"^## Security Considerations\n(.*?)^## Copyright", body, re.S | re.M)
    if sec and RFC2119.search(sec.group(1)):
        errors.append("RFC 2119 keywords inside Security Considerations")
    if f"eip-{PLACEHOLDER}/" in body and number != PLACEHOLDER:
        errors.append("placeholder asset links were not rewritten")
    if CJK.search(text):
        errors.append("CJK characters present in the ERC text")
    return errors, body


def check_asset_links(body, number, pkg_root):
    errors = []
    for rel, n in re.findall(r"\]\((\.\./assets/eip-(\d+)/[^)]+)\)", body):
        if n != number:
            errors.append(f"asset link with wrong number: {rel}")
        local = os.path.join(pkg_root, "assets", f"erc-{n}", rel.split(f"/eip-{n}/", 1)[1])
        if rel.endswith("/"):
            errors.append(f"directory-style asset link (HTMLProofer 404): {rel}")
        elif not os.path.isfile(local):
            errors.append(f"asset link target missing in package: {rel}")
    return errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--number", default=PLACEHOLDER, help="ERC number to file under (default: the 9999 placeholder)")
    ap.add_argument("--discussions", default=None, help="Ethereum Magicians thread URL for discussions-to")
    ap.add_argument("--out", default=os.path.join(ROOT, "ercs-pr-package"))
    ap.add_argument("--allow-tbd", action="store_true", help="allow a placeholder discussions-to (dry runs only)")
    args = ap.parse_args()
    number = args.number

    text = open(SRC_MD, encoding="utf-8").read()
    text = re.sub(r"^eip: \d+$", f"eip: {number}", text, count=1, flags=re.M)
    if args.discussions:
        text = re.sub(r"^discussions-to: .*$", f"discussions-to: {args.discussions}", text, count=1, flags=re.M)
    text = text.replace(f"../assets/eip-{PLACEHOLDER}/", f"../assets/eip-{number}/")

    if os.path.isdir(args.out):
        shutil.rmtree(args.out)
    os.makedirs(os.path.join(args.out, "ERCS"))
    dst_assets = os.path.join(args.out, "assets", f"erc-{number}")
    for sub in ASSET_SUBDIRS:
        src = os.path.join(SRC_ASSETS, sub)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dst_assets, sub))
    if number != PLACEHOLDER:
        for root, _, files in os.walk(dst_assets):
            for f in files:
                if f.endswith((".json", ".sol", ".md")):
                    p = os.path.join(root, f)
                    t = open(p, encoding="utf-8").read()
                    t2 = t.replace(f"eip-{PLACEHOLDER}", f"eip-{number}").replace(f"erc-{PLACEHOLDER}", f"erc-{number}")
                    if t2 != t:
                        open(p, "w", encoding="utf-8").write(t2)
    md_path = os.path.join(args.out, "ERCS", f"erc-{number}.md")
    open(md_path, "w", encoding="utf-8").write(text)

    errors, body = lint_erc(text, number, args.allow_tbd)
    errors += check_asset_links(body, number, args.out)
    for root, _, files in os.walk(args.out):
        for f in files:
            p = os.path.join(root, f)
            try:
                if CJK.search(open(p, encoding="utf-8").read()):
                    errors.append(f"CJK characters in {os.path.relpath(p, args.out)}")
            except UnicodeDecodeError:
                pass
    if errors:
        fail(errors)
    n_files = sum(len(f) for _, _, f in os.walk(args.out))
    print(f"package ok: {os.path.relpath(args.out, ROOT)} ({n_files} files), ERC-{number}")


if __name__ == "__main__":
    main()
