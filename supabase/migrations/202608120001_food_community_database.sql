-- Pulsar community food products, evidence storage, and review-safe contributions.
-- Apply with `supabase db push`; never run this from the iOS client.

create extension if not exists pgcrypto;

create type public.food_product_source as enum (
  'pulsar_community', 'open_food_facts', 'label_ocr', 'manual'
);
create type public.food_verification_status as enum (
  'imported', 'community_submitted', 'photo_verified', 'community_verified', 'needs_review', 'outdated'
);
create type public.food_nutrient_basis as enum (
  'per_serving', 'per_100g', 'per_100ml', 'per_package'
);
create type public.food_contribution_type as enum (
  'new_product', 'nutrition_update', 'product_update', 'label_changed'
);
create type public.food_contribution_status as enum (
  'pending', 'approved', 'rejected', 'needs_review'
);

create table public.food_products (
  id uuid primary key default gen_random_uuid(),
  barcode text not null unique check (barcode ~ '^[0-9]{14}$'),
  name text not null check (length(btrim(name)) between 1 and 180),
  generic_name text check (generic_name is null or length(generic_name) <= 300),
  brand text check (brand is null or length(brand) <= 180),
  country_code text check (country_code is null or country_code ~ '^[a-zA-Z]{2}$'),
  package_quantity numeric check (package_quantity is null or package_quantity > 0),
  package_unit text,
  serving_quantity numeric check (serving_quantity is null or serving_quantity > 0),
  serving_unit text,
  serving_grams numeric check (serving_grams is null or serving_grams > 0),
  serving_milliliters numeric check (serving_milliliters is null or serving_milliliters > 0),
  servings_per_container numeric check (servings_per_container is null or servings_per_container > 0),
  front_image_url text,
  nutrition_image_url text,
  ingredients_image_url text,
  ingredients text check (ingredients is null or length(ingredients) <= 8000),
  allergens text[] not null default '{}',
  source public.food_product_source not null,
  source_product_id text,
  source_updated_at timestamptz,
  raw_source_payload jsonb,
  verification_status public.food_verification_status not null default 'imported',
  verification_count integer not null default 0 check (verification_count >= 0),
  verified_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index food_products_name_idx on public.food_products using gin (to_tsvector('simple', name));
create index food_products_source_idx on public.food_products (source, source_product_id);
create index food_products_verification_idx on public.food_products (verification_status, updated_at desc);

create table public.food_product_nutrients (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.food_products(id) on delete cascade,
  nutrient_key text not null check (nutrient_key ~ '^[a-z0-9_]{2,80}$'),
  amount numeric not null check (amount >= 0 and amount <= 1000000),
  unit text not null check (unit in ('kcal', 'kJ', 'g', 'mg', 'mcg', 'ml')),
  basis public.food_nutrient_basis not null,
  confidence numeric check (confidence is null or confidence between 0 and 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, nutrient_key, basis)
);

create index food_product_nutrients_product_idx on public.food_product_nutrients (product_id);
create index food_product_nutrients_key_idx on public.food_product_nutrients (nutrient_key, basis);

create table public.food_product_contributions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.food_products(id) on delete set null,
  barcode text not null check (barcode ~ '^[0-9]{14}$'),
  submitted_by uuid not null references auth.users(id) on delete cascade,
  contribution_type public.food_contribution_type not null,
  proposed_product_data jsonb not null check (jsonb_typeof(proposed_product_data) = 'object'),
  proposed_nutrients jsonb not null default '[]'::jsonb check (jsonb_typeof(proposed_nutrients) = 'array'),
  front_image_path text,
  nutrition_image_path text,
  ingredients_image_path text,
  status public.food_contribution_status not null default 'pending',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status in ('approved', 'rejected')) = (reviewed_at is not null and reviewed_by is not null))
);

create index food_contributions_submitter_idx on public.food_product_contributions (submitted_by, created_at desc);
create index food_contributions_review_queue_idx on public.food_product_contributions (status, created_at);
create index food_contributions_product_idx on public.food_product_contributions (product_id, created_at desc);
create unique index food_contributions_one_pending_kind_idx
  on public.food_product_contributions (submitted_by, barcode, contribution_type)
  where status = 'pending';

-- Immutable history is populated before any trusted product update. Pending proposals never touch this table.
create table public.food_product_versions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.food_products(id) on delete cascade,
  product_snapshot jsonb not null,
  nutrient_snapshot jsonb not null,
  superseded_by uuid references public.food_product_contributions(id) on delete set null,
  archived_by uuid references auth.users(id) on delete set null,
  archived_at timestamptz not null default now()
);
create index food_product_versions_product_idx on public.food_product_versions (product_id, archived_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger food_products_set_updated_at
before update on public.food_products
for each row execute function public.set_updated_at();
create trigger food_product_nutrients_set_updated_at
before update on public.food_product_nutrients
for each row execute function public.set_updated_at();
create trigger food_product_contributions_set_updated_at
before update on public.food_product_contributions
for each row execute function public.set_updated_at();

create or replace function public.archive_food_product_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.food_product_versions (product_id, product_snapshot, nutrient_snapshot, archived_by)
  select
    old.id,
    to_jsonb(old),
    coalesce(jsonb_agg(to_jsonb(n) order by n.nutrient_key) filter (where n.id is not null), '[]'::jsonb),
    auth.uid()
  from public.food_product_nutrients n
  where n.product_id = old.id;
  return new;
end;
$$;

create trigger archive_food_product_before_update
before update on public.food_products
for each row
when (old.verification_status in ('photo_verified', 'community_verified'))
execute function public.archive_food_product_version();

-- Kept outside the insert policy to avoid recursive RLS evaluation on the contributions table.
create or replace function public.pending_food_contribution_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)
  from public.food_product_contributions own_pending
  where own_pending.submitted_by = (select auth.uid())
    and own_pending.status = 'pending';
$$;

revoke all on function public.pending_food_contribution_count() from public, anon;
grant execute on function public.pending_food_contribution_count() to authenticated;

-- Server-validated cache boundary. It can refresh only imported/untrusted rows and cannot overwrite verified data.
create or replace function public.cache_open_food_facts_product(p_product jsonb, p_nutrients jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_id uuid;
  item jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_product->>'source' <> 'open_food_facts' then raise exception 'invalid source'; end if;
  if coalesce(p_product->>'barcode', '') !~ '^[0-9]{14}$' then raise exception 'invalid barcode'; end if;
  if length(btrim(coalesce(p_product->>'name', ''))) not between 1 and 180 then raise exception 'invalid name'; end if;
  if jsonb_typeof(p_nutrients) <> 'array' then raise exception 'invalid nutrients'; end if;

  select id into target_id
  from public.food_products
  where barcode = p_product->>'barcode'
    and verification_status in ('photo_verified', 'community_verified');
  if target_id is not null then return target_id; end if;

  insert into public.food_products (
    id, barcode, name, generic_name, brand, country_code, package_quantity, package_unit,
    serving_quantity, serving_unit, serving_grams, serving_milliliters, servings_per_container, front_image_url,
    nutrition_image_url, ingredients_image_url, ingredients, allergens, source,
    source_product_id, source_updated_at, raw_source_payload, verification_status, created_by
  ) values (
    coalesce((p_product->>'id')::uuid, gen_random_uuid()), p_product->>'barcode', btrim(p_product->>'name'),
    nullif(p_product->>'generic_name', ''), nullif(p_product->>'brand', ''), nullif(p_product->>'country_code', ''),
    nullif(p_product->>'package_quantity', '')::numeric, nullif(p_product->>'package_unit', ''),
    nullif(p_product->>'serving_quantity', '')::numeric, nullif(p_product->>'serving_unit', ''),
    nullif(p_product->>'serving_grams', '')::numeric, nullif(p_product->>'serving_milliliters', '')::numeric,
    nullif(p_product->>'servings_per_container', '')::numeric,
    nullif(p_product->>'front_image_url', ''), nullif(p_product->>'nutrition_image_url', ''),
    nullif(p_product->>'ingredients_image_url', ''), left(nullif(p_product->>'ingredients', ''), 8000),
    coalesce(array(select jsonb_array_elements_text(p_product->'allergens')), '{}'), 'open_food_facts',
    nullif(p_product->>'source_product_id', ''), nullif(p_product->>'source_updated_at', '')::timestamptz,
    case when p_product ? 'raw_source_payload' then (p_product->>'raw_source_payload')::jsonb else null end,
    case when p_product->>'verification_status' = 'needs_review' then 'needs_review'::public.food_verification_status else 'imported'::public.food_verification_status end,
    auth.uid()
  )
  on conflict (barcode) do update set
    name = excluded.name, generic_name = excluded.generic_name, brand = excluded.brand,
    country_code = excluded.country_code, package_quantity = excluded.package_quantity,
    package_unit = excluded.package_unit, serving_quantity = excluded.serving_quantity,
    serving_unit = excluded.serving_unit, serving_grams = excluded.serving_grams,
    serving_milliliters = excluded.serving_milliliters, servings_per_container = excluded.servings_per_container,
    front_image_url = excluded.front_image_url,
    nutrition_image_url = excluded.nutrition_image_url, ingredients_image_url = excluded.ingredients_image_url,
    ingredients = excluded.ingredients, allergens = excluded.allergens, source_product_id = excluded.source_product_id,
    source_updated_at = excluded.source_updated_at, raw_source_payload = excluded.raw_source_payload,
    verification_status = excluded.verification_status
  where public.food_products.verification_status not in ('photo_verified', 'community_verified')
  returning id into target_id;

  if target_id is null then
    select id into target_id from public.food_products where barcode = p_product->>'barcode';
    return target_id;
  end if;

  delete from public.food_product_nutrients where product_id = target_id;
  for item in select value from jsonb_array_elements(p_nutrients)
  loop
    if coalesce(item->>'nutrient_key', '') !~ '^[a-z0-9_]{2,80}$'
       or (item->>'amount')::numeric not between 0 and 1000000
       or item->>'unit' not in ('kcal', 'kJ', 'g', 'mg', 'mcg', 'ml')
       or item->>'basis' not in ('per_serving', 'per_100g', 'per_100ml', 'per_package') then
      raise exception 'invalid nutrient';
    end if;
    insert into public.food_product_nutrients (product_id, nutrient_key, amount, unit, basis, confidence)
    values (
      target_id, item->>'nutrient_key', (item->>'amount')::numeric, item->>'unit',
      (item->>'basis')::public.food_nutrient_basis, nullif(item->>'confidence', '')::numeric
    );
  end loop;
  return target_id;
end;
$$;

revoke all on function public.cache_open_food_facts_product(jsonb, jsonb) from public, anon;
grant execute on function public.cache_open_food_facts_product(jsonb, jsonb) to authenticated;

alter table public.food_products enable row level security;
alter table public.food_product_nutrients enable row level security;
alter table public.food_product_contributions enable row level security;
alter table public.food_product_versions enable row level security;

create policy "published products are readable"
on public.food_products for select to anon, authenticated
using (verification_status in ('photo_verified', 'community_verified'));
create policy "published nutrients are readable"
on public.food_product_nutrients for select to anon, authenticated
using (exists (
  select 1 from public.food_products p
  where p.id = product_id
    and p.verification_status in ('photo_verified', 'community_verified')
));
create policy "contributors read own proposals"
on public.food_product_contributions for select to authenticated
using (submitted_by = (select auth.uid()));
create policy "contributors create pending proposals"
on public.food_product_contributions for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and status = 'pending'
  and reviewed_by is null
  and reviewed_at is null
  and public.pending_food_contribution_count() < 50
);
create policy "contributors edit only own pending proposals"
on public.food_product_contributions for update to authenticated
using (submitted_by = (select auth.uid()) and status = 'pending')
with check (submitted_by = (select auth.uid()) and status = 'pending' and reviewed_by is null and reviewed_at is null);
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('food-product-evidence', 'food-product-evidence', false, 8388608, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "contributors upload evidence to own pending proposal"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 3
  and storage.filename(name) in ('front.jpg', 'nutrition.jpg', 'ingredients.jpg')
  and exists (
    select 1 from public.food_product_contributions c
    where c.id::text = (storage.foldername(name))[2]
      and c.submitted_by = (select auth.uid())
      and c.status = 'pending'
  )
);
create policy "contributors read own evidence"
on storage.objects for select to authenticated
using (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 3
);
create policy "contributors replace own pending evidence"
on storage.objects for update to authenticated
using (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 3
  and exists (
    select 1 from public.food_product_contributions c
    where c.id::text = (storage.foldername(name))[2]
      and c.submitted_by = (select auth.uid())
      and c.status = 'pending'
  )
)
with check (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 3
  and storage.filename(name) in ('front.jpg', 'nutrition.jpg', 'ingredients.jpg')
);
create policy "contributors delete own pending evidence"
on storage.objects for delete to authenticated
using (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.food_product_contributions c
    where c.id::text = (storage.foldername(name))[2]
      and c.submitted_by = (select auth.uid())
      and c.status = 'pending'
  )
);

revoke insert, update, delete on public.food_products from anon, authenticated;
revoke insert, update, delete on public.food_product_nutrients from anon, authenticated;
revoke all on public.food_product_versions from anon, authenticated;
