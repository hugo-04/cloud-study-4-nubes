-- Flyway: V1__esquema_inicial.sql  (esquema de ejemplo de ModaLima)
-- Reglas: nunca editar una migración ya aplicada; cambios compatibles hacia atrás.

CREATE SCHEMA ventas;
GO

CREATE TABLE ventas.cliente
(
    id                 nvarchar(40)  NOT NULL PRIMARY KEY,
    nombre             nvarchar(120) NOT NULL,
    correo             nvarchar(200) NOT NULL,
    telefono           nvarchar(30)  NULL,
    documento_identidad nvarchar(30) NULL,
    creado_en          datetime2     NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE ventas.pedido
(
    id           bigint IDENTITY(1, 1) PRIMARY KEY,
    inquilino_id nvarchar(40)  NOT NULL DEFAULT N'modalima',
    cliente_id   nvarchar(40)  NOT NULL,
    estado       nvarchar(20)  NOT NULL,
    total        decimal(12, 2) NOT NULL,
    creado_en    datetime2     NOT NULL DEFAULT SYSUTCDATETIME(),
    version      bigint        NOT NULL DEFAULT 0,                 -- @Version de JPA
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (cliente_id) REFERENCES ventas.cliente (id),
    CONSTRAINT ck_pedido_estado CHECK (estado IN ('CREADO', 'PAGADO', 'ENVIADO', 'CANCELADO')),
    CONSTRAINT ck_pedido_total CHECK (total >= 0)
);

-- Índice para "pedidos de un cliente, los más recientes primero" (cubre la consulta paginada)
CREATE INDEX ix_pedido_cliente_creado
    ON ventas.pedido (cliente_id, creado_en DESC, id DESC)
    INCLUDE (estado, total);

CREATE TABLE ventas.pedido_linea
(
    pedido_id   bigint         NOT NULL,
    linea       int            NOT NULL,
    producto_id nvarchar(40)   NOT NULL,
    cantidad    int            NOT NULL,
    precio      decimal(12, 2) NOT NULL,
    PRIMARY KEY (pedido_id, linea),
    CONSTRAINT fk_linea_pedido FOREIGN KEY (pedido_id) REFERENCES ventas.pedido (id) ON DELETE CASCADE,
    CONSTRAINT ck_linea_cantidad CHECK (cantidad > 0)
);

CREATE TABLE ventas.factura
(
    id         bigint IDENTITY(1, 1) PRIMARY KEY,
    pedido_id  bigint         NOT NULL UNIQUE,                    -- una factura por pedido: idempotencia
    total      decimal(12, 2) NOT NULL,
    emitida_en datetime2      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_factura_pedido FOREIGN KEY (pedido_id) REFERENCES ventas.pedido (id)
);
GO

-- V2__outbox.sql: eventos pendientes de publicar (patrón Outbox)
CREATE TABLE ventas.outbox
(
    id           bigint IDENTITY(1, 1) PRIMARY KEY,
    mensaje_id   uniqueidentifier NOT NULL DEFAULT NEWID(),       -- MessageId fijo -> detección de duplicados en Service Bus
    tipo         nvarchar(100)    NOT NULL,
    cuerpo       nvarchar(max)    NOT NULL,
    creado_en    datetime2        NOT NULL DEFAULT SYSUTCDATETIME(),
    publicado_en datetime2        NULL
);

-- Solo las filas pendientes: el índice filtrado se mantiene pequeño
CREATE INDEX ix_outbox_pendientes ON ventas.outbox (id) WHERE publicado_en IS NULL;
GO

-- V3__historial_pedido.sql: tabla temporal con versión del sistema (historial automático de cambios)
ALTER TABLE ventas.pedido ADD
    valido_desde datetime2 GENERATED ALWAYS AS ROW START HIDDEN NOT NULL DEFAULT SYSUTCDATETIME(),
    valido_hasta datetime2 GENERATED ALWAYS AS ROW END HIDDEN NOT NULL DEFAULT CONVERT(datetime2, '9999-12-31 23:59:59.9999999'),
    PERIOD FOR SYSTEM_TIME (valido_desde, valido_hasta);
ALTER TABLE ventas.pedido SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = ventas.pedido_historial));
GO

-- Consulta de ejemplo: cómo estaba un pedido ayer a las 10:00
-- SELECT * FROM ventas.pedido FOR SYSTEM_TIME AS OF '2026-10-15T10:00:00' WHERE id = 1001;
