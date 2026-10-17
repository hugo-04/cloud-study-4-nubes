-- PostgreSQL / Aurora PostgreSQL: usuario de aplicación con autenticación IAM y mínimo privilegio
CREATE USER app_iam WITH LOGIN;
GRANT rds_iam TO app_iam;
GRANT CONNECT ON DATABASE pedidos TO app_iam;
GRANT USAGE ON SCHEMA public TO app_iam;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_iam;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO app_iam;

-- Evita conexiones que se quedan con una transacción abierta
ALTER ROLE app_iam SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE app_iam SET statement_timeout = '15s';

-- Usuario de solo lectura para reportes (también con IAM)
CREATE USER reportes_iam WITH LOGIN;
GRANT rds_iam TO reportes_iam;
GRANT pg_read_all_data TO reportes_iam;

-- MySQL / Aurora MySQL (equivalente):
-- CREATE USER 'app_iam'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS' REQUIRE SSL;
-- GRANT SELECT, INSERT, UPDATE ON pedidos.* TO 'app_iam'@'%';

-- Tabla de ejemplo con versión para bloqueo optimista
CREATE TABLE IF NOT EXISTS pedido (
  id          uuid PRIMARY KEY,
  cliente_id  text        NOT NULL,
  total       numeric(12,2) NOT NULL CHECK (total >= 0),
  estado      text        NOT NULL,
  version     integer     NOT NULL DEFAULT 0,
  creado_en   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pedido_cliente_idx ON pedido (cliente_id, creado_en DESC);
