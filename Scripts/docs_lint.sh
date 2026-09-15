#!/usr/bin/env bash
set -euo pipefail

# EN: Validate Markdown structure, metadata, naming, lifecycle, and local links.
# ES: Valida la estructura, metadatos, nombres, ciclo de vida y enlaces locales.
# 中文：检查 Markdown 的结构、元数据、命名、生命周期和本地链接。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

python3 - "${PROJECT_DIR}" <<'PY'
from __future__ import annotations

# EN: This checker uses only the Python standard library and never changes files.
# ES: Este verificador usa solo la biblioteca estándar y nunca modifica archivos.
# 中文：检查器只使用 Python 标准库，且不会修改任何文件。

import datetime as dt
import re
import sys
from pathlib import Path
from urllib.parse import unquote


project = Path(sys.argv[1]).resolve()
docs = project / "docs"
today = dt.date.today()
allowed_types = {"product", "planning", "architecture", "protocol", "research", "history", "archive", "policy"}
allowed_statuses = {"draft", "active", "stable", "superseded", "archived"}
required = {"doc_id", "title", "type", "status", "canonical", "domain", "owner", "created", "last_reviewed", "related_builds", "supersedes", "superseded_by"}
errors: list[str] = []
warnings: list[str] = []


def front_matter(path: Path) -> tuple[dict[str, object], str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, ""
    end = next((index for index, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
    if end is None:
        return {}, ""
    values: dict[str, object] = {}
    list_key: str | None = None
    for line in lines[1:end]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("-") and list_key:
            current = values.setdefault(list_key, [])
            if isinstance(current, list):
                current.append(stripped[1:].strip())
            continue
        if ":" not in line:
            list_key = None
            continue
        key, raw = line.split(":", 1)
        key, value = key.strip(), raw.strip()
        if not value:
            values[key] = []
            list_key = key
        elif value in {"true", "false"}:
            values[key] = value == "true"
            list_key = None
        else:
            values[key] = value.strip('"\'')
            list_key = None
    return values, "\n".join(lines[end + 1 :])


def check_date(value: object, label: str, path: Path) -> dt.date | None:
    if not isinstance(value, str):
        errors.append(f"{path}: {label} must be YYYY-MM-DD")
        return None
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        errors.append(f"{path}: {label} must be YYYY-MM-DD")
        return None


root_markdown = sorted(path.name for path in project.glob("*.md"))
if root_markdown != ["README.md"]:
    errors.append(f"root Markdown whitelist violation: {root_markdown}")

canonical_domains: dict[str, Path] = {}
markdown_links = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
for path in sorted(docs.rglob("*.md")):
    if path == docs / "README.md":
        continue
    metadata, body = front_matter(path)
    missing = sorted(required - metadata.keys())
    if missing:
        errors.append(f"{path}: missing front matter keys: {', '.join(missing)}")
        continue

    doc_type = metadata.get("type")
    status = metadata.get("status")
    canonical = metadata.get("canonical")
    domain = metadata.get("domain")
    if doc_type not in allowed_types:
        errors.append(f"{path}: unsupported type {doc_type!r}")
    if status not in allowed_statuses:
        errors.append(f"{path}: unsupported status {status!r}")
    if canonical not in {True, False}:
        errors.append(f"{path}: canonical must be true or false")
    if not isinstance(domain, str) or not domain:
        errors.append(f"{path}: domain must be non-empty")
    check_date(metadata.get("created"), "created", path)
    reviewed = check_date(metadata.get("last_reviewed"), "last_reviewed", path)
    if reviewed:
        age = (today - reviewed).days
        if doc_type == "planning" and status == "active" and age > 14:
            warnings.append(f"{path}: active planning doc is {age} days since review")
        if doc_type == "product" and age > 30:
            warnings.append(f"{path}: product doc is {age} days since review")

    in_archive = "archive" in path.relative_to(docs).parts
    if in_archive:
        if status != "archived":
            errors.append(f"{path}: archive documents must have status archived")
        if "archived_at:" not in path.read_text(encoding="utf-8").split("---", 2)[1]:
            errors.append(f"{path}: archive documents need archived_at")
        if "must not be used as the current implementation plan" not in body.lower():
            errors.append(f"{path}: archive warning is missing")
    else:
        forbidden = re.search(r"V2|V3|FINAL2?|NEW|LATEST|COPY|新版|最终版", path.name, flags=re.IGNORECASE)
        if forbidden:
            errors.append(f"{path}: canonical/current filename contains forbidden legacy marker {forbidden.group(0)!r}")

    if canonical is True and isinstance(domain, str):
        previous = canonical_domains.get(domain)
        if previous:
            errors.append(f"canonical domain conflict: {previous} and {path} both use {domain}")
        else:
            canonical_domains[domain] = path

    for match in markdown_links.finditer(body):
        target = match.group(1).strip().strip("<>").split("#", 1)[0].split("?", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:", "#", "codex:", "plugin:", "file:")) or target.startswith("/"):
            continue
        resolved = (path.parent / unquote(target)).resolve()
        if not resolved.exists():
            errors.append(f"{path}: broken relative link {target!r}")

index = docs / "README.md"
if not index.exists():
    errors.append("docs/README.md is missing")
elif "Generated by Scripts/generate_docs_index.py" not in index.read_text(encoding="utf-8"):
    errors.append("docs/README.md is not marked as generated")

# EN: Check the two navigation entry points as well as the metadata documents.
# ES: Comprueba también los dos puntos de navegación además de los documentos con metadatos.
# 中文：除带元数据文档外，也检查两个导航入口的链接。
for navigation_path in (project / "README.md", index):
    if not navigation_path.exists():
        continue
    navigation_body = navigation_path.read_text(encoding="utf-8")
    for match in markdown_links.finditer(navigation_body):
        target = match.group(1).strip().strip("<>").split("#", 1)[0].split("?", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:", "#", "codex:", "plugin:", "file:")) or target.startswith("/"):
            continue
        resolved = (navigation_path.parent / unquote(target)).resolve()
        if not resolved.exists():
            errors.append(f"{navigation_path}: broken relative link {target!r}")

for warning in warnings:
    print(f"warning: {warning}", file=sys.stderr)
if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)
print(f"docs lint passed: {len(list(docs.rglob('*.md')))} project docs checked")
PY
