-- Versioned OpenNutrition ingestion and the public, read-only food lookup boundary.
-- Only the server importer may write dataset tables. The iOS app calls the two
-- security-definer read RPCs at the bottom of this migration.

create type public.food_dataset_import_status as enum (
  'loading', 'active', 'superseded', 'failed'
);

alter table public.food_product_contributions
  add column if not exists source_provider text,
  add column if not exists source_product_id text,
  add column if not exists source_dataset_version text;
create index if not exists food_contributions_imported_source_idx
  on public.food_product_contributions (source_provider, source_product_id, source_dataset_version)
  where source_product_id is not null;

create table public.food_dataset_imports (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider = 'open_nutrition'),
  dataset_version text not null,
  source_url text not null,
  archive_sha256 text not null check (archive_sha256 ~ '^[0-9a-f]{64}$'),
  expected_record_count integer not null check (expected_record_count > 0),
  imported_record_count integer not null default 0 check (imported_record_count >= 0),
  inserted_count integer not null default 0 check (inserted_count >= 0),
  updated_count integer not null default 0 check (updated_count >= 0),
  skipped_count integer not null default 0 check (skipped_count >= 0),
  deleted_count integer not null default 0 check (deleted_count >= 0),
  conflict_barcode_count integer not null default 0 check (conflict_barcode_count >= 0),
  invalid_barcode_count integer not null default 0 check (invalid_barcode_count >= 0),
  failed_record_count integer not null default 0 check (failed_record_count >= 0),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  status public.food_dataset_import_status not null default 'loading',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  activated_at timestamptz,
  superseded_at timestamptz,
  unique (provider, dataset_version, archive_sha256)
);

create unique index food_dataset_one_active_provider_idx
  on public.food_dataset_imports (provider) where status = 'active';

create table public.food_dataset_staging_records (
  import_id uuid not null references public.food_dataset_imports(id) on delete cascade,
  source_product_id text not null,
  canonical_barcode text check (canonical_barcode is null or canonical_barcode ~ '^[0-9]{14}$'),
  original_barcode text,
  name text not null check (length(btrim(name)) between 1 and 500),
  alternate_names text[] not null default '{}',
  food_type text not null check (food_type in ('everyday', 'grocery', 'prepared', 'restaurant')),
  source_references jsonb not null default '[]'::jsonb check (jsonb_typeof(source_references) = 'array'),
  provenance_class text not null check (provenance_class in ('authoritative_database', 'unknown_provenance')),
  source_confidence numeric check (source_confidence is null or source_confidence between 0 and 1),
  is_ai_estimated boolean,
  product jsonb not null check (jsonb_typeof(product) = 'object'),
  raw_record jsonb not null check (jsonb_typeof(raw_record) = 'object'),
  primary key (import_id, source_product_id)
);

create table public.food_dataset_records (
  import_id uuid not null references public.food_dataset_imports(id) on delete cascade,
  provider text not null check (provider = 'open_nutrition'),
  source_product_id text not null,
  canonical_barcode text check (canonical_barcode is null or canonical_barcode ~ '^[0-9]{14}$'),
  original_barcode text,
  name text not null,
  alternate_names text[] not null default '{}',
  food_type text not null,
  source_references jsonb not null default '[]'::jsonb,
  provenance_class text not null,
  source_confidence numeric,
  is_ai_estimated boolean,
  product jsonb not null,
  raw_record jsonb not null,
  search_document tsvector not null,
  primary key (import_id, source_product_id)
);

create index food_dataset_records_barcode_idx
  on public.food_dataset_records (import_id, canonical_barcode)
  where canonical_barcode is not null;
create index food_dataset_records_search_idx
  on public.food_dataset_records using gin (search_document);
create index food_dataset_records_name_prefix_idx
  on public.food_dataset_records (import_id, lower(name) text_pattern_ops);

create table public.food_dataset_barcode_conflicts (
  import_id uuid not null references public.food_dataset_imports(id) on delete cascade,
  canonical_barcode text not null check (canonical_barcode ~ '^[0-9]{14}$'),
  source_product_ids text[] not null check (cardinality(source_product_ids) > 1),
  created_at timestamptz not null default now(),
  primary key (import_id, canonical_barcode)
);

alter table public.food_dataset_imports enable row level security;
alter table public.food_dataset_staging_records enable row level security;
alter table public.food_dataset_records enable row level security;
alter table public.food_dataset_barcode_conflicts enable row level security;

revoke all on public.food_dataset_imports from public, anon, authenticated;
revoke all on public.food_dataset_staging_records from public, anon, authenticated;
revoke all on public.food_dataset_records from public, anon, authenticated;
revoke all on public.food_dataset_barcode_conflicts from public, anon, authenticated;

create or replace function public.require_food_importer()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.require_food_importer() from public, anon, authenticated;

create or replace function public.begin_open_nutrition_import(
  p_dataset_version text,
  p_source_url text,
  p_archive_sha256 text,
  p_expected_record_count integer,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare result_id uuid;
begin
  perform public.require_food_importer();
  if p_dataset_version = '' or p_source_url !~ '^https://' or p_archive_sha256 !~ '^[0-9a-f]{64}$'
     or p_expected_record_count <= 0 or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'invalid import metadata';
  end if;

  insert into public.food_dataset_imports (
    provider, dataset_version, source_url, archive_sha256, expected_record_count, metadata
  ) values (
    'open_nutrition', p_dataset_version, p_source_url, p_archive_sha256, p_expected_record_count, p_metadata
  )
  on conflict (provider, dataset_version, archive_sha256) do update
    set expected_record_count = excluded.expected_record_count,
        metadata = excluded.metadata,
        status = case
          when public.food_dataset_imports.status = 'failed' then 'loading'::public.food_dataset_import_status
          else public.food_dataset_imports.status
        end,
        started_at = case when public.food_dataset_imports.status = 'failed' then now() else public.food_dataset_imports.started_at end,
        completed_at = case when public.food_dataset_imports.status = 'failed' then null else public.food_dataset_imports.completed_at end,
        failed_record_count = case when public.food_dataset_imports.status = 'failed' then 0 else public.food_dataset_imports.failed_record_count end
  returning id into result_id;
  return result_id;
end;
$$;

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
    insert into public.food_dataset_staging_records (
      import_id, source_product_id, canonical_barcode, original_barcode, name,
      alternate_names, food_type, source_references, provenance_class,
      source_confidence, is_ai_estimated, product, raw_record
    ) values (
      p_import_id, item->>'source_product_id', nullif(item->>'canonical_barcode', ''),
      nullif(item->>'original_barcode', ''), btrim(item->>'name'),
      coalesce(array(select jsonb_array_elements_text(item->'alternate_names')), '{}'),
      item->>'food_type', coalesce(item->'source_references', '[]'::jsonb),
      item->>'provenance_class', nullif(item->>'source_confidence', '')::numeric,
      nullif(item->>'is_ai_estimated', '')::boolean, item->'product', item->'raw_record'
    )
    on conflict (import_id, source_product_id) do update set
      canonical_barcode = excluded.canonical_barcode,
      original_barcode = excluded.original_barcode,
      name = excluded.name,
      alternate_names = excluded.alternate_names,
      food_type = excluded.food_type,
      source_references = excluded.source_references,
      provenance_class = excluded.provenance_class,
      source_confidence = excluded.source_confidence,
      is_ai_estimated = excluded.is_ai_estimated,
      product = excluded.product,
      raw_record = excluded.raw_record;
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
  expected_count integer;
  staged_count integer;
  previous_id uuid;
  previous_count integer := 0;
  inserted_total integer := 0;
  updated_total integer := 0;
  skipped_total integer := 0;
  deleted_total integer := 0;
  conflict_total integer := 0;
  invalid_total integer := 0;
begin
  perform public.require_food_importer();
  if exists (select 1 from public.food_dataset_imports where id = p_import_id and status = 'active') then
    return (
      select jsonb_build_object(
        'import_id', id, 'records', imported_record_count, 'inserted', inserted_count,
        'updated', updated_count, 'skipped', skipped_count, 'deleted', deleted_count,
        'barcode_conflicts', conflict_barcode_count, 'invalid_barcodes', invalid_barcode_count,
        'idempotent', true
      ) from public.food_dataset_imports where id = p_import_id
    );
  end if;
  select expected_record_count into expected_count
  from public.food_dataset_imports where id = p_import_id and status = 'loading' for update;
  if expected_count is null then raise exception 'import is not loadable'; end if;

  select count(*) into staged_count from public.food_dataset_staging_records where import_id = p_import_id;
  if staged_count <> expected_count then
    raise exception 'record count mismatch: expected %, staged %', expected_count, staged_count;
  end if;
  if exists (
    select 1 from public.food_dataset_staging_records
    where import_id = p_import_id
      and (not (product ? 'nutrients') or jsonb_typeof(product->'nutrients') <> 'array')
  ) then raise exception 'one or more records have invalid nutrients'; end if;

  select id, imported_record_count into previous_id, previous_count
  from public.food_dataset_imports where provider = 'open_nutrition' and status = 'active' for update;

  if previous_id is null then
    inserted_total := staged_count;
  else
    select count(*) filter (where old.source_product_id is null),
           count(*) filter (where old.source_product_id is not null and old.raw_record is distinct from fresh.raw_record),
           count(*) filter (where old.source_product_id is not null and old.raw_record is not distinct from fresh.raw_record)
    into inserted_total, updated_total, skipped_total
    from public.food_dataset_staging_records fresh
    left join public.food_dataset_records old
      on old.import_id = previous_id and old.source_product_id = fresh.source_product_id
    where fresh.import_id = p_import_id;

    select count(*) into deleted_total
    from public.food_dataset_records old
    where old.import_id = previous_id and not exists (
      select 1 from public.food_dataset_staging_records fresh
      where fresh.import_id = p_import_id and fresh.source_product_id = old.source_product_id
    );
    if previous_count > 0 and deleted_total::numeric / previous_count > 0.10
       and not p_allow_significant_deletions then
      raise exception 'significant deletion guard: % of % records', deleted_total, previous_count;
    end if;
  end if;

  insert into public.food_dataset_records (
    import_id, provider, source_product_id, canonical_barcode, original_barcode,
    name, alternate_names, food_type, source_references, provenance_class,
    source_confidence, is_ai_estimated, product, raw_record, search_document
  )
  select p_import_id, 'open_nutrition', source_product_id, canonical_barcode, original_barcode,
    name, alternate_names, food_type, source_references, provenance_class,
    source_confidence, is_ai_estimated, product, raw_record,
    to_tsvector('simple', name || ' ' || array_to_string(alternate_names, ' ')
      || ' ' || coalesce(product->>'generic_name', '')
      || ' ' || coalesce(product->>'ingredients', ''))
  from public.food_dataset_staging_records where import_id = p_import_id;

  insert into public.food_dataset_barcode_conflicts (import_id, canonical_barcode, source_product_ids)
  select p_import_id, canonical_barcode, array_agg(source_product_id order by source_product_id)
  from public.food_dataset_staging_records
  where import_id = p_import_id and canonical_barcode is not null
  group by canonical_barcode having count(*) > 1;

  select count(*) into conflict_total from public.food_dataset_barcode_conflicts where import_id = p_import_id;
  select count(*) into invalid_total from public.food_dataset_staging_records
    where import_id = p_import_id and original_barcode is not null and canonical_barcode is null;

  if previous_id is not null then
    update public.food_dataset_imports set status = 'superseded', superseded_at = now()
    where id = previous_id;
  end if;
  update public.food_dataset_imports set
    status = 'active', imported_record_count = staged_count,
    inserted_count = inserted_total, updated_count = updated_total,
    skipped_count = skipped_total, deleted_count = deleted_total,
    conflict_barcode_count = conflict_total, invalid_barcode_count = invalid_total,
    completed_at = now(), activated_at = now()
  where id = p_import_id;
  delete from public.food_dataset_staging_records where import_id = p_import_id;

  return jsonb_build_object(
    'import_id', p_import_id, 'records', staged_count, 'inserted', inserted_total,
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
  delete from public.food_dataset_staging_records where import_id = p_import_id;
  update public.food_dataset_imports set status = 'failed', completed_at = now(), failed_record_count = 1
  where id = p_import_id and status = 'loading';
end;
$$;

create or replace function public.rollback_open_nutrition_import(p_target_import_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare current_id uuid;
begin
  perform public.require_food_importer();
  if not exists (
    select 1 from public.food_dataset_imports
    where id = p_target_import_id and provider = 'open_nutrition'
      and status in ('active', 'superseded') and completed_at is not null
  ) then raise exception 'target import is not promotable'; end if;
  select id into current_id from public.food_dataset_imports
    where provider = 'open_nutrition' and status = 'active' for update;
  if current_id is not null and current_id <> p_target_import_id then
    update public.food_dataset_imports set status = 'superseded', superseded_at = now()
    where id = current_id;
  end if;
  update public.food_dataset_imports set status = 'active', activated_at = now(), superseded_at = null
  where id = p_target_import_id;
  return p_target_import_id;
end;
$$;

revoke all on function public.begin_open_nutrition_import(text, text, text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.stage_open_nutrition_batch(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.finalize_open_nutrition_import(uuid, boolean) from public, anon, authenticated;
revoke all on function public.fail_open_nutrition_import(uuid) from public, anon, authenticated;
revoke all on function public.rollback_open_nutrition_import(uuid) from public, anon, authenticated;
grant execute on function public.begin_open_nutrition_import(text, text, text, integer, jsonb) to service_role;
grant execute on function public.stage_open_nutrition_batch(uuid, jsonb) to service_role;
grant execute on function public.finalize_open_nutrition_import(uuid, boolean) to service_role;
grant execute on function public.fail_open_nutrition_import(uuid) to service_role;
grant execute on function public.rollback_open_nutrition_import(uuid) to service_role;

-- The legacy direct Open Food Facts cache is intentionally removed. Dataset
-- imports are now the only third-party data write path.
drop function if exists public.cache_open_food_facts_product(jsonb, jsonb);
drop policy if exists "published products are readable" on public.food_products;
drop policy if exists "published nutrients are readable" on public.food_product_nutrients;
create policy "verified products are readable"
on public.food_products for select to anon, authenticated
using (verification_status in ('photo_verified', 'community_verified'));
create policy "verified product nutrients are readable"
on public.food_product_nutrients for select to anon, authenticated
using (exists (
  select 1 from public.food_products p
  where p.id = product_id and p.verification_status in ('photo_verified', 'community_verified')
));

create or replace function public.lookup_food_by_barcode(p_barcode text)
returns table(status text, product jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare active_id uuid; community jsonb; imported jsonb; matching_count integer;
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

  select dataset_import.id into active_id
  from public.food_dataset_imports dataset_import
  where dataset_import.provider = 'open_nutrition'
    and dataset_import.status = 'active';
  if active_id is null then return query select 'not_found'::text, null::jsonb; return; end if;
  select count(*), min(r.product::text)::jsonb into matching_count, imported
  from public.food_dataset_records r
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
    select websearch_to_tsquery('simple', left(btrim(p_query), 120)) query,
           greatest(p_page, 1) page_number,
           least(greatest(p_page_size, 1), 50) page_size
  ), active as (
    select id from public.food_dataset_imports
    where provider = 'open_nutrition' and status = 'active'
  ), candidates as (
    select r.product,
      (case when lower(r.name) = lower(btrim(p_query)) then 10
            when lower(r.name) like lower(btrim(p_query)) || '%' then 5 else 0 end
       + ts_rank_cd(r.search_document, parameters.query))::real score
    from public.food_dataset_records r cross join parameters
    where r.import_id = (select id from active)
      and (r.search_document @@ parameters.query or lower(r.name) like lower(btrim(p_query)) || '%')
      and (
        r.canonical_barcode is null or not exists (
          select 1 from public.food_products override
          where override.barcode = r.canonical_barcode
            and override.verification_status in ('photo_verified', 'community_verified')
        )
      )
    union all
    select to_jsonb(p) || jsonb_build_object(
        'nutrients', coalesce((select jsonb_agg(to_jsonb(n) - 'product_id')
          from public.food_product_nutrients n where n.product_id = p.id), '[]'::jsonb)
      ),
      (case when lower(p.name) = lower(btrim(p_query)) then 20 else 12 end)::real
    from public.food_products p
    where p.verification_status in ('photo_verified', 'community_verified')
      and to_tsvector('simple', p.name) @@ websearch_to_tsquery('simple', left(btrim(p_query), 120))
  ), counted as (
    select candidates.*, count(*) over () total from candidates
  )
  select product, score, total from counted
  order by score desc, product->>'name', product->>'id'
  offset (select (page_number - 1) * page_size from parameters)
  limit (select page_size from parameters);
$$;

revoke all on function public.lookup_food_by_barcode(text) from public;
revoke all on function public.search_food_products(text, integer, integer) from public;
grant execute on function public.lookup_food_by_barcode(text) to anon, authenticated;
grant execute on function public.search_food_products(text, integer, integer) to anon, authenticated;
