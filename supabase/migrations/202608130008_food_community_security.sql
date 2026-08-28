-- Harden the community boundary for environments that applied the base food
-- migration without every later OpenNutrition migration.
-- Personal Pulsar data is intentionally absent from this schema.

drop policy if exists "published products are readable" on public.food_products;
drop policy if exists "published nutrients are readable" on public.food_product_nutrients;
drop policy if exists "verified products are readable" on public.food_products;
drop policy if exists "verified product nutrients are readable" on public.food_product_nutrients;
drop policy if exists "contributors replace own pending evidence" on storage.objects;

create policy "verified products are readable"
on public.food_products for select to anon, authenticated
using (verification_status in ('imported', 'photo_verified', 'community_verified'));

create policy "verified product nutrients are readable"
on public.food_product_nutrients for select to anon, authenticated
using (exists (
  select 1
  from public.food_products p
  where p.id = product_id
    and p.verification_status in ('imported', 'photo_verified', 'community_verified')
));

create policy "contributors replace own pending evidence"
on storage.objects for update to authenticated
using (
  bucket_id = 'food-product-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and array_length(storage.foldername(name), 1) = 3
  and storage.filename(name) in ('front.jpg', 'nutrition.jpg', 'ingredients.jpg')
  and exists (
    select 1
    from public.food_product_contributions c
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

-- Review is a backend-only operation. The iOS publishable key cannot approve,
-- reject, or mutate a published product directly.
create or replace function public.review_food_contribution(
  p_contribution_id uuid,
  p_status public.food_contribution_status,
  p_reviewer_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  contribution public.food_product_contributions;
  target_id uuid;
  item jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'invalid review status';
  end if;

  select * into contribution
  from public.food_product_contributions
  where id = p_contribution_id and status = 'pending'
  for update;
  if not found then raise exception 'pending contribution not found'; end if;

  if p_status = 'approved' then
    if contribution.product_id is null then
      insert into public.food_products (
        barcode, name, generic_name, brand, country_code, package_quantity,
        package_unit, serving_quantity, serving_unit, serving_grams,
        serving_milliliters, servings_per_container, ingredients, allergens,
        source, verification_status, created_by, verified_at
      )
      values (
        contribution.barcode,
        left(coalesce(contribution.proposed_product_data->>'name', 'Unnamed food'), 180),
        nullif(left(contribution.proposed_product_data->>'generic_name', 300), ''),
        nullif(left(contribution.proposed_product_data->>'brand', 180), ''),
        nullif(contribution.proposed_product_data->>'country_code', ''),
        nullif(contribution.proposed_product_data->>'package_quantity', '')::numeric,
        nullif(contribution.proposed_product_data->>'package_unit', ''),
        nullif(contribution.proposed_product_data->>'serving_quantity', '')::numeric,
        nullif(contribution.proposed_product_data->>'serving_unit', ''),
        nullif(contribution.proposed_product_data->>'serving_grams', '')::numeric,
        nullif(contribution.proposed_product_data->>'serving_milliliters', '')::numeric,
        nullif(contribution.proposed_product_data->>'servings_per_container', '')::numeric,
        left(nullif(contribution.proposed_product_data->>'ingredients', ''), 8000),
        coalesce(array(select jsonb_array_elements_text(contribution.proposed_product_data->'allergens')), '{}'),
        'pulsar_community', 'community_verified', contribution.submitted_by, now()
      ) returning id into target_id;
    else
      target_id := contribution.product_id;
      update public.food_products
      set name = left(coalesce(contribution.proposed_product_data->>'name', name), 180),
          generic_name = nullif(left(contribution.proposed_product_data->>'generic_name', 300), ''),
          brand = nullif(left(contribution.proposed_product_data->>'brand', 180), ''),
          country_code = nullif(contribution.proposed_product_data->>'country_code', ''),
          package_quantity = nullif(contribution.proposed_product_data->>'package_quantity', '')::numeric,
          package_unit = nullif(contribution.proposed_product_data->>'package_unit', ''),
          serving_quantity = nullif(contribution.proposed_product_data->>'serving_quantity', '')::numeric,
          serving_unit = nullif(contribution.proposed_product_data->>'serving_unit', ''),
          serving_grams = nullif(contribution.proposed_product_data->>'serving_grams', '')::numeric,
          serving_milliliters = nullif(contribution.proposed_product_data->>'serving_milliliters', '')::numeric,
          servings_per_container = nullif(contribution.proposed_product_data->>'servings_per_container', '')::numeric,
          ingredients = left(nullif(contribution.proposed_product_data->>'ingredients', ''), 8000),
          allergens = coalesce(array(select jsonb_array_elements_text(contribution.proposed_product_data->'allergens')), '{}'),
          verification_status = 'community_verified',
          verified_at = now()
      where id = target_id;
    end if;

    delete from public.food_product_nutrients where product_id = target_id;
    for item in select value from jsonb_array_elements(contribution.proposed_nutrients)
    loop
      insert into public.food_product_nutrients (product_id, nutrient_key, amount, unit, basis, confidence)
      values (
        target_id,
        item->>'nutrient_key',
        (item->>'amount')::numeric,
        item->>'unit',
        (item->>'basis')::public.food_nutrient_basis,
        nullif(item->>'confidence', '')::numeric
      );
    end loop;
  end if;

  update public.food_product_contributions
  set status = p_status, reviewed_by = p_reviewer_id, reviewed_at = now()
  where id = contribution.id;
  return target_id;
end;
$$;

revoke all on function public.review_food_contribution(uuid, public.food_contribution_status, uuid)
from public, anon, authenticated;
grant execute on function public.review_food_contribution(uuid, public.food_contribution_status, uuid)
to service_role;
