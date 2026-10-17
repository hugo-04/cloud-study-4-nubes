-- Outbox (servicio de pedidos) e inbox (servicio de facturación). Oracle SQL (ATP).
CREATE TABLE outbox (
  id_evento     VARCHAR2(36)  PRIMARY KEY,
  tipo          VARCHAR2(60)  NOT NULL,          -- p. ej. PedidoPagado.v1
  clave         VARCHAR2(64)  NOT NULL,          -- id del pedido
  carga         CLOB          CHECK (carga IS JSON),
  estado        VARCHAR2(12)  DEFAULT 'PENDIENTE' NOT NULL,  -- PENDIENTE | ENVIADO | FALLIDO
  intentos      NUMBER(3)     DEFAULT 0 NOT NULL,
  creado        TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);
CREATE INDEX outbox_pendientes ON outbox (estado, creado);

-- En la MISMA transacción que el INSERT del pedido:
-- INSERT INTO outbox (id_evento, tipo, clave, carga) VALUES (:id, 'PedidoPagado.v1', :pedido, :json);

-- Relay: toma un lote sin pisarse con otras réplicas
-- SELECT id_evento, tipo, clave, carga FROM outbox
--  WHERE estado = 'PENDIENTE' ORDER BY creado FETCH FIRST 50 ROWS ONLY FOR UPDATE SKIP LOCKED;

CREATE TABLE inbox (
  id_evento   VARCHAR2(36) PRIMARY KEY,   -- la clave única ES la idempotencia
  recibido    TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);
