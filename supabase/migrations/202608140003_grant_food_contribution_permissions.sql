-- RLS policies do not grant table privileges. Keep the contribution boundary
-- explicit: authenticated contributors may only reach their own rows through
-- the policies defined in the food community schema migration.

grant select, insert, update on table public.food_product_contributions to authenticated;
grant execute on function public.publish_food_contribution(uuid) to authenticated;
