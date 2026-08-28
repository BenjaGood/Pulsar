import csv
import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import import_opennutrition as importer


class OpenNutritionImporterTests(unittest.TestCase):
    def row(self, **changes):
        row = {
            "id": "fd_4PhO6yibzOp5",
            "name": "Organic 21 Whole Grains & Seeds Bread by Dave's Killer Bread",
            "alternate_names": '["Dave s Killer Bread Organic 21 Whole Grains and Seeds"]',
            "description": "", "type": "grocery", "source": "[]",
            "serving": '{"common":{"quantity":1,"unit":"cup"},"metric":{"quantity":250,"unit":"mg"}}',
            "nutrition_100g": '{"calories":0,"protein":2,"undefined":99}', "ean_13": "0013764027053",
            "labels": "[]", "package_size": "{}", "ingredients": "milk", "ingredient_analysis": "{}",
        }
        row.update(changes)
        return row

    def archive(self, rows):
        temporary = tempfile.TemporaryDirectory()
        path = Path(temporary.name) / "opennutrition-dataset-test.zip"
        stream = io.StringIO(newline="")
        writer = csv.DictWriter(stream, fieldnames=importer.EXPECTED_HEADERS, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("README.md", "OpenNutrition test")
            archive.writestr("LICENSE-ODbL.txt", "ODbL")
            archive.writestr("LICENSE-DbCL.txt", "DbCL")
            archive.writestr("opennutrition_foods.tsv", stream.getvalue())
        self.addCleanup(temporary.cleanup)
        return path

    def test_checksum_mismatch_is_rejected(self):
        archive = self.archive([self.row()])
        checksum = archive.with_suffix(".sha256")
        checksum.write_text("0" * 64)
        with self.assertRaises(importer.ImportFailure):
            importer.verify_local_archive(archive, checksum)

    def test_streaming_tsv_preserves_unicode_and_quoted_tab(self):
        archive = self.archive([self.row(name="Crème brûlée\tstyle", alternate_names='["Unicode café"]')])
        result = list(importer.rows(archive))
        self.assertEqual(result[0]["name"], "Crème brûlée\tstyle")

    def test_mapping_preserves_zero_nil_and_unsupported_raw_value(self):
        result = importer.transform(self.row(), "test", "https://downloads.opennutrition.app/test.zip")
        nutrients = {item["nutrient_key"]: item for item in result["product"]["nutrients"]}
        self.assertEqual(nutrients["energy_kcal"]["amount"], 0)
        self.assertEqual(nutrients["protein_g"]["amount"], 2)
        self.assertNotIn("fat_g", nutrients)
        self.assertNotIn("undefined", nutrients)
        self.assertEqual(result["product"]["raw_nutrition_100g"]["undefined"], 99)

    def test_serving_milligrams_convert_to_grams_without_mass_volume_guess(self):
        result = importer.transform(self.row(), "test", "https://downloads.opennutrition.app/test.zip")
        self.assertEqual(result["product"]["serving_grams"], 0.25)
        self.assertIsNone(result["product"]["serving_milliliters"])

    def test_cholesterol_micrograms_are_normalized_to_milligrams(self):
        result = importer.transform(
            self.row(nutrition_100g='{"cholesterol":12500}'),
            "test", "https://downloads.opennutrition.app/test.zip",
        )
        nutrient = result["product"]["nutrients"][0]
        self.assertEqual(nutrient["nutrient_key"], "cholesterol_mg")
        self.assertEqual(nutrient["amount"], 12.5)
        self.assertEqual(nutrient["unit"], "mg")

    def test_provenance_is_mapped_only_when_the_release_supplies_an_authoritative_source(self):
        authoritative = self.row(source=json.dumps([{
            "id": 331960, "database": "USDA Foundational Foods", "reference": "FDC ID"
        }]))
        known = importer.transform(authoritative, "test", "https://downloads.opennutrition.app/test.zip")
        unknown = importer.transform(self.row(), "test", "https://downloads.opennutrition.app/test.zip")
        self.assertEqual(known["provenance_class"], "authoritative_database")
        self.assertEqual(unknown["provenance_class"], "unknown_provenance")
        self.assertIsNone(known["is_ai_estimated"])
        self.assertIsNone(known["source_confidence"])

    def test_ean13_normalizes_to_gtin14_and_invalid_is_preserved_only_as_original(self):
        good = importer.transform(self.row(), "test", "https://downloads.opennutrition.app/test.zip")
        bad = importer.transform(self.row(ean_13="0013764027052"), "test", "https://downloads.opennutrition.app/test.zip")
        self.assertEqual(good["canonical_barcode"], "00013764027053")
        self.assertIsNone(bad["canonical_barcode"])
        self.assertEqual(bad["original_barcode"], "0013764027052")

    def test_known_lala_release_barcode_normalizes_without_losing_zeroes(self):
        lala = self.row(
            id="fd_cQ05pEiqbMP7", name="Vitamin D Whole Milk by Lala",
            alternate_names='["Vitamin D Whole Milk by Lala"]', ean_13="0815473015037",
            serving='{"common":{"quantity":1,"unit":"cup"},"metric":{"quantity":240,"unit":"ml"}}',
        )
        product = importer.transform(lala, "2025.1", "https://downloads.opennutrition.app/opennutrition-dataset-2025.1.zip")
        self.assertEqual(product["canonical_barcode"], "00815473015037")
        self.assertEqual(product["product"]["name"], "Vitamin D Whole Milk by Lala")
        self.assertTrue(product["product"]["serving_is_estimated"])

    def test_compact_record_retains_runtime_fields_without_raw_dataset_duplication(self):
        transformed = importer.transform(self.row(), "test", "https://downloads.opennutrition.app/test.zip")
        compact = importer.compact_record(transformed)
        self.assertEqual(compact["product_id"], transformed["product"]["id"])
        self.assertEqual(compact["nutrients"]["energy_kcal"], 0)
        self.assertEqual(compact["nutrients"]["protein_g"], 2)
        self.assertNotIn("raw_record", compact)
        self.assertNotIn("raw_nutrition_100g", compact)
        self.assertRegex(compact["record_hash"], r"^[0-9a-f]{64}$")

    def test_new_secret_key_is_not_misused_as_a_bearer_jwt(self):
        client = importer.SupabaseImporter(
            "https://project.supabase.co", "sb_secret_server-only-test-key"
        )
        self.assertNotIn("authorization", client.headers)
        self.assertEqual(client.headers["apikey"], "sb_secret_server-only-test-key")

    def test_legacy_service_role_jwt_keeps_bearer_header(self):
        key = "eyJheader.payload.signature"
        client = importer.SupabaseImporter("https://project.supabase.co", key)
        self.assertEqual(client.headers["authorization"], f"Bearer {key}")

    def test_duplicate_ids_fail_analysis(self):
        archive = self.archive([self.row(), self.row()])
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        with self.assertRaisesRegex(importer.ImportFailure, "duplicate source id"):
            importer.analyze(archive, "https://downloads.opennutrition.app/test.zip", digest)

    def test_missing_required_name_fails(self):
        with self.assertRaises(importer.ImportFailure):
            importer.transform(self.row(name=""), "test", "https://downloads.opennutrition.app/test.zip")


if __name__ == "__main__":
    unittest.main()
