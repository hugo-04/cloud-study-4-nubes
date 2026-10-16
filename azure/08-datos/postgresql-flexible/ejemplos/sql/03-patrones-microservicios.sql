-- Patrones de microservicios directamente en PostgreSQL.

-- 1) COLA DE TAREAS / OUTBOX con FOR UPDATE SKIP LOCKED
CREATE TABLE ventas.tarea (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo             text NOT NULL,
    carga            jsonb NOT NULL,
    estado           text NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE', 'EN_CURSO', 'HECHA', 'FALLIDA')),
    intentos         integer NOT NULL DEFAULT 0,
    disponible_desde timestamptz NOT NULL DEFAULT now(),
    creada_en        timestamptz NOT NULL DEFAULT now(),
    terminada_en     timestamptz
);

-- Solo las pendientes: el índice se mantiene pequeño aunque la tabla crezca
CREATE INDEX ix_tarea_pendientes ON ventas.tarea (disponible_desde, id) WHERE estado = 'PENDIENTE';

-- Tomar un lote: varias réplicas pueden ejecutar esto a la vez y reciben tareas distintas
-- BEGIN;
-- SELECT id, tipo, carga FROM ventas.tarea
--  WHERE estado = 'PENDIENTE' AND disponible_desde <= now()
--  ORDER BY id LIMIT 10
--  FOR UPDATE SKIP LOCKED;
-- UPDATE ventas.tarea SET estado = 'EN_CURSO', intentos = intentos + 1 WHERE id = ANY (:ids);
-- COMMIT;

-- Reintento con retroceso: devolver la tarea a la cola con espera creciente
-- UPDATE ventas.tarea
--    SET estado = 'PENDIENTE', disponible_desde = now() + (interval '10 seconds' * power(2, intentos))
--  WHERE id = :id AND intentos < 6;

-- 2) UPSERT idempotente
-- INSERT INTO ventas.stock (producto_id, cantidad) VALUES ('p-100', 5)
-- ON CONFLICT (producto_id) DO UPDATE SET cantidad = ventas.stock.cantidad + EXCLUDED.cantidad;

-- 3) BLOQUEO CONSULTIVO por transacción (líder único de un trabajo programado)
-- SELECT pg_try_advisory_xact_lock(42);   -- true solo para UNA transacción a la vez

-- 4) NOTIFICAR cambios con LISTEN/NOTIFY (OJO: no funciona con PgBouncer en modo transacción)
CREATE OR REPLACE FUNCTION ventas.notificar_pedido() RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify('pedidos', json_build_object('id', NEW.id, 'estado', NEW.estado)::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_pedido_notificar
    AFTER INSERT OR UPDATE OF estado ON ventas.pedido
    FOR EACH ROW EXECUTE FUNCTION ventas.notificar_pedido();

-- 5) SEGURIDAD A NIVEL DE FILA (multi-inquilino) con una variable de sesión
ALTER TABLE ventas.pedido ADD COLUMN inquilino_id text NOT NULL DEFAULT 'modalima';
ALTER TABLE ventas.pedido ENABLE ROW LEVEL SECURITY;

CREATE POLICY aislar_inquilino ON ventas.pedido
    USING (inquilino_id = current_setting('app.inquilino', true))
    WITH CHECK (inquilino_id = current_setting('app.inquilino', true));

-- La aplicación fija el inquilino AL INICIO DE CADA TRANSACCIÓN (compatible con PgBouncer):
-- BEGIN; SET LOCAL app.inquilino = 'cliente-A'; SELECT * FROM ventas.pedido; COMMIT;

-- 6) Concurrencia optimista a mano (sin ORM)
-- UPDATE ventas.pedido SET estado = 'PAGADO', version = version + 1 WHERE id = :id AND version = :version_leida;
-- (0 filas actualizadas = alguien cambió el pedido: responder 409)
