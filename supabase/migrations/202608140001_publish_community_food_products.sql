-- Publish a confirmed contribution through one authenticated, idempotent
-- database boundary. The contribution remains pending for moderation/evidence
-- review, while the normalized product is immediately usable by the community.

create or replace function public.publish_food_contribution(p_contribution_id uuid)
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
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into contribution
  from public.food_product_contributions
  where id = p_contribution_id
    and submitted_by = (select auth.uid())
  for update;

  if not found then
    raise exception 'contribution not found';
  end if;

  -- A retry after a successful publish is safe and returns the same product.
  if contribution.product_id is not null then
    return contribution.product_id;
  end if;

  -- The unique barcode constraint is the race-condition guard. If another
  -- request won the race, attach this contribution to the existing record.
  select id into target_id
  from public.food_products
  where barcode = contribution.barcode
  for update;

  if target_id is null then
    insert into public.food_products (
      barcode, name, generic_name, brand, country_code, package_quantity,
      package_unit, serving_quantity, serving_unit, serving_grams,
      serving_milliliters, servings_per_container, ingredients, allergens,
      source, verification_status, created_by
    ) values (
      contribution.barcode,
      left(btrim(coalesce(contribution.proposed_product_data->>'name', '')), 180),
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
      'pulsar_community', 'photo_verified', contribution.submitted_by
    ) on conflict (barcode) do nothing returning id into target_id;

    if target_id is null then
      select id into target_id
      from public.food_products
      where barcode = contribution.barcode
      for update;
    end if;

    if not exists (select 1 from public.food_product_nutrients where product_id = target_id) then
      for item in select value from jsonb_array_elements(contribution.proposed_nutrients)
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
    end if;
  end if;

  update public.food_product_contributions
  set product_id = target_id
  where id = contribution.id;
  return target_id;
end;
$$;

revoke all on function public.publish_food_contribution(uuid) from public, anon;
grant execute on function public.publish_food_contribution(uuid) to authenticated;
