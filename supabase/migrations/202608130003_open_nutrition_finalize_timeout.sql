-- Final promotion scans the complete release to validate counts and record
-- duplicate barcodes. Allow this operator-only function to finish atomically
-- even when the public Data API role has a short default statement timeout.

alter function public.finalize_open_nutrition_import(uuid, boolean)
  set statement_timeout = '0';
