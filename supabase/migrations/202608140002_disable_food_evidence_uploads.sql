-- Package photos are transient on-device OCR input. Keep the historical
-- nullable columns for migration compatibility, but remove all client upload
-- permissions so future app versions cannot persist label images remotely.

drop policy if exists "contributors upload evidence to own pending proposal" on storage.objects;
drop policy if exists "contributors read own evidence" on storage.objects;
drop policy if exists "contributors replace own pending evidence" on storage.objects;
drop policy if exists "contributors delete own pending evidence" on storage.objects;
