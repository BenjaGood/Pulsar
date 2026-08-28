# OpenNutrition importer

This server-only importer discovers the stable official download links, verifies the published SHA-256, validates the package documents and exact TSV schema, then reads the full TSV as a stream. It never scrapes OpenNutrition search pages and never writes the dataset into the app repository.

Analyze the current official release:

```sh
python3 Backend/OpenNutritionImporter/import_opennutrition.py --analyze-only --report /tmp/opennutrition-report.json
```

Import after applying the Supabase migrations:

```sh
SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
SUPABASE_SECRET_KEY=SERVER_ONLY_SECRET \
python3 Backend/OpenNutritionImporter/import_opennutrition.py
```

If the Supabase CLI is not installed, the equivalent one-off migration command is:

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

The import additionally requires `SUPABASE_URL` and a current `SUPABASE_SECRET_KEY` (or legacy `SUPABASE_SERVICE_ROLE_KEY`) in the backend/CI process. The iOS publishable/anon key cannot stage or promote a dataset.

The service-role key must stay in the backend/CI secret store. Promotion is atomic; failed validation leaves the previous release active. Deleting more than 10% of the previous release blocks promotion unless an operator reruns with `--allow-significant-deletions` after reviewing the JSON report. Completed releases remain available to `rollback_open_nutrition_import`.

The runtime import uses the compact schema from `202608130001_compact_open_nutrition_runtime.sql`.
It stores all release products, searchable identity/serving/provenance fields, and every
nutrient supported by Pulsar, while the checksum-verified ZIP remains the immutable raw
source. The database does not duplicate the complete TSV as per-row JSON.

Run focused importer tests with:

```sh
cd Backend/OpenNutritionImporter && python3 -m unittest -v
```
