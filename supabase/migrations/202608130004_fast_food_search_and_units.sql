-- Keep public search below the Data API timeout by using independent indexed
-- match branches and only building product JSON for the requested page.

set statement_timeout = '0';

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
  ), matching_imported_ids as materialized (
    select r.import_id, r.source_product_id
    from public.food_dataset_compact_records r cross join parameters cross join active
    where r.import_id = active.id and r.search_document @@ parameters.query
    union
    select r.import_id, r.source_product_id
    from public.food_dataset_compact_records r cross join parameters cross join active
    where r.import_id = active.id
      and public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%'
  ), candidates as (
    select
      'imported'::text kind,
      r imported_record,
      null::jsonb community_product,
      (case
        when public.food_immutable_unaccent(lower(r.name)) = parameters.term then 50
        when public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%' then 30
        when public.food_immutable_unaccent(lower(coalesce(r.generic_name, ''))) like parameters.term || '%' then 20
        else 0
      end + ts_rank_cd(r.search_document, parameters.query))::real score
    from matching_imported_ids match
    join public.food_dataset_compact_records r
      on r.import_id = match.import_id and r.source_product_id = match.source_product_id
    cross join parameters
    where r.canonical_barcode is null or not exists (
      select 1 from public.food_products override
      where override.barcode = r.canonical_barcode
        and override.verification_status in ('photo_verified', 'community_verified')
    )
    union all
    select
      'community'::text,
      null::public.food_dataset_compact_records,
      to_jsonb(p) || jsonb_build_object(
        'nutrients', coalesce((select jsonb_agg(to_jsonb(n) - 'product_id')
          from public.food_product_nutrients n where n.product_id = p.id), '[]'::jsonb)
      ),
      100::real
    from public.food_products p cross join parameters
    where p.verification_status in ('photo_verified', 'community_verified')
      and to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ', p.name, p.generic_name, p.brand))))
        @@ parameters.query
  ), counted as (
    select candidates.*, count(*) over () total
    from candidates
  ), page as (
    select * from counted
    order by score desc,
      coalesce((imported_record).name, community_product->>'name'),
      coalesce((imported_record).source_product_id, community_product->>'id')
    offset (select (page_number - 1) * page_size from parameters)
    limit (select page_size from parameters)
  )
  select
    case when kind = 'imported' then public.food_compact_product(
      imported_record,
      (select dataset_version from active),
      (select source_url from active)
    ) else community_product end,
    score,
    total
  from page
  order by score desc,
    coalesce((imported_record).name, community_product->>'name'),
    coalesce((imported_record).source_product_id, community_product->>'id');
$$;

revoke all on function public.search_food_products(text, integer, integer) from public;
grant execute on function public.search_food_products(text, integer, integer) to anon, authenticated;

-- OpenNutrition 2025.1 encodes cholesterol in micrograms while Pulsar's
-- canonical field is milligrams (e.g. Lala whole milk: 12,500 µg = 12.5 mg).
update public.food_dataset_compact_records
set cholesterol_mg = cholesterol_mg / 1000.0
where cholesterol_mg is not null;
