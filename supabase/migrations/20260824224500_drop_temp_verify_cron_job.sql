-- Cleans up the TEMP verification helper from
-- 20260824224200_temp_verify_cron_job.sql (that migration file was
-- removed after use, per this repo's temp-migration convention).
drop function if exists public.temp_batch6_list_cron_jobs();
