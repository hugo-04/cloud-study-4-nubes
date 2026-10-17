-- Aurora PostgreSQL: pedidos + bandeja de salida (se escriben en la MISMA transacción)
CREATE TABLE IF NOT EXISTS pedidos (
    id              UUID PRIMARY KEY,
    cliente_id      TEXT        NOT NULL,
    total           NUMERIC(12,2) NOT NULL CHECK (total >= 0),
    envio           TEXT        NOT NULL,
    estado          TEXT        NOT NULL DEFAULT 'CREADO',
    clave_idempotencia TEXT     NOT NULL,
    creado          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (cliente_id, clave_idempotencia)
);

CREATE TABLE IF NOT EXISTS bandeja_salida (
    id          UUID PRIMARY KEY,                 -- = id del evento (idempotencia aguas abajo)
    tipo        TEXT        NOT NULL,             -- PedidoCreado
    agregado_id UUID        NOT NULL,
    carga       JSONB       NOT NULL,
    creado      TIMESTAMPTZ NOT NULL DEFAULT now(),
    publicado   TIMESTAMPTZ,
    intentos    INT         NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS ix_bandeja_pendientes ON bandeja_salida (creado) WHERE publicado IS NULL;

-- Dos transacciones del servicio de pedidos:
-- BEGIN;
--   INSERT INTO pedidos (...) VALUES (...) ON CONFLICT (cliente_id, clave_idempotencia) DO NOTHING;
--   INSERT INTO bandeja_salida (id, tipo, agregado_id, carga) VALUES (...);
-- COMMIT;

-- Lectura del publicador (varias réplicas sin pisarse):
-- SELECT id, tipo, agregado_id, carga FROM bandeja_salida
--  WHERE publicado IS NULL ORDER BY creado LIMIT 10 FOR UPDATE SKIP LOCKED;
