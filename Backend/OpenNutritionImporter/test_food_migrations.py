import unittest
from pathlib import Path


class FoodMigrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        migrations = Path(__file__).resolve().parents[2] / "supabase" / "migrations"
        cls.community = (migrations / "202608120001_food_community_database.sql").read_text()
        cls.dataset = (migrations / "202608120003_open_nutrition_dataset.sql").read_text()
        cls.operational = (migrations / "202608120004_operational_food_lookup.sql").read_text()
        cls.compact = (migrations / "202608130001_compact_open_nutrition_runtime.sql").read_text()
        cls.resumable = (migrations / "202608130002_resumable_open_nutrition_import.sql").read_text()
        cls.finalize_timeout = (migrations / "202608130003_open_nutrition_finalize_timeout.sql").read_text()
        cls.fast_search = (migrations / "202608130004_fast_food_search_and_units.sql").read_text()
        cls.gin_prefix = (migrations / "202608130005_gin_prefix_food_search.sql").read_text()
        cls.narrow_search = (migrations / "202608130006_narrow_ranked_food_search.sql").read_text()
        cls.bounded_search = (migrations / "202608130007_bounded_food_search.sql").read_text()

    def test_community_writes_remain_protected(self):
        self.assertIn(
            "revoke insert, update, delete on public.food_products from anon, authenticated",
            self.community,
        )
        self.assertIn("contributors upload evidence to own pending proposal", self.community)

    def test_import_is_service_role_only_atomic_and_conflict_safe(self):
        for contract in (
            "service role required",
            "significant deletion guard",
            "rollback_open_nutrition_import",
            "food_dataset_barcode_conflicts",
            "drop function if exists public.cache_open_food_facts_product",
            "return query select 'conflict'::text",
            "override.barcode = r.canonical_barcode",
        ):
            self.assertIn(contract, self.dataset)

    def test_public_read_rpcs_expose_readiness_and_indexed_search(self):
        for contract in (
            "create or replace function public.food_database_status",
            "create extension if not exists unaccent",
            "food_dataset_records_normalized_search_trgm_idx",
            "grant execute on function public.food_database_status() to anon, authenticated",
            "return query select 'dataset_not_imported'::text",
        ):
            self.assertIn(contract, self.operational)

    def test_compact_runtime_avoids_raw_dataset_duplication(self):
        for contract in (
            "food_dataset_compact_records",
            "storage_profile', 'compact_v1",
            "record_hash",
            "food_dataset_compact_search_idx",
            "food_dataset_compact_barcode_idx",
            "food_compact_product",
            "return query select 'dataset_not_imported'::text",
        ):
            self.assertIn(contract, self.compact)
        self.assertNotIn("raw_record jsonb", self.compact)
        self.assertNotIn("product jsonb not null", self.compact)

    def test_interrupted_import_can_resume_from_committed_batch_boundary(self):
        self.assertIn("open_nutrition_import_resume_count", self.resumable)
        self.assertIn("status in ('loading', 'active')", self.resumable)
        self.assertIn("require_food_importer", self.resumable)
        self.assertIn("set statement_timeout = '0'", self.finalize_timeout)

    def test_search_uses_indexed_match_branches_before_product_serialization(self):
        self.assertIn("matching_imported_ids as materialized", self.fast_search)
        self.assertIn("food_dataset_compact_search_idx", self.compact)
        self.assertIn("food_dataset_compact_name_prefix_idx", self.compact)
        self.assertIn("from page", self.fast_search)
        self.assertIn("tsvector_to_array", self.gin_prefix)
        self.assertIn(":* & ", self.gin_prefix)
        self.assertNotIn("matching_imported_ids", self.gin_prefix)
        self.assertIn("candidate_ids as", self.narrow_search)
        self.assertIn("page_ids as", self.narrow_search)
        self.assertIn("left join public.food_dataset_compact_records imported", self.narrow_search)
        self.assertIn("imported_match_ids as materialized", self.bounded_search)
        self.assertIn("limit 1000", self.bounded_search)
        self.assertIn("lower(r.name)) =", self.bounded_search)


if __name__ == "__main__":
    unittest.main()
