-- #Мне лень писать коммент к каждой сущности, названия все максимально сделал говорящими, если че спрашивайте, все отвечу. Всем привет, кстати
CREATE TABLE haha_areas(
      id SERIAL PRIMARY KEY,
      area_name VARCHAR(100) UNIQUE NOT NULL,
      buffer_minutes INT DEFAULT 10  NOT NULL,
      traffic_coefficient NUMERIC(3,2) DEFAULT 1.00,
      event_diffs NUMERIC (3,2) DEFAULT 1.00,
      n_couriers_in_area DEFAULT 0
);
CREATE TABLE haha_couriers( 
    id SERIAL PRIMARY KEY,
    fio VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    area INT REFERENCES haha_areas(id),
    transport_type VARCHAR(50) NOT NULL CHECK(
          transport_type IN (
            'Пешком',
            'На электросамокате',
            'На велосипеде',
            'На мопеде',
            'На мотоцикле',
            'На машине',
            'На электровелосипеде'
          )
    ),
    sla_rating NUMERIC(5,2) DEFAULT 100.00 NOT NULL
);
CREATE TABLE haha_cancel_reasons(
    id SERIAL PRIMARY KEY,
    kakova_prichina VARCHAR(255) UNIQUE NOT NULL,
    is_courier_fault BOOLEAN DEFAULT FALSE NOT NULL
);
CREATE TABLE haha_orders(
    id SERIAL PRIMARY KEY,
    courier_id INT REFERENCES haha_couriers(id) ON DELETE SET NULL,
    items_description TEXT NOT NULL,
    distance NUMERIC(4,2) NOT NULL,
    area INT REFERENCES haha_areas(id) NOT NULL,
    planned_from TIMESTAMP NOT NULL,
    planned_to TIMESTAMP NOT NULL,
    delivered_actually_at TIMESTAMP, 
    status VARCHAR(50) DEFAULT 'Новый' NOT NULL, 
    cancel_reason INT REFERENCES haha_cancel_reasons(id)
    );
CREATE TABLE haha_order_statuses(
     id SERIAL PRIMARY KEY,
     order_id INT REFERENCES haha_orders(id) ON DELETE CASCADE NOT NULL,
    courier_id INT REFERENCES haha_couriers(id),
    status_actual VARCHAR(50) NOT NULL CHECK(status_actual IN ('Новый','В пути', 'Доставлен', 'Отменен')),
    timestop TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    cancel_reason  INT REFERENCES haha_cancel_reasons(id)
    );

CREATE OR REPLACE FUNCTION fn_haha_penalty_sla()
RETURNS TRIGGER AS $$
Declare
   v_is_fault BOOLEAN;
BEGIN 
    IF NEW.status_actual ='Отменен' AND NEW.cancel_reason IS NOT NULL THEN
    SELECT is_courier_fault INTO v_is_fault 
    FROM haha_cancel_reasons
    WHERE id=NEW.cancel_reason;
    IF v_is_fault = TRUE AND NEW.courier_id IS NOT NULL THEN
    UPDATE haha_couriers
    SET sla_rating = GREATEST(0.00, sla_rating-10.00)
    WHERE Id= NEW.courier_id;
    END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql; 
CREATE TRIGGER trg_haha_after_cancel
AFTER INSERT ON haha_order_statuses
FOR EACH ROW
EXECUTE FUNCTION fn_haha_penalty_sla(); 

CREATE OR REPLACE FUNCTION fn_haha_sync_order_status()
RETURNS TRIGGER AS $$
BEGIN 
    UPDATE haha_orders
    SET status=NEW.status_actual,
      cancel_reason=NEW.cancel_reason
    WHERE id=New.order_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_haha_after_status_insert
AFTER INSERT ON haha_order_statuses
FOR EACH ROW
EXECUTE FUNCTION fn_haha_sync_order_status();

CREATE OR REPLACE FUNCTION fn_haha_calculate_sla_deadline()
RETURNS TRIGGER AS $$
Declare
   vid_transporta VARCHAR(50);
   v_minutes_per_km NUMERIC;
   result_delivery_time NUMERIC;
BEGIN
  IF NEW.courier_id IS NOT NULL THEN
     SELECT transport_type into vid_transporta
     FROM haha_couriers
     WHERE id=New.courier_id;
  ELSE 
   vid_transporta:='Пешком';
   END IF;

   IF vid_transporta='Пешком' THEN
   v_minutes_per_km:=15;
   ELSEIF vid_transporta='На электросамокате' THEN
   v_minutes_per_km:=7;
   ELSEIF vid_transporta='На велосипеде' THEN
   v_minutes_per_km:=8;
   ELSEIF vid_transporta='На электровелосипеде' THEN
   v_minutes_per_km:=5;
   ELSEIF vid_transporta IN ('На мопеде', 'На мотоцикле') THEN
   v_minutes_per_km:=4;
   ELSEIF vid_transporta='На машине' THEN
   v_minutes_per_km:=3;
   ELSE
   v_minutes_per_km=10;
END IF;
result_delievery_time:=NEW.distance*v_minutes_per_km;
IF result_delievery_time<20 THEN
   result_delievery_time:=20;
END IF;
  NEW.planned_to:= NEW.planned_from + (result_delievery_time || ' minutes')::INTERVAL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql; 

CREATE TRIGGER trg_haha_sla_control
BEFORE INSERT UPDATE of courier_id ON haha_orders 
FOR EACH ROW
EXECUTE FUNCTION fn_haha_calculate_sla_deadline();

CREATE OR REPLACE FUNCTION haha_area_number_of_couriers()
RETURNS TRIGGER AS $$
BEGIN
IF TG_OP='INSERT' AND New.area IS NOT NULL THEN
 Update haha_areas
 SET n_couriers_in_area=n_couriers_in_area+1
 where id = New.area;
END IF; 
IF TG_OP='DELETE' AND Old.area IS NOT NULL  THEN
Update haha_areas
SET n_couriers_in_area=GREATEST(n_couriers_in_area-1,0)
where id= Old.area;
END IF;
IF TG_OP='UPDATE' and New.area IS DISTINCT FROM Old.area THEN
 IF New.area IS NOT NULL THEN
 Update haha_areas
 SET n_couriers_in_area=n_couriers_in_area+1
 where id = New.area;
 END IF;
IF Old.area IS NOT NULL THEN
 Update haha_areas
 SET n_couriers_in_area=GREATEST(n_couriers_in_area-1,0)
 where id= Old.area;
 END IF;
 END IF;
RETURN NULL;
END;
$$ LANGUAGE plpgsql; 
CREATE TRIGGER haha_n_couriers_in_area_detect
AFTER INSERT OR UPDATE OR DELETE ON haha_couriers
FOR EACH ROW
EXECUTE FUNCTION haha_area_number_of_couriers(); 