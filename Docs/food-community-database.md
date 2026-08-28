# Pulsar community food database and OpenNutrition

## Runtime behavior

Pulsar uses one server-side database boundary for barcode lookup and food-name search. The iOS app does not call OpenNutrition or Open Food Facts at runtime and does not contain a dataset service credential.

Barcode resolution is deterministic:

1. Normalize UPC-A, EAN-8, EAN-13, or GTIN-14 and validate its check digit.
2. Return an approved `photo_verified` or `community_verified` Pulsar Community record when one exists.
3. Otherwise, return one exact-barcode record from the active OpenNutrition release.
4. If the active release has more than one record for that barcode, return `conflict`. Pulsar does not guess.
5. If no record is found, continue to nutrition-label OCR and then manual entry.

Food-name search combines approved community products with the active OpenNutrition release. `search_food_products` uses a GIN full-text index, boosts exact and prefix name matches, caps pages at 50 rows, and produces a stable ordering. The Add Food screen waits 300 ms, cancels stale requests, starts with eight results, and lets the user load more.

## Verified OpenNutrition 2025.1 release

The release was discovered from the stable official download page, not a search-result page:

- Download page: <https://www.opennutrition.app/download>
- ZIP: <https://downloads.opennutrition.app/opennutrition-dataset-2025.1.zip>
- Official checksum: <https://downloads.opennutrition.app/opennutrition-dataset-2025.1.zip.sha256>
- Verified SHA-256: `30420802bbf0e29852c282e37a58c7e18ebc1b57e109706925ef969f0498ff47`
- ZIP size: 62,927,029 bytes
- TSV size after decompression: 282,413,682 bytes
- Dataset rows / unique IDs: 326,759 / 326,759
- Types: 5,299 `everyday`, 313,442 `grocery`, 3,836 `prepared`, and 4,182 `restaurant`
- Barcode rows: 313,442; unique values: 313,256
- Duplicate barcode values: 186, each represented by two records in this release
- Valid EAN-13 checksums: 305,849; invalid EAN-13 checksums: 7,593
- Records with source references: 3,389; total source-reference objects: 8,614
- Records explicitly identifying Open Food Facts in their source objects: 0
- Barcode values beginning with the GS1 prefix `750`: 0. Because the release has no country or market column, Mexican retail coverage cannot be measured beyond this limited prefix check and should be treated as a significant current gap.

The archive contains exactly `README.md`, `LICENSE-ODbL.txt`, `LICENSE-DbCL.txt`, and `opennutrition_foods.tsv`. The importer reads and checks all four. The TSV headers are:

```text
id, name, alternate_names, description, type, source, serving,
nutrition_100g, ean_13, labels, package_size, ingredients, ingredient_analysis
```

Important schema limits:

- The release has no separate brand, restaurant-name, country, market, confidence, AI-estimation flag, citation-reasoning, or updated-at column. Pulsar leaves those values `nil`; it does not infer or fabricate them.
- `grocery` is the dataset type for all 313,442 barcode records, but the schema does not independently prove that every row is branded.
- Every row contains `nutrition_100g` and a `serving` object. Serving metric units in this release include `g`, `ml`, `mg`, `grm`, and a small number of `IU`/`iu` values. Pulsar converts `grm` to grams and `mg` to grams. Because the nutrient basis is mass-based, volume-only and IU servings use an explicit estimated 100 g reference serving; Pulsar never invents a mass/volume density conversion.
- The release provides no nutrient-unit metadata. The versioned 2025.1 map uses the dataset’s established field convention for calories, grams, milligrams, and vitamin-D micrograms. The entire original `nutrition_100g` object remains in `raw_nutrition_100g`, and unmapped keys such as `undefined` are never converted into Pulsar nutrients. This map must be reviewed for every new release.
- Explicit numeric zero is preserved. A missing nutrient key remains unavailable; it is never stored as zero.
- Source objects are preserved exactly. A record is classified `authoritative_database` only when its source array names one of the authoritative databases recognized for this release; otherwise it is `unknown_provenance`. The largest source groups are USDA Standard Reference, Legacy (3,427 references), Canadian Nutrient File (2,878), Frida (962), Australian Nutrient Database (906), and USDA Foundational Foods (441).

## Import and storage design

`Backend/OpenNutritionImporter/import_opennutrition.py` uses only the Python standard library and operates server-side:

1. Parse the official download page for its single release ZIP and matching `.sha256` anchor.
2. Require `downloads.opennutrition.app`, stream the ZIP to a temporary directory, and verify SHA-256 before opening it.
3. Reject absolute paths, traversal, nested paths, symlinks, missing documents, additional package files, or changed TSV headers.
4. Analyze every TSV row with streaming `csv.DictReader`; disk-backed SQLite detects duplicate IDs and barcodes without retaining the dataset in memory.
5. Validate required fields and every JSON column. Preserve invalid source barcodes but do not create a canonical lookup key for them.
6. Stage batches through a service-role-only RPC, validate the complete expected row count and nutrient arrays, calculate inserted/updated/skipped/deleted/conflict counts, then atomically promote the release.

`food_dataset_imports` stores release URL, version, checksum, expected and imported counts, change counts, conflict/invalid-barcode counts, timestamps, and status. `food_dataset_records` is immutable and keyed by release plus source ID. Older completed releases are retained for rollback. `food_dataset_staging_records` is never readable by app roles and is removed after promotion or a reported failure.

Promotion fails closed. A count mismatch, malformed record, or removal of more than 10% of the active release aborts the transaction and leaves the previous release active. A deliberate large deletion requires `--allow-significant-deletions` after operator review. Re-importing an already-active release is idempotent and returns its existing report.

The repository intentionally does not contain the downloaded dataset, ZIP, licenses copied from the archive, or generated import output.

## Operations

Apply the migrations in order:

```sh
supabase db push
```

Configure the iOS target with the public project URL and anon/publishable key:

```sh
cp Config/FoodCommunity.local.xcconfig.example Config/FoodCommunity.local.xcconfig
# Replace the two placeholders in the ignored local file.
```

`Config/Oura.shared.xcconfig` is the Debug and Release base configuration and optionally includes `FoodCommunity.shared.xcconfig`, which in turn optionally includes the ignored local override. The app validates both values at runtime. Empty or placeholder values produce a Debug-only `FoodDatabase` fault and a typed `notConfigured` error; they are never reported as offline and no secret value is logged.

Analyze the newest official release without importing:

```sh
python3 Backend/OpenNutritionImporter/import_opennutrition.py \
  --analyze-only \
  --report /tmp/opennutrition-report.json
```

Review the report and any upstream README/license/schema changes, then import from a backend or CI runner:

```sh
SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
SUPABASE_SECRET_KEY=SERVER_ONLY_SECRET \
python3 Backend/OpenNutritionImporter/import_opennutrition.py
```

Verify the public read boundary with the same anon key used by the app (do not paste the key into logs):

```sh
curl --fail-with-body \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$SUPABASE_URL/rest/v1/rpc/food_database_status"

curl --fail-with-body \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_query":"Lala","p_page":1,"p_page_size":8}' \
  "$SUPABASE_URL/rest/v1/rpc/search_food_products"

curl --fail-with-body \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_barcode":"00013764027053"}' \
  "$SUPABASE_URL/rest/v1/rpc/lookup_food_by_barcode"
```

The expected status after importing release 2025.1 is `ready`, 326,759 products, and 313,442 source barcode rows. `dataset_not_imported` is an operational failure, not an empty search result.

The importer calls `fail_open_nutrition_import` if staging or promotion fails. To reactivate a retained release, call `rollback_open_nutrition_import` with its import UUID using the service role. Never place the service-role key in an xcconfig, Info.plist, client bundle, log, or user default.

The importer follows stable download-page anchors, so routine updates do not require a release URL in app code. A changed archive layout, schema, license, checksum format, or nutrient convention intentionally stops the update for human review.

Focused importer tests:

```sh
cd Backend/OpenNutritionImporter
python3 -m unittest -v
```

## Community proposals and security

Community edits remain proposals. Authenticated users may create and modify only their own pending contributions. Pending proposals cannot overwrite trusted products. Product approval, source changes, dataset staging, promotion, rollback, and deletion remain server/admin operations. Anonymous and authenticated app roles have no direct read or write grant on import/staging/conflict tables; public access is restricted to `lookup_food_by_barcode` and `search_food_products`.

The iOS contribution flow uses Supabase Auth anonymous sign-in, persisted in the device Keychain and protected by RLS. Before testing submissions in a Supabase project:

1. Open `Authentication` → `Providers` in the project dashboard.
2. Enable the `Anonymous` provider and save the setting.
3. Apply the repository migrations with `supabase db push`; this includes `publish_food_contribution`, which is required by the client after the contribution insert.
4. Retry the submission in the app. A `422 anonymous_provider_disabled` response means step 2 has not been completed for the configured project.

Alternatively, replace anonymous sign-in with the app's authenticated account session. Package photos never leave the device: Vision OCR consumes them locally, and only confirmed structured product data is sent to Supabase. Historical evidence columns and storage policies are retained only for migration compatibility; current clients do not populate or upload them.

Approved product versions are archived before trusted data changes. Package images are transient client-side OCR input and are not retained as evidence.

## Attribution, licenses, and exports

The official package identifies the OpenNutrition database under ODbL 1.0 and database contents under the modified `LICENSE-DbCL.txt` shipped with the release. Attribution must appear in interfaces that list or expose the data. Pulsar therefore displays this exact primary label beside imported search and product results:

> Nutrition data from OpenNutrition

It links to <https://www.opennutrition.app>. The in-app Food Data Sources screen also links to [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) and directs users to the official release for its exact modified DbCL terms.

If a future record explicitly names Open Food Facts in its preserved source objects, Pulsar additionally displays:

> (c) Open Food Facts contributors

It links to <https://world.openfoodfacts.org>. The 2025.1 archive has no record-level Open Food Facts source objects, so Pulsar does not infer that attribution on individual records.

Recommended exact App Store and website notice:

> Pulsar includes nutrition data from OpenNutrition, licensed under the Open Database License (ODbL) 1.0, with database contents under OpenNutrition’s modified Database Contents License. Where an imported record identifies Open Food Facts as an upstream source, (c) Open Food Facts contributors is shown with that record.

An exported or redistributed OpenNutrition-derived database must retain OpenNutrition attribution and ODbL/DbCL notices and satisfy ODbL Share-Alike requirements for a derived database. Pulsar must make the machine-readable shared food database, its OpenNutrition-derived/community-corrected fields, and the applicable transformation/import metadata available under compatible terms when Share-Alike is triggered. Export tooling must separate shared food records from private user information. Food logs, account/profile data, private foods, contribution evidence, contribution ownership, and private storage paths are never part of that shared database export.

This section is an implementation checklist, not legal advice; release owners should have final attribution and Share-Alike behavior reviewed before distribution.
