ALTER TABLE public.notifications
  DROP CONSTRAINT notifications_event_type_check,
  ADD CONSTRAINT notifications_event_type_check
    CHECK (event_type = ANY (ARRAY[
      'booking_created'::text,
      'booking_confirmed'::text,
      'booking_rejected'::text,
      'booking_completed'::text,
      'booking_reminder'::text
    ]));

CREATE UNIQUE INDEX notifications_one_booking_reminder
  ON public.notifications (booking_id, event_type)
  WHERE event_type = 'booking_reminder';

CREATE OR REPLACE FUNCTION private.create_booking_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_created integer;
BEGIN
  INSERT INTO public.notifications
    (recipient_id, barbershop_id, booking_id, event_type, title, body)
  SELECT
    b.customer_id,
    b.barbershop_id,
    b.id,
    'booking_reminder',
    'Ёдрас: навбати шумо пагоҳ аст',
    COALESCE(b.barbershop_name_snapshot, s.name, 'Сартарошхона')
      || ' · ' || COALESCE(b.service_name_snapshot, s.name, 'Хизматрасонӣ')
      || ' · ' || to_char(b.starts_at AT TIME ZONE 'Asia/Dushanbe', 'DD.MM.YYYY HH24:MI')
  FROM public.bookings AS b
  LEFT JOIN public.services AS s ON s.id = b.service_id
  WHERE b.status IN ('pending', 'confirmed')
    AND b.starts_at > now() + interval '23 hours 55 minutes'
    AND b.starts_at <= now() + interval '24 hours 5 minutes'
  ON CONFLICT (booking_id, event_type)
    WHERE event_type = 'booking_reminder'
    DO NOTHING;

  GET DIAGNOSTICS v_created = ROW_COUNT;
  RETURN v_created;
END;
$function$;

REVOKE ALL ON FUNCTION private.create_booking_reminders() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.cleanup_booking_reminder()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NEW.starts_at IS DISTINCT FROM OLD.starts_at
     OR NEW.status = 'cancelled' THEN
    DELETE FROM public.notifications
    WHERE booking_id = NEW.id
      AND event_type = 'booking_reminder';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.cleanup_booking_reminder() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS booking_reminder_cleanup_after_update ON public.bookings;
CREATE TRIGGER booking_reminder_cleanup_after_update
AFTER UPDATE OF starts_at, status ON public.bookings
FOR EACH ROW
EXECUTE FUNCTION private.cleanup_booking_reminder();

DO $block$
BEGIN
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'customer-booking-reminders';

  PERFORM cron.schedule(
    'customer-booking-reminders',
    '* * * * *',
    'SELECT private.create_booking_reminders();'
  );
END;
$block$;
