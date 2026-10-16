-- Flyway: V1__esquema_inicial.sql  (esquema de ejemplo de ModaLima en PostgreSQL)
-- Se ejecuta con la identidad dueña "id-pipeline-migraciones".

CREATE TABLE ventas.cliente (
    id          text PRIMARY KEY,
    nombre      text NOT NULL,
    correo      text NOT NULL,
    documento_identidad text,
    creado_en   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ventas.pedido (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id  text NOT NULL REFERENCES ventas.cliente (id),
    estado      text NOT NULL CHECK (estado IN ('CREADO', 'PAGADO', 'ENVIADO', 'CANCELADO')),
    total       numeric(12, 2) NOT NULL CHECK (total >= 0),
    atributos   jsonb NOT NULL DEFAULT '{}'::jsonb,
    creado_en   timestamptz NOT NULL DEFAULT now(),
    version     bigint NOT NULL DEFAULT 0              -- @Version de JPA
);

-- Pedidos de un cliente, los más recientes primero (cubre la consulta paginada)
CREATE INDEX ix_pedido_cliente ON ventas.pedido (cliente_id, id DESC);

-- Búsquedas por atributos dentro del jsonb (atributos @> '{"vip": true}')
CREATE INDEX ix_pedido_atributos ON ventas.pedido USING gin (atributos jsonb_path_ops);

-- Índice parcial: solo los pedidos activos (más pequeño y rápido)
CREATE INDEX ix_pedido_activos ON ventas.pedido (creado_en) WHERE estado IN ('CREADO', 'PAGADO');

CREATE TABLE ventas.pedido_linea (
    pedido_id   bigint NOT NULL REFERENCES ventas.pedido (id) ON DELETE CASCADE,
    linea       integer NOT NULL,
    producto_id text NOT NULL,
    cantidad    integer NOT NULL CHECK (cantidad > 0),
    precio      numeric(12, 2) NOT NULL,
    PRIMARY KEY (pedido_id, linea)
);

CREATE TABLE ventas.stock (
    producto_id text PRIMARY KEY,
    cantidad    integer NOT NULL DEFAULT 0
);

-- Idempotencia de consumidores: un evento ya procesado no se repite
CREATE TABLE ventas.evento_procesado (
    evento_id   text PRIMARY KEY,
    procesado_en timestamptz NOT NULL DEFAULT now()
);

-- Tabla particionada por mes para históricos grandes (se crean particiones por adelantado o con pg_partman)
CREATE TABLE ventas.pedido_evento (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    pedido_id   bigint NOT NULL,
    tipo        text NOT NULL,
    datos       jsonb,
    ocurrido_en timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, ocurrido_en)
) PARTITION BY RANGE (ocurrido_en);

CREATE TABLE ventas.pedido_evento_2026_10 PARTITION OF ventas.pedido_evento
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE ventas.pedido_evento_2026_11 PARTITION OF ventas.pedido_evento
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
