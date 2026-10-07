-- #Мне лень писать коммент к каждой сущности, названия все максимально сделал говорящими, если че спрашивайте, все отвечу. Всем привет, кстати
CREATE TABLE haha_couriers(
    id SERIAL PRIMARY KEY,
    fio VARCHAR(255) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    area VARCHAR(100) NOT NULL,
    transport_type VARCHAR(50) NOT NULL,
    sla_rating NUMERIC(5,2) DEFAULT 100.00 NOT NULL
);
CREATE TABLE haha_cancel_reasons(
    id SERIAL PRIMARY KEY,
    kakova_prichina VARCHAR(255) UNIQUE NOT NULL
);
CREATE TABLE haha_orders(
    id SERIAL PRIMARY KEY,
    courier_id INT REFERENCES haha_couriers(id) ON DELETE SET NULL,
    items_description TEXT NOT NULL,
    distance NUMERIC(4,2) NOT NULL,
    area VARCHAR(100) NOT NULL,
    planned_from TIMESTAMP NOT NULL,
    planned_to TIMESTAMP NOT NULL,
    delievered_actually_at TIMESTAMP,
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
BEGIN 
    IF NEW.status_actual ='Отменен' AND NEW.cancel_reason=2 THEN
    UPDATE haha_couriers
    SET sla_rating = GREATEST(0.00, sla_rating-10.00)
    WHERE Id= NEW.courier_id;
    END IF;
    RETURN NEW;
END;
$$ LANGAUGE plgsql;
CREATE TRIGGER trg_haha_after_cancel
AFTER INSERT ON haha_order_statuses
FOR EACH ROW
EXECUTION FUNCTION fn_haha_penalty_sla();