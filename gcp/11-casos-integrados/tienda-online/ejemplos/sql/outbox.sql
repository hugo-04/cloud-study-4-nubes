-- Outbox (servicio de pedidos) e inbox (facturación). PostgreSQL (Cloud SQL).
CREATE TABLE outbox (
  id_evento  uuid        PRIMARY KEY,
  tipo       text        NOT NULL,            -- PedidoPagado.v1
  clave      text        NOT NULL,            -- id del pedido (clave de orden)
  carga      jsonb       NOT NULL,
  estado     text        NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','ENVIADO','FALLIDO')),
  intentos   smallint    NOT NULL DEFAULT 0,
  creado     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_pendientes ON outbox (creado) WHERE estado = 'PENDIENTE';

-- En la MISMA transacción que el INSERT del pedido:
-- INSERT INTO outbox (id_evento, tipo, clave, carga) VALUES ($1, 'PedidoPagado.v1', $2, $3::jsonb);

-- Relay: un lote sin pisarse con otras instancias
-- SELECT id_evento, tipo, clave, carga, intentos FROM outbox
--  WHERE estado = 'PENDIENTE' ORDER BY creado LIMIT 50 FOR UPDATE SKIP LOCKED;

CREATE TABLE inbox (
  id_evento uuid        PRIMARY KEY,          -- la clave única ES la idempotencia
  recibido  timestamptz NOT NULL DEFAULT now()
);
-- INSERT INTO inbox (id_evento) VALUES ($1) ON CONFLICT DO NOTHING;  -- 0 filas = duplicado
