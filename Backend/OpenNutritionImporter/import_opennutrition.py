#!/usr/bin/env python3
"""Verify, inspect, and stream an official OpenNutrition release into Supabase."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import sqlite3
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterator

DOWNLOAD_PAGE = "https://www.opennutrition.app/download"
EXPECTED_HEADERS = (
    "id", "name", "alternate_names", "description", "type", "source", "serving",
    "nutrition_100g", "ean_13", "labels", "package_size", "ingredients", "ingredient_analysis",
)
EXPECTED_PACKAGE_FILES = {"README.md", "LICENSE-ODbL.txt", "LICENSE-DbCL.txt", "opennutrition_foods.tsv"}
SUPPORTED_TYPES = {"everyday", "grocery", "prepared", "restaurant"}
AUTHORITATIVE_DATABASES = {
    "USDA Standard Reference, Legacy", "Canadian Nutrient File", "Frida",
    "Australian Nutrient Database", "USDA Foundational Foods",
}
PULSAR_FOOD_NAMESPACE = uuid.UUID("924714ef-1d40-4cc0-8f21-43ebd60df254")
NUTRIENT_MAP = {
    "calories": ("energy_kcal", "kcal"),
    "protein": ("protein_g", "g"),
    "carbohydrates": ("carbohydrates_g", "g"),
    "total_fat": ("fat_g", "g"),
    "saturated_fats": ("saturated_fat_g", "g"),
    "trans_fats": ("trans_fat_g", "g"),
    "dietary_fiber": ("fiber_g", "g"),
    "total_sugars": ("sugars_g", "g"),
    "added_sugars": ("added_sugars_g", "g"),
    "sodium": ("sodium_mg", "mg"),
    "cholesterol": ("cholesterol_mg", "mg"),
    "calcium": ("calcium_mg", "mg"),
    "iron": ("iron_mg", "mg"),
    "potassium": ("potassium_mg", "mg"),
    "vitamin_d": ("vitamin_d_mcg", "mcg"),
}


class ImportFailure(RuntimeError):
    pass


class DownloadLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


@dataclass
class ReleaseReport:
    dataset_version: str
    source_url: str
    archive_sha256: str
    archive_bytes: int
    tsv_uncompressed_bytes: int
    record_count: int
    unique_id_count: int
    type_counts: dict[str, int]
    barcode_record_count: int
    unique_barcode_count: int
    duplicate_barcode_count: int
    invalid_barcode_count: int
    source_reference_record_count: int
    source_reference_count: int
    open_food_facts_reference_count: int


def request(url: str, *, data: bytes | None = None, headers: dict[str, str] | None = None) -> bytes:
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:1000]
        raise ImportFailure(f"HTTP {error.code} for {url}: {detail}") from error


def discover_release(download_page: str = DOWNLOAD_PAGE) -> tuple[str, str]:
    parser = DownloadLinkParser()
    parser.feed(request(download_page).decode("utf-8"))
    absolute = [urllib.parse.urljoin(download_page, link) for link in parser.links]
    archives = [link for link in absolute if re.search(r"opennutrition-dataset-[^/]+\.zip$", link)]
    checksums = [link for link in absolute if link.endswith(".zip.sha256")]
    if len(archives) != 1 or len(checksums) != 1:
        raise ImportFailure("official download page must expose one release ZIP and one SHA-256 file")
    if checksums[0] != archives[0] + ".sha256":
        raise ImportFailure("release ZIP and checksum links do not match")
    if urllib.parse.urlparse(archives[0]).hostname != "downloads.opennutrition.app":
        raise ImportFailure("release archive is not hosted by downloads.opennutrition.app")
    return archives[0], checksums[0]


def download_release(archive_url: str, checksum_url: str, destination: Path) -> tuple[Path, str]:
    destination.mkdir(parents=True, exist_ok=True)
    archive_path = destination / Path(urllib.parse.urlparse(archive_url).path).name
    checksum_text = request(checksum_url).decode("ascii", errors="strict")
    expected = checksum_text.strip().split()[0].lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ImportFailure("official checksum file does not contain a SHA-256 digest")
    digest = hashlib.sha256()
    req = urllib.request.Request(archive_url)
    with urllib.request.urlopen(req, timeout=120) as response, archive_path.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != expected:
        archive_path.unlink(missing_ok=True)
        raise ImportFailure("archive SHA-256 does not match the official checksum")
    return archive_path, expected


def verify_local_archive(archive_path: Path, checksum_path: Path) -> str:
    expected = checksum_path.read_text(encoding="ascii").strip().split()[0].lower()
    digest = hashlib.sha256()
    with archive_path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    if not re.fullmatch(r"[0-9a-f]{64}", expected) or digest.hexdigest() != expected:
        raise ImportFailure("local archive SHA-256 verification failed")
    return expected


def validated_zip(archive_path: Path) -> zipfile.ZipFile:
    archive = zipfile.ZipFile(archive_path)
    names: set[str] = set()
    for info in archive.infolist():
        path = Path(info.filename)
        if path.is_absolute() or ".." in path.parts or len(path.parts) != 1:
            archive.close()
            raise ImportFailure(f"unsafe or unexpected archive path: {info.filename}")
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            archive.close()
            raise ImportFailure(f"symlink is not permitted in release archive: {info.filename}")
        names.add(info.filename)
    if names != EXPECTED_PACKAGE_FILES:
        archive.close()
        raise ImportFailure(f"unexpected package contents: {sorted(names)}")
    for required in ("README.md", "LICENSE-ODbL.txt", "LICENSE-DbCL.txt"):
        if not archive.read(required).strip():
            archive.close()
            raise ImportFailure(f"required package document is empty: {required}")
    return archive


def dataset_version(archive_path: Path) -> str:
    match = re.fullmatch(r"opennutrition-dataset-(.+)\.zip", archive_path.name)
    if not match:
        raise ImportFailure("archive filename does not identify an OpenNutrition dataset version")
    return match.group(1)


def rows(archive_path: Path) -> Iterator[dict[str, str]]:
    with validated_zip(archive_path) as archive, archive.open("opennutrition_foods.tsv") as raw:
        with io.TextIOWrapper(raw, encoding="utf-8", newline="") as text_stream:
            reader = csv.DictReader(text_stream, delimiter="\t")
            if tuple(reader.fieldnames or ()) != EXPECTED_HEADERS:
                raise ImportFailure(f"unexpected TSV headers: {reader.fieldnames}")
            for line_number, row in enumerate(reader, start=2):
                if None in row:
                    raise ImportFailure(f"TSV row {line_number} has more fields than its header")
                yield row


def parse_json(row: dict[str, str], key: str, expected_type: type, line_hint: str) -> Any:
    raw = row[key]
    if raw == "" and expected_type is str:
        return ""
    try:
        value = json.loads(raw or ("[]" if expected_type is list else "{}"))
    except json.JSONDecodeError as error:
        raise ImportFailure(f"invalid {key} JSON for {line_hint}: {error}") from error
    if not isinstance(value, expected_type):
        raise ImportFailure(f"{key} has the wrong JSON shape for {line_hint}")
    return value


def valid_ean13(value: str) -> bool:
    if not re.fullmatch(r"\d{13}", value):
        return False
    digits = [int(character) for character in value]
    return (sum(digits[:-1][::2]) + 3 * sum(digits[:-1][1::2]) + digits[-1]) % 10 == 0


def canonical_barcode(value: str) -> str | None:
    return "0" + value if valid_ean13(value) else None


def normalized_serving(raw: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {"raw": raw}
    common = raw.get("common")
    metric = raw.get("metric")
    if isinstance(common, dict):
        result["common"] = common
    if isinstance(metric, dict) and isinstance(metric.get("quantity"), (int, float)):
        quantity = float(metric["quantity"])
        unit = str(metric.get("unit", ""))
        if unit in {"g", "grm"}:
            result["grams"] = quantity
        elif unit == "mg":
            result["grams"] = quantity / 1000
        elif unit == "ml":
            result["milliliters"] = quantity
    return result


def transform(row: dict[str, str], version: str, source_url: str) -> dict[str, Any]:
    source_id = row["id"].strip()
    name = row["name"].strip()
    food_type = row["type"].strip()
    if not source_id or not name or food_type not in SUPPORTED_TYPES:
        raise ImportFailure(f"invalid required fields for source id {source_id or '<missing>'}")
    alternate_names = parse_json(row, "alternate_names", list, source_id)
    if not all(isinstance(value, str) for value in alternate_names):
        raise ImportFailure(f"alternate_names contains a non-string value for {source_id}")
    sources = parse_json(row, "source", list, source_id)
    serving_raw = parse_json(row, "serving", dict, source_id)
    nutrition_raw = parse_json(row, "nutrition_100g", dict, source_id)
    labels = parse_json(row, "labels", list, source_id)
    package_size = parse_json(row, "package_size", dict, source_id)
    ingredient_analysis = parse_json(row, "ingredient_analysis", dict, source_id)
    package_metric = package_size.get("metric") if isinstance(package_size.get("metric"), dict) else {}
    allergens = sorted(
        key.removeprefix("allergen_").replace("_", " ")
        for key, value in ingredient_analysis.items()
        if key.startswith("allergen_") and value
    )
    nutrients = []
    for source_key, (key, unit) in NUTRIENT_MAP.items():
        value = nutrition_raw.get(source_key)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if source_key == "cholesterol":
                value /= 1000.0  # OpenNutrition 2025.1 stores cholesterol as micrograms.
            nutrients.append({"nutrient_key": key, "amount": value, "unit": unit, "basis": "per_100g"})
    barcode = row["ean_13"].strip() or None
    canonical = canonical_barcode(barcode) if barcode else None
    serving = normalized_serving(serving_raw)
    common = serving.get("common", {})
    product = {
        "id": str(uuid.uuid5(PULSAR_FOOD_NAMESPACE, f"open_nutrition:{source_id}")),
        "barcode": canonical,
        "original_barcode": barcode,
        "name": name,
        "generic_name": row["description"].strip() or None,
        "brand": None,
        "food_type": food_type,
        "alternate_names": alternate_names,
        "serving_quantity": common.get("quantity") if isinstance(common, dict) else None,
        "serving_unit": common.get("unit") if isinstance(common, dict) else None,
        "serving_grams": serving.get("grams"),
        "serving_milliliters": serving.get("milliliters"),
        # Release 2025.1 nutrition values are mass-based (per 100 g). A volume-only
        # serving cannot be scaled without a density supplied by the dataset, so
        # the client must use an explicit 100 g reference serving instead.
        "serving_is_estimated": not bool(serving.get("grams")),
        "package_size": package_size,
        "package_quantity": package_metric.get("quantity"),
        "package_unit": package_metric.get("unit"),
        "ingredients": row["ingredients"].strip() or None,
        "allergens": allergens,
        "ingredient_analysis": ingredient_analysis,
        "labels": labels,
        "source": "open_nutrition",
        "source_product_id": source_id,
        "source_dataset_version": version,
        "source_updated_at": None,
        "source_url": source_url,
        "source_references": sources,
        "source_provenance": sources,
        "provenance_class": "authoritative_database" if any(
            isinstance(item, dict) and item.get("database") in AUTHORITATIVE_DATABASES for item in sources
        ) else "unknown_provenance",
        "source_confidence": None,
        "is_ai_estimated": None,
        "verification_status": "imported",
        "nutrients": nutrients,
        "raw_nutrition_100g": nutrition_raw,
    }
    return {
        "source_product_id": source_id,
        "canonical_barcode": canonical,
        "original_barcode": barcode,
        "name": name,
        "alternate_names": alternate_names,
        "food_type": food_type,
        "source_references": sources,
        "provenance_class": product["provenance_class"],
        "source_confidence": None,
        "is_ai_estimated": None,
        "product": product,
        "raw_record": row,
    }


def compact_record(record: dict[str, Any]) -> dict[str, Any]:
    """Return the lossless app-facing subset stored by the compact Supabase schema.

    The official archive remains the immutable source artifact. Storing its raw TSV
    JSON beside every normalized product more than triples database usage, so the
    runtime database retains identifiers, provenance, searchable fields, serving
    data, and every nutrient supported by Pulsar without duplicating the archive.
    """
    product = record["product"]
    nutrients = {
        nutrient["nutrient_key"]: nutrient["amount"]
        for nutrient in product["nutrients"]
    }
    compact = {
        "product_id": product["id"],
        "source_product_id": record["source_product_id"],
        "canonical_barcode": record["canonical_barcode"],
        "original_barcode": record["original_barcode"],
        "name": record["name"],
        "generic_name": product["generic_name"],
        "alternate_names": record["alternate_names"],
        "food_type": record["food_type"],
        "source_references": record["source_references"],
        "provenance_class": record["provenance_class"],
        "serving_quantity": product["serving_quantity"],
        "serving_unit": product["serving_unit"],
        "serving_grams": product["serving_grams"],
        "serving_milliliters": product["serving_milliliters"],
        "serving_is_estimated": product["serving_is_estimated"],
        "package_quantity": product["package_quantity"],
        "package_unit": product["package_unit"],
        "ingredients": product["ingredients"],
        "allergens": product["allergens"],
        "nutrients": nutrients,
    }
    compact = {key: value for key, value in compact.items() if value is not None}
    compact["record_hash"] = hashlib.sha256(
        json.dumps(compact, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return compact


def analyze(archive_path: Path, source_url: str, digest: str) -> ReleaseReport:
    types: Counter[str] = Counter()
    barcode_records = invalid_barcodes = source_records = source_count = off_sources = records = 0
    with tempfile.NamedTemporaryFile(suffix=".sqlite3") as temp:
        database = sqlite3.connect(temp.name)
        database.execute("create table ids (value text primary key)")
        database.execute("create table barcodes (value text)")
        for row in rows(archive_path):
            records += 1
            source_id = row["id"].strip()
            name = row["name"].strip()
            if not source_id or not name:
                raise ImportFailure(f"record {records} is missing id or name")
            try:
                database.execute("insert into ids values (?)", (source_id,))
            except sqlite3.IntegrityError as error:
                raise ImportFailure(f"duplicate source id: {source_id}") from error
            types[row["type"]] += 1
            barcode = row["ean_13"].strip()
            if barcode:
                barcode_records += 1
                database.execute("insert into barcodes values (?)", (barcode,))
                invalid_barcodes += int(not valid_ean13(barcode))
            sources = parse_json(row, "source", list, source_id)
            if sources:
                source_records += 1
                source_count += len(sources)
                off_sources += sum(
                    1 for item in sources if isinstance(item, dict)
                    and "open food facts" in json.dumps(item).lower()
                )
            # Validate every JSON field and every supported transformation during analysis.
            transform(row, dataset_version(archive_path), source_url)
        database.commit()
        unique_barcodes = database.execute("select count(distinct value) from barcodes").fetchone()[0]
        duplicate_barcodes = database.execute(
            "select count(*) from (select value from barcodes group by value having count(*) > 1)"
        ).fetchone()[0]
        unique_ids = database.execute("select count(*) from ids").fetchone()[0]
    with validated_zip(archive_path) as archive:
        tsv_bytes = archive.getinfo("opennutrition_foods.tsv").file_size
    return ReleaseReport(
        dataset_version=dataset_version(archive_path), source_url=source_url,
        archive_sha256=digest, archive_bytes=archive_path.stat().st_size,
        tsv_uncompressed_bytes=tsv_bytes, record_count=records, unique_id_count=unique_ids,
        type_counts=dict(sorted(types.items())), barcode_record_count=barcode_records,
        unique_barcode_count=unique_barcodes, duplicate_barcode_count=duplicate_barcodes,
        invalid_barcode_count=invalid_barcodes, source_reference_record_count=source_records,
        source_reference_count=source_count, open_food_facts_reference_count=off_sources,
    )


class SupabaseImporter:
    def __init__(self, url: str, service_role_key: str) -> None:
        self.base = url.rstrip("/")
        self.headers = {
            "apikey": service_role_key,
            "content-type": "application/json",
        }
        if service_role_key.startswith("eyJ") and service_role_key.count(".") == 2:
            self.headers["authorization"] = f"Bearer {service_role_key}"

    def rpc(self, name: str, payload: dict[str, Any]) -> Any:
        raw = request(
            f"{self.base}/rest/v1/rpc/{name}",
            data=json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            headers=self.headers,
        )
        return json.loads(raw) if raw else None

    def import_release(self, archive_path: Path, report: ReleaseReport, batch_size: int, allow_deletions: bool) -> Any:
        import_id = self.rpc("begin_open_nutrition_import", {
            "p_dataset_version": report.dataset_version,
            "p_source_url": report.source_url,
            "p_archive_sha256": report.archive_sha256,
            "p_expected_record_count": report.record_count,
            "p_metadata": {
                "headers": list(EXPECTED_HEADERS),
                "archive_bytes": report.archive_bytes,
                "tsv_uncompressed_bytes": report.tsv_uncompressed_bytes,
                "type_counts": report.type_counts,
                "barcode_record_count": report.barcode_record_count,
                "unique_barcode_count": report.unique_barcode_count,
                "duplicate_barcode_count": report.duplicate_barcode_count,
                "invalid_barcode_count": report.invalid_barcode_count,
            },
        })
        try:
            resume_from = int(self.rpc(
                "open_nutrition_import_resume_count", {"p_import_id": import_id}
            ))
            if not 0 <= resume_from <= report.record_count:
                raise ImportFailure(f"invalid server resume offset: {resume_from}")
            batch: list[dict[str, Any]] = []
            for record_number, row in enumerate(rows(archive_path), start=1):
                if record_number <= resume_from:
                    continue
                batch.append(compact_record(transform(row, report.dataset_version, report.source_url)))
                if len(batch) >= batch_size:
                    self.rpc("stage_open_nutrition_batch", {"p_import_id": import_id, "p_records": batch})
                    batch.clear()
            if batch:
                self.rpc("stage_open_nutrition_batch", {"p_import_id": import_id, "p_records": batch})
            return self.rpc("finalize_open_nutrition_import", {
                "p_import_id": import_id,
                "p_allow_significant_deletions": allow_deletions,
            })
        except Exception as error:
            # Supabase's API statement timeout is transient. Every batch is
            # transactional, so retain committed rows and resume on the next run.
            if "57014" in str(error) or "statement timeout" in str(error).lower():
                raise
            try:
                self.rpc("fail_open_nutrition_import", {"p_import_id": import_id})
            except Exception:
                pass
            raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Already-downloaded official ZIP")
    parser.add_argument("--checksum", type=Path, help="Official .sha256 for --archive")
    parser.add_argument("--download-page", default=DOWNLOAD_PAGE)
    parser.add_argument("--analyze-only", action="store_true")
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--allow-significant-deletions", action="store_true")
    parser.add_argument("--report", type=Path, help="Write the inspection report as JSON")
    args = parser.parse_args(argv)
    if not 1 <= args.batch_size <= 1000:
        parser.error("--batch-size must be between 1 and 1000")

    if args.archive:
        if not args.checksum:
            parser.error("--checksum is required with --archive")
        archive_path = args.archive
        digest = verify_local_archive(archive_path, args.checksum)
        dataset_version(archive_path)
        source_url = f"https://downloads.opennutrition.app/{archive_path.name}"
    else:
        archive_url, checksum_url = discover_release(args.download_page)
        temporary = tempfile.TemporaryDirectory(prefix="opennutrition-")
        archive_path, digest = download_release(archive_url, checksum_url, Path(temporary.name))
        source_url = archive_url

    report = analyze(archive_path, source_url, digest)
    report_json = json.dumps(asdict(report), indent=2, ensure_ascii=False, sort_keys=True)
    print(report_json)
    if args.report:
        args.report.write_text(report_json + "\n", encoding="utf-8")
    if args.analyze_only:
        return 0

    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = (
        os.environ.get("SUPABASE_SECRET_KEY", "").strip()
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    )
    if not supabase_url or not service_key:
        raise ImportFailure(
            "SUPABASE_URL and SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY) are required for import"
        )
    result = SupabaseImporter(supabase_url, service_key).import_release(
        archive_path, report, args.batch_size, args.allow_significant_deletions
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ImportFailure as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
