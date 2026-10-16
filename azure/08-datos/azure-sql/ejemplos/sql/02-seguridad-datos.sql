-- Azure SQL Database · protección de datos dentro de la base.
-- Requiere el esquema de 04-esquema-pedidos.sql (ventas.cliente, ventas.pedido).

-- 1) ENMASCARADO DINÁMICO: quien no tenga UNMASK ve valores enmascarados
--    (sintaxis oficial de T-SQL; algunos analizadores genéricos como sqlfluff no la reconocen)
ALTER TABLE ventas.cliente ALTER COLUMN correo ADD MASKED WITH (FUNCTION = 'email()');
ALTER TABLE ventas.cliente ALTER COLUMN telefono ADD MASKED WITH (FUNCTION = 'partial(0,"XXX-XXX-",3)');
-- Solo el servicio de atención puede ver los datos reales:
-- GRANT UNMASK TO [id-api-atencion];

-- 2) SEGURIDAD A NIVEL DE FILA (RLS) para multi-inquilino
CREATE SCHEMA seguridad;
GO

CREATE FUNCTION seguridad.fn_filtro_inquilino(@inquilino_id AS nvarchar(40))
    RETURNS TABLE
    WITH SCHEMABINDING
AS
    RETURN SELECT 1 AS permitido
    WHERE @inquilino_id = CAST(SESSION_CONTEXT(N'tenant_id') AS nvarchar(40));
GO

CREATE SECURITY POLICY seguridad.politica_inquilino
    ADD FILTER PREDICATE seguridad.fn_filtro_inquilino(inquilino_id) ON ventas.pedido,
    ADD BLOCK  PREDICATE seguridad.fn_filtro_inquilino(inquilino_id) ON ventas.pedido AFTER INSERT
    WITH (STATE = ON);
GO

-- La aplicación fija el inquilino al tomar la conexión (ver InquilinoDataSource en uso-en-java.md):
-- EXEC sp_set_session_context @key = N'tenant_id', @value = N'cliente-A', @read_only = 0;
-- SELECT * FROM ventas.pedido;     -- solo filas de cliente-A

-- 3) ALWAYS ENCRYPTED: el cifrado ocurre en el cliente (las claves no llegan al servidor).
--    Se configura con la herramienta del cliente (SSMS/Azure Data Studio) y la clave maestra en Key Vault;
--    el driver necesita "columnEncryptionSetting=Enabled" en la cadena de conexión.
--    No se crea con T-SQL puro porque requiere cifrar los datos existentes desde el cliente.

-- 4) AUDITORÍA a nivel de base (además de la del servidor)
-- CREATE DATABASE AUDIT SPECIFICATION ... (se gestiona mejor con Terraform/portal; ver terraform/main.tf)

-- 5) TABLA DE REGISTRO INMUTABLE (Ledger): sin UPDATE/DELETE posibles
CREATE TABLE ventas.libro_auditoria
(
    id          bigint IDENTITY(1, 1) PRIMARY KEY,
    usuario     nvarchar(128) NOT NULL DEFAULT SUSER_SNAME(),
    accion      nvarchar(100) NOT NULL,
    detalle     nvarchar(400) NULL,
    ocurrido_en datetime2     NOT NULL DEFAULT SYSUTCDATETIME()
)
WITH (LEDGER = ON (APPEND_ONLY = ON));
GO
