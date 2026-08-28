-- Resume an interrupted compact import from its last committed batch.
-- Each staging RPC is transactional, so the committed row count is a safe
-- prefix offset for the deterministic official TSV stream.

create or replace function public.open_nutrition_import_resume_count(p_import_id uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result bigint;
begin
  perform public.require_food_importer();
  if not exists (
    select 1 from public.food_dataset_imports
    where id = p_import_id and provider = 'open_nutrition' and status in ('loading', 'active')
  ) then raise exception 'import is not resumable'; end if;
  select count(*) into result
  from public.food_dataset_compact_records where import_id = p_import_id;
  return result;
end;
$$;

revoke all on function public.open_nutrition_import_resume_count(uuid)
  from public, anon, authenticated;
grant execute on function public.open_nutrition_import_resume_count(uuid) to service_role;
