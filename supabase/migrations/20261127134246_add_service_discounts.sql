ALTER TABLE public.services
  ADD COLUMN discount_price numeric,
  ADD COLUMN discount_starts_at timestamptz,
  ADD COLUMN discount_ends_at timestamptz,
  ADD CONSTRAINT services_discount_price_check
    CHECK (discount_price IS NULL OR (discount_price >= 0 AND discount_price < price)),
  ADD CONSTRAINT services_discount_period_check
    CHECK (
      (discount_starts_at IS NULL AND discount_ends_at IS NULL)
      OR
      (discount_starts_at IS NOT NULL AND discount_ends_at IS NOT NULL AND discount_starts_at < discount_ends_at)
    );

CREATE OR REPLACE FUNCTION private.set_booking_snapshots()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  SELECT
    s.name,
    CASE
      WHEN s.discount_price IS NOT NULL
       AND s.discount_starts_at IS NOT NULL
       AND s.discount_ends_at IS NOT NULL
       AND now() >= s.discount_starts_at
       AND now() < s.discount_ends_at
      THEN s.discount_price
      ELSE s.price
    END,
    s.duration_minutes
  INTO NEW.service_name_snapshot, NEW.price_snapshot, NEW.duration_minutes_snapshot
  FROM public.services s
  WHERE s.id = NEW.service_id
    AND s.barbershop_id = NEW.barbershop_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Хизматрасонӣ ёфт нашуд ё фаъол нест.';
  END IF;

  SELECT b.name
  INTO NEW.barbershop_name_snapshot
  FROM public.barbershops b
  WHERE b.id = NEW.barbershop_id
    AND b.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'Марказ ёфт нашуд ё фаъол нест.';
  END IF;

  RETURN NEW;
END;
$function$;
