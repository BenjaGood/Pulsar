-- Operational readiness, accent-insensitive search, and explicit lookup states.
-- This is additive so it can repair an environment where the earlier food
-- migrations were applied before the client error handling was finalized.

create extension if not exists unaccent;
create extension if not exists pg_trgm;

create or replace function public.food_immutable_unaccent(value text)
returns text
language sql
immutable
parallel safe
strict
set search_path = ''
as $$
  select public.unaccent('public.unaccent', value);
$$;

alter table public.food_dataset_records
  add column if not exists normalized_search_text text not null default '';

create or replace function public.set_food_dataset_search_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.normalized_search_text := public.food_immutable_unaccent(lower(concat_ws(' ',
    new.name,
    array_to_string(new.alternate_names, ' '),
    new.product->>'generic_name',
    new.product->>'brand',
    new.product->>'ingredients'
  )));
  new.search_document := to_tsvector('simple', new.normalized_search_text);
  return new;
end;
$$;

drop trigger if exists food_dataset_records_search_fields on public.food_dataset_records;
create trigger food_dataset_records_search_fields
before insert or update of name, alternate_names, product on public.food_dataset_records
for each row execute function public.set_food_dataset_search_fields();

update public.food_dataset_records
set normalized_search_text = public.food_immutable_unaccent(lower(concat_ws(' ',
      name, array_to_string(alternate_names, ' '), product->>'generic_name',
      product->>'brand', product->>'ingredients'
    ))),
    search_document = to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ',
      name, array_to_string(alternate_names, ' '), product->>'generic_name',
      product->>'brand', product->>'ingredients'
    ))));

create index if not exists food_dataset_records_normalized_search_trgm_idx
  on public.food_dataset_records using gin (normalized_search_text gin_trgm_ops);
create index if not exists food_dataset_records_normalized_name_prefix_idx
  on public.food_dataset_records (
    import_id,
    public.food_immutable_unaccent(lower(name)) text_pattern_ops
  );

create or replace function public.food_database_status()
returns table(status text, dataset_version text, product_count bigint, barcode_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case when active.id is null or active.imported_record_count = 0
      then 'dataset_not_imported' else 'ready' end,
    active.dataset_version,
    coalesce(active.imported_record_count, 0)::bigint,
    coalesce(
      nullif(active.metadata->>'barcode_record_count', '')::bigint,
      (select count(*) from public.food_dataset_records r
       where r.import_id = active.id and r.original_barcode is not null),
      0
    )::bigint
  from (select 1) seed
  left join public.food_dataset_imports active
    on active.provider = 'open_nutrition' and active.status = 'active';
$$;

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
  if active_id is null then
    return query select 'dataset_not_imported'::text, null::jsonb;
    return;
  end if;

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
    select
      public.food_immutable_unaccent(lower(left(btrim(p_query), 120))) term,
      websearch_to_tsquery(
        'simple', public.food_immutable_unaccent(lower(left(btrim(p_query), 120)))
      ) query,
      greatest(p_page, 1) page_number,
      least(greatest(p_page_size, 1), 50) page_size
  ), active as (
    select id from public.food_dataset_imports
    where provider = 'open_nutrition' and status = 'active'
  ), candidates as (
    select r.product,
      (case
         when public.food_immutable_unaccent(lower(r.name)) = parameters.term then 50
         when public.food_immutable_unaccent(lower(coalesce(r.product->>'brand', ''))) = parameters.term then 45
         when public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%' then 30
         when public.food_immutable_unaccent(lower(coalesce(r.product->>'brand', ''))) like parameters.term || '%' then 25
         when position(parameters.term in public.food_immutable_unaccent(lower(r.name))) > 0 then 20
         when position(parameters.term in r.normalized_search_text) > 0 then 10
         else 0
       end + ts_rank_cd(r.search_document, parameters.query))::real score
    from public.food_dataset_records r cross join parameters
    where r.import_id = (select id from active)
      and (
        r.search_document @@ parameters.query
        or public.food_immutable_unaccent(lower(r.name)) like parameters.term || '%'
        or public.food_immutable_unaccent(lower(coalesce(r.product->>'brand', ''))) like parameters.term || '%'
      )
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
      (100 + case
         when public.food_immutable_unaccent(lower(p.name)) = parameters.term then 50
         when public.food_immutable_unaccent(lower(coalesce(p.brand, ''))) = parameters.term then 45
         when public.food_immutable_unaccent(lower(p.name)) like parameters.term || '%' then 30
         when public.food_immutable_unaccent(lower(coalesce(p.brand, ''))) like parameters.term || '%' then 25
         else ts_rank_cd(
           to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ', p.name, p.generic_name, p.brand, p.ingredients)))),
           parameters.query
         )
       end)::real
    from public.food_products p cross join parameters
    where p.verification_status in ('photo_verified', 'community_verified')
      and (
        to_tsvector('simple', public.food_immutable_unaccent(lower(concat_ws(' ', p.name, p.generic_name, p.brand, p.ingredients))))
          @@ parameters.query
        or public.food_immutable_unaccent(lower(p.name)) like parameters.term || '%'
        or public.food_immutable_unaccent(lower(coalesce(p.brand, ''))) like parameters.term || '%'
      )
  ), counted as (
    select candidates.*, count(*) over () total from candidates
  )
  select product, score, total from counted
  order by score desc, product->>'name', product->>'id'
  offset (select (page_number - 1) * page_size from parameters)
  limit (select page_size from parameters);
$$;

revoke all on function public.food_database_status() from public;
revoke all on function public.lookup_food_by_barcode(text) from public;
revoke all on function public.search_food_products(text, integer, integer) from public;
grant execute on function public.food_database_status() to anon, authenticated;
grant execute on function public.lookup_food_by_barcode(text) to anon, authenticated;
grant execute on function public.search_food_products(text, integer, integer) to anon, authenticated;
