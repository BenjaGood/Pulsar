-- Compact OpenNutrition runtime storage for bounded Supabase projects.
-- The verified release archive remains the immutable raw source. The database
-- stores the complete product catalog and Pulsar-supported nutrition fields,
-- without duplicating the raw TSV as JSON in staging and active tables.

create table if not exists public.food_dataset_compact_records (
  import_id uuid not null references public.food_dataset_imports(id) on delete cascade,
  product_id uuid not null,
  source_product_id text not null,
  record_hash text not null check (record_hash ~ '^[0-9a-f]{64}$'),
  canonical_barcode text check (canonical_barcode is null or canonical_barcode ~ '^[0-9]{14}$'),
  original_barcode text,
  name text not null check (length(btrim(name)) between 1 and 500),
  generic_name text,
  alternate_names text[] not null default '{}',
  food_type text not null check (food_type in ('everyday', 'grocery', 'prepared', 'restaurant')),
  source_references jsonb not null default '[]'::jsonb check (jsonb_typeof(source_references) = 'array'),
  provenance_class text not null check (provenance_class in ('authoritative_database', 'unknown_provenance')),
  serving_quantity real,
  serving_unit text,
  serving_grams real,
  serving_milliliters real,
  serving_is_estimated boolean not null default true,
  package_quantity real,
  package_unit text,
  ingredients text,
  allergens text[] not null default '{}',
  energy_kcal real,
  protein_g real,
  carbohydrates_g real,
  fat_g real,
  saturated_fat_g real,
  trans_fat_g real,
  fiber_g real,
  sugars_g real,
  added_sugars_g real,
  sodium_mg real,
  salt_g real,
  cholesterol_mg real,
  calcium_mg real,
  iron_mg real,
  potassium_mg real,
  vitamin_d_mcg real,
  search_document tsvector not null,
  primary key (import_id, source_product_id)
);

alter table public.food_dataset_compact_records enable row level security;
revoke all on public.food_dataset_compact_records from public, anon, authenticated;

create index if not exists food_dataset_compact_barcode_idx
  on public.food_dataset_compact_records (import_id, canonical_barcode)
  where canonical_barcode is not null;
create index if not exists food_dataset_compact_search_idx
  on public.food_dataset_compact_records using gin (search_document);
create index if not exists food_dataset_compact_name_prefix_idx
  on public.food_dataset_compact_records (
    import_id,
    public.food_immutable_unaccent(lower(name)) text_pattern_ops
  );

create or replace function public.stage_open_nutrition_batch(p_import_id uuid, p_records jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare item jsonb; written integer := 0;
begin
  perform public.require_food_importer();
  if exists (select 1 from public.food_dataset_imports where id = p_import_id and status = 'active') then
    return jsonb_array_length(p_records);
  end if;
  if not exists (
    select 1 from public.food_dataset_imports
    where id = p_import_id and provider = 'open_nutrition' and status = 'loading'
  ) then raise exception 'import is not loadable'; end if;
  if jsonb_typeof(p_records) <> 'array' or jsonb_array_length(p_records) > 1000 then
    raise exception 'batch must be an array of at most 1000 records';
  end if;

  for item in select value from jsonb_array_elements(p_records)
  loop
    insert into public.food_dataset_compact_records (
      import_id, product_id, source_product_id, record_hash,
      canonical_barcode, original_barcode, name, generic_name, alternate_names,
      food_type, source_references, provenance_class,
      serving_quantity, serving_unit, serving_grams, serving_milliliters,
      serving_is_estimated, package_quantity, package_unit, ingredients, allergens,
      energy_kcal, protein_g, carbohydrates_g, fat_g, saturated_fat_g,
      trans_fat_g, fiber_g, sugars_g, added_sugars_g, sodium_mg, salt_g,
      cholesterol_mg, calcium_mg, iron_mg, potassium_mg, vitamin_d_mcg,
      search_document
    ) values (
      p_import_id, (item->>'product_id')::uuid, item->>'source_product_id', item->>'record_hash',
      nullif(item->>'canonical_barcode', ''), nullif(item->>'original_barcode', ''),
      btrim(item->>'name'), nullif(item->>'generic_name', ''),
      coalesce(array(select jsonb_array_elements_text(item->'alternate_names')), '{}'),
      item->>'food_type', coalesce(item->'source_references', '[]'::jsonb), item->>'provenance_class',
      nullif(item->>'serving_quantity', '')::real, nullif(item->>'serving_unit', ''),
      nullif(item->>'serving_grams', '')::real, nullif(item->>'serving_milliliters', '')::real,
      coalesce((item->>'serving_is_estimated')::boolean, true),
      nullif(item->>'package_quantity', '')::real, nullif(item->>'package_unit', ''),
      nullif(item->>'ingredients', ''),
      coalesce(array(select jsonb_array_elements_text(item->'allergens')), '{}'),
      nullif(item->'nutrients'->>'energy_kcal', '')::real,
      nullif(item->'nutrients'->>'protein_g', '')::real,
      nullif(item->'nutrients'->>'carbohydrates_g', '')::real,
      nullif(item->'nutrients'->>'fat_g', '')::real,
      nullif(item->'nutrients'->>'saturated_fat_g', '')::real,
      nullif(item->'nutrients'->>'trans_fat_g', '')::real,
      nullif(item->'nutrients'->>'fiber_g', '')::real,
      nullif(item->'nutrients'->>'sugars_g', '')::real,
      nullif(item->'nutrients'->>'added_sugars_g', '')::real,
      nullif(item->'nutrients'->>'sodium_mg', '')::real,
      nullif(item->'nutrients'->>'salt_g', '')::real,
      nullif(item->'nutrients'->>'cholesterol_mg', '')::real,
      nullif(item->'nutrients'->>'calcium_mg', '')::real,
      nullif(item->'nutrients'->>'iron_mg', '')::real,
      nullif(item->'nutrients'->>'potassium_mg', '')::real,
      nullif(item->'nutrients'->>'vitamin_d_mcg', '')::real,
      to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ',
        item->>'name', item->>'generic_name',
        array_to_string(coalesce(array(select jsonb_array_elements_text(item->'alternate_names')), '{}'), ' ')
      ))))
    )
    on conflict (import_id, source_product_id) do update set
      product_id = excluded.product_id, record_hash = excluded.record_hash,
      canonical_barcode = excluded.canonical_barcode, original_barcode = excluded.original_barcode,
      name = excluded.name, generic_name = excluded.generic_name,
      alternate_names = excluded.alternate_names, food_type = excluded.food_type,
      source_references = excluded.source_references, provenance_class = excluded.provenance_class,
      serving_quantity = excluded.serving_quantity, serving_unit = excluded.serving_unit,
      serving_grams = excluded.serving_grams, serving_milliliters = excluded.serving_milliliters,
      serving_is_estimated = excluded.serving_is_estimated,
      package_quantity = excluded.package_quantity, package_unit = excluded.package_unit,
      ingredients = excluded.ingredients, allergens = excluded.allergens,
      energy_kcal = excluded.energy_kcal, protein_g = excluded.protein_g,
      carbohydrates_g = excluded.carbohydrates_g, fat_g = excluded.fat_g,
      saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g,
      fiber_g = excluded.fiber_g, sugars_g = excluded.sugars_g,
      added_sugars_g = excluded.added_sugars_g, sodium_mg = excluded.sodium_mg,
      salt_g = excluded.salt_g, cholesterol_mg = excluded.cholesterol_mg,
      calcium_mg = excluded.calcium_mg, iron_mg = excluded.iron_mg,
      potassium_mg = excluded.potassium_mg, vitamin_d_mcg = excluded.vitamin_d_mcg,
      search_document = excluded.search_document;
    written := written + 1;
  end loop;
  return written;
end;
$$;

create or replace function public.finalize_open_nutrition_import(
  p_import_id uuid,
  p_allow_significant_deletions boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_count integer; imported_count integer; previous_id uuid; previous_count integer := 0;
  inserted_total integer := 0; updated_total integer := 0; skipped_total integer := 0;
  deleted_total integer := 0; conflict_total integer := 0; invalid_total integer := 0;
begin
  perform public.require_food_importer();
  if exists (select 1 from public.food_dataset_imports where id = p_import_id and status = 'active') then
    return (select jsonb_build_object(
      'import_id', id, 'records', imported_record_count, 'inserted', inserted_count,
      'updated', updated_count, 'skipped', skipped_count, 'deleted', deleted_count,
      'barcode_conflicts', conflict_barcode_count, 'invalid_barcodes', invalid_barcode_count,
      'idempotent', true
    ) from public.food_dataset_imports where id = p_import_id);
  end if;

  select expected_record_count into expected_count
  from public.food_dataset_imports where id = p_import_id and status = 'loading' for update;
  if expected_count is null then raise exception 'import is not loadable'; end if;
  select count(*) into imported_count from public.food_dataset_compact_records where import_id = p_import_id;
  if imported_count <> expected_count then
    raise exception 'record count mismatch: expected %, imported %', expected_count, imported_count;
  end if;

  select id, imported_record_count into previous_id, previous_count
  from public.food_dataset_imports where provider = 'open_nutrition' and status = 'active' for update;
  if previous_id is null then
    inserted_total := imported_count;
  else
    select count(*) filter (where old.source_product_id is null),
           count(*) filter (where old.source_product_id is not null and old.record_hash <> fresh.record_hash),
           count(*) filter (where old.source_product_id is not null and old.record_hash = fresh.record_hash)
    into inserted_total, updated_total, skipped_total
    from public.food_dataset_compact_records fresh
    left join public.food_dataset_compact_records old
      on old.import_id = previous_id and old.source_product_id = fresh.source_product_id
    where fresh.import_id = p_import_id;
    select count(*) into deleted_total from public.food_dataset_compact_records old
    where old.import_id = previous_id and not exists (
      select 1 from public.food_dataset_compact_records fresh
      where fresh.import_id = p_import_id and fresh.source_product_id = old.source_product_id
    );
    if previous_count > 0 and deleted_total::numeric / previous_count > 0.10
       and not p_allow_significant_deletions then
      raise exception 'significant deletion guard: % of % records', deleted_total, previous_count;
    end if;
  end if;

  delete from public.food_dataset_barcode_conflicts where import_id = p_import_id;
  insert into public.food_dataset_barcode_conflicts (import_id, canonical_barcode, source_product_ids)
  select p_import_id, canonical_barcode, array_agg(source_product_id order by source_product_id)
  from public.food_dataset_compact_records
  where import_id = p_import_id and canonical_barcode is not null
  group by canonical_barcode having count(*) > 1;
  select count(*) into conflict_total from public.food_dataset_barcode_conflicts where import_id = p_import_id;
  select count(*) into invalid_total from public.food_dataset_compact_records
    where import_id = p_import_id and original_barcode is not null and canonical_barcode is null;

  if previous_id is not null then
    update public.food_dataset_imports set status = 'superseded', superseded_at = now()
    where id = previous_id;
  end if;
  update public.food_dataset_imports set
    status = 'active', imported_record_count = imported_count,
    inserted_count = inserted_total, updated_count = updated_total,
    skipped_count = skipped_total, deleted_count = deleted_total,
    conflict_barcode_count = conflict_total, invalid_barcode_count = invalid_total,
    metadata = metadata || jsonb_build_object('storage_profile', 'compact_v1'),
    completed_at = now(), activated_at = now()
  where id = p_import_id;

  return jsonb_build_object(
    'import_id', p_import_id, 'records', imported_count, 'inserted', inserted_total,
    'updated', updated_total, 'skipped', skipped_total, 'deleted', deleted_total,
    'barcode_conflicts', conflict_total, 'invalid_barcodes', invalid_total
  );
end;
$$;

create or replace function public.fail_open_nutrition_import(p_import_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.require_food_importer();
  delete from public.food_dataset_compact_records where import_id = p_import_id;
  delete from public.food_dataset_staging_records where import_id = p_import_id;
  update public.food_dataset_imports set status = 'failed', completed_at = now(), failed_record_count = 1
  where id = p_import_id and status = 'loading';
end;
$$;

create or replace function public.food_compact_product(
  p_record public.food_dataset_compact_records,
  p_dataset_version text,
  p_source_url text
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', p_record.product_id,
    'barcode', p_record.canonical_barcode,
    'original_barcode', p_record.original_barcode,
    'name', p_record.name,
    'generic_name', p_record.generic_name,
    'food_type', p_record.food_type,
    'alternate_names', to_jsonb(p_record.alternate_names),
    'serving_quantity', p_record.serving_quantity,
    'serving_unit', p_record.serving_unit,
    'serving_grams', p_record.serving_grams,
    'serving_milliliters', p_record.serving_milliliters,
    'serving_is_estimated', p_record.serving_is_estimated,
    'package_quantity', p_record.package_quantity,
    'package_unit', p_record.package_unit,
    'ingredients', p_record.ingredients,
    'allergens', to_jsonb(p_record.allergens),
    'source', 'open_nutrition',
    'source_product_id', p_record.source_product_id,
    'source_dataset_version', p_dataset_version,
    'source_url', p_source_url,
    'source_references', p_record.source_references,
    'provenance_class', p_record.provenance_class,
    'verification_status', 'imported',
    'nutrients', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'nutrient_key', nutrient_key, 'amount', amount,
        'unit', unit, 'basis', 'per_100g'
      ) order by ordinal), '[]'::jsonb)
      from (values
        (1, 'energy_kcal', p_record.energy_kcal, 'kcal'),
        (2, 'protein_g', p_record.protein_g, 'g'),
        (3, 'carbohydrates_g', p_record.carbohydrates_g, 'g'),
        (4, 'fat_g', p_record.fat_g, 'g'),
        (5, 'saturated_fat_g', p_record.saturated_fat_g, 'g'),
        (6, 'trans_fat_g', p_record.trans_fat_g, 'g'),
        (7, 'fiber_g', p_record.fiber_g, 'g'),
        (8, 'sugars_g', p_record.sugars_g, 'g'),
        (9, 'added_sugars_g', p_record.added_sugars_g, 'g'),
        (10, 'sodium_mg', p_record.sodium_mg, 'mg'),
        (11, 'salt_g', p_record.salt_g, 'g'),
        (12, 'cholesterol_mg', p_record.cholesterol_mg, 'mg'),
        (13, 'calcium_mg', p_record.calcium_mg, 'mg'),
        (14, 'iron_mg', p_record.iron_mg, 'mg'),
        (15, 'potassium_mg', p_record.potassium_mg, 'mg'),
        (16, 'vitamin_d_mcg', p_record.vitamin_d_mcg, 'mcg')
      ) as nutrient(ordinal, nutrient_key, amount, unit)
      where amount is not null
    )
  ));
$$;

revoke all on function public.food_compact_product(public.food_dataset_compact_records, text, text)
  from public, anon, authenticated;

create or replace function public.lookup_food_by_barcode(p_barcode text)
returns table(status text, product jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  active_id uuid; active_version text; active_url text;
  community jsonb; imported jsonb; matching_count integer;
begin
  if p_barcode !~ '^[0-9]{14}$' then raise exception 'invalid barcode'; end if;
  select to_jsonb(p) || jsonb_build_object(
    'nutrients', coalesce((select jsonb_agg(to_jsonb(n) - 'product_id')
      from public.food_product_nutrients n where n.product_id = p.id), '[]'::jsonb)
  ) into community
  from public.food_products p
  where p.barcode = p_barcode and p.verification_status in ('photo_verified', 'community_verified')
  order by p.verified_at desc nulls last limit 1;
  if community is not null then return query select 'found'::text, community; return; end if;

  select dataset_import.id, dataset_import.dataset_version, dataset_import.source_url
  into active_id, active_version, active_url
  from public.food_dataset_imports dataset_import
  where dataset_import.provider = 'open_nutrition' and dataset_import.status = 'active';
  if active_id is null then return query select 'dataset_not_imported'::text, null::jsonb; return; end if;

  select count(*), min(public.food_compact_product(r, active_version, active_url)::text)::jsonb
  into matching_count, imported
  from public.food_dataset_compact_records r
  where r.import_id = active_id and r.canonical_barcode = p_barcode;
  if matching_count > 1 then return query select 'conflict'::text, null::jsonb;
  elsif matching_count = 1 then return query select 'found'::text, imported;
  else return query select 'not_found'::text, null::jsonb;
  end if;
end;
$$;

create or replace function public.search_food_products(
  p_query text,
  p_page integer default 1,
  p_page_size integer default 25
)
returns table(product jsonb, rank real, total_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with parameters as (
    select public.food_immutable_unaccent(lower(left(btrim(p_query), 120))) term,
      websearch_to_tsquery('simple', public.food_immutable_unaccent(lower(left(btrim(p_query), 120)))) query,
      greatest(p_page, 1) page_number,
      least(greatest(p_page_size, 1), 50) page_size
  ), active as (
    select id, dataset_version, source_url from public.food_dataset_imports
    where provider = 'open_nutrition' and status = 'active'
  ), candidates as (
    select public.food_compact_product(r, active.dataset_version, active.source_url) product,
      (case
        when public.food_immutable_unaccent(lower(r.name)) = parameters.term then 50
        when public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%' then 30
        when public.food_immutable_unaccent(lower(coalesce(r.generic_name, ''))) like parameters.term || '%' then 20
        else 0
      end + ts_rank_cd(r.search_document, parameters.query))::real score
    from public.food_dataset_compact_records r cross join parameters cross join active
    where r.import_id = active.id
      and (r.search_document @@ parameters.query
        or public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%'
        or public.food_immutable_unaccent(lower(coalesce(r.generic_name, ''))) like parameters.term || '%')
      and (r.canonical_barcode is null or not exists (
        select 1 from public.food_products override
        where override.barcode = r.canonical_barcode
          and override.verification_status in ('photo_verified', 'community_verified')
      ))
    union all
    select to_jsonb(p) || jsonb_build_object(
      'nutrients', coalesce((select jsonb_agg(to_jsonb(n) - 'product_id')
        from public.food_product_nutrients n where n.product_id = p.id), '[]'::jsonb)
    ), 100::real
    from public.food_products p cross join parameters
    where p.verification_status in ('photo_verified', 'community_verified')
      and to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ', p.name, p.generic_name, p.brand))))
        @@ parameters.query
  ), counted as (
    select candidates.*, count(*) over () total from candidates
  )
  select product, score, total from counted
  order by score desc, product->>'name', product->>'id'
  offset (select (page_number - 1) * page_size from parameters)
  limit (select page_size from parameters);
$$;

revoke all on function public.stage_open_nutrition_batch(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.finalize_open_nutrition_import(uuid, boolean) from public, anon, authenticated;
revoke all on function public.fail_open_nutrition_import(uuid) from public, anon, authenticated;
revoke all on function public.lookup_food_by_barcode(text) from public;
revoke all on function public.search_food_products(text, integer, integer) from public;
grant execute on function public.stage_open_nutrition_batch(uuid, jsonb) to service_role;
grant execute on function public.finalize_open_nutrition_import(uuid, boolean) to service_role;
grant execute on function public.fail_open_nutrition_import(uuid) to service_role;
grant execute on function public.lookup_food_by_barcode(text) to anon, authenticated;
grant execute on function public.search_food_products(text, integer, integer) to anon, authenticated;
