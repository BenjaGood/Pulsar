-- Keep ranking/counting rows narrow. Product payloads and community nutrient
-- JSON are assembled only after pagination, which keeps common terms fast.

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
    select normalized.term,
      to_tsquery(
        'simple',
        array_to_string(tsvector_to_array(to_tsvector('simple', normalized.term)), ':* & ') || ':*'
      ) query,
      greatest(p_page, 1) page_number,
      least(greatest(p_page_size, 1), 50) page_size
    from (select public.food_immutable_unaccent(lower(left(btrim(p_query), 120))) term) normalized
  ), active as (
    select id, dataset_version, source_url from public.food_dataset_imports
    where provider = 'open_nutrition' and status = 'active'
  ), candidate_ids as (
    select
      'imported'::text kind,
      r.import_id,
      r.source_product_id,
      null::uuid community_id,
      (case
        when public.food_immutable_unaccent(lower(r.name)) = parameters.term then 50
        when public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%' then 30
        when public.food_immutable_unaccent(lower(coalesce(r.generic_name, ''))) like parameters.term || '%' then 20
        else 0
      end + ts_rank_cd(r.search_document, parameters.query))::real score,
      r.name sort_name,
      r.source_product_id sort_id
    from public.food_dataset_compact_records r cross join parameters cross join active
    where r.import_id = active.id
      and r.search_document @@ parameters.query
      and (r.canonical_barcode is null or not exists (
        select 1 from public.food_products override
        where override.barcode = r.canonical_barcode
          and override.verification_status in ('photo_verified', 'community_verified')
      ))
    union all
    select
      'community'::text, null::uuid, null::text, p.id, 100::real, p.name, p.id::text
    from public.food_products p cross join parameters
    where p.verification_status in ('photo_verified', 'community_verified')
      and to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ', p.name, p.generic_name, p.brand))))
        @@ parameters.query
  ), page_ids as (
    select candidate_ids.*, count(*) over () total
    from candidate_ids
    order by score desc, sort_name, sort_id
    offset (select (page_number - 1) * page_size from parameters)
    limit (select page_size from parameters)
  )
  select
    case when page_ids.kind = 'imported' then public.food_compact_product(
      imported,
      (select dataset_version from active),
      (select source_url from active)
    ) else to_jsonb(community) || jsonb_build_object(
      'nutrients', coalesce((select jsonb_agg(to_jsonb(n) - 'product_id')
        from public.food_product_nutrients n where n.product_id = community.id), '[]'::jsonb)
    ) end,
    page_ids.score,
    page_ids.total
  from page_ids
  left join public.food_dataset_compact_records imported
    on page_ids.kind = 'imported'
   and imported.import_id = page_ids.import_id
   and imported.source_product_id = page_ids.source_product_id
  left join public.food_products community
    on page_ids.kind = 'community' and community.id = page_ids.community_id
  order by page_ids.score desc, page_ids.sort_name, page_ids.sort_id;
$$;

revoke all on function public.search_food_products(text, integer, integer) from public;
grant execute on function public.search_food_products(text, integer, integer) to anon, authenticated;
