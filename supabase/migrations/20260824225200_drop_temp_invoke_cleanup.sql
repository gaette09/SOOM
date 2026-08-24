-- Cleans up the TEMP verification helper from
-- 20260824224900_temp_invoke_cleanup.sql (that migration file was
-- removed after use, per this repo's temp-migration convention).
drop function if exists public.temp_batch6_invoke_cleanup();
