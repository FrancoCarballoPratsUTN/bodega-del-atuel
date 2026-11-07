-- Roles y privilegios mínimos.
--
-- Los secretos se inyectan por entorno y nunca se versionan.
-- Este archivo requiere psql porque usa los meta-comandos \getenv y \if.
--
-- Variables requeridas:
--   BDA_OWNER_PASSWORD      -> propietario_base_datos
--   BDA_DATABASE_PASSWORD   -> rol_api_lectura_escritura
--   BDA_REPORTES_PASSWORD   -> rol_reportes_solo_lectura

\set ON_ERROR_STOP on

\getenv owner_password BDA_OWNER_PASSWORD
\getenv database_password BDA_DATABASE_PASSWORD
\getenv reportes_password BDA_REPORTES_PASSWORD

\if :{?owner_password}
\else
    \warn 'Falta la variable de entorno BDA_OWNER_PASSWORD'
    SELECT 1 / 0 AS falta_bda_owner_password;
\endif

\if :{?database_password}
\else
    \warn 'Falta la variable de entorno BDA_DATABASE_PASSWORD'
    SELECT 1 / 0 AS falta_bda_database_password;
\endif

\if :{?reportes_password}
\else
    \warn 'Falta la variable de entorno BDA_REPORTES_PASSWORD'
    SELECT 1 / 0 AS falta_bda_reportes_password;
\endif

-- Revocar privilegios por defecto otorgados al rol PUBLIC.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

-- Rol 1: propietario de la base de datos.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'propietario_base_datos') THEN
        CREATE ROLE propietario_base_datos LOGIN;
    END IF;
END
$$;

ALTER ROLE propietario_base_datos WITH LOGIN PASSWORD :'owner_password';

GRANT ALL PRIVILEGES ON SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO propietario_base_datos;

-- Rol 2: API lectura y escritura (DML del backend).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_api_lectura_escritura') THEN
        CREATE ROLE rol_api_lectura_escritura LOGIN;
    END IF;
END
$$;

ALTER ROLE rol_api_lectura_escritura WITH LOGIN PASSWORD :'database_password';

GRANT USAGE ON SCHEMA public TO rol_api_lectura_escritura;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO rol_api_lectura_escritura;

-- Rol 3: reportes de solo lectura (consultas analíticas y exportación).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_reportes_solo_lectura') THEN
        CREATE ROLE rol_reportes_solo_lectura LOGIN;
    END IF;
END
$$;

ALTER ROLE rol_reportes_solo_lectura WITH LOGIN PASSWORD :'reportes_password';

GRANT USAGE ON SCHEMA public TO rol_reportes_solo_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_reportes_solo_lectura;

-- Privilegios automáticos para objetos futuros.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON ROUTINES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO rol_reportes_solo_lectura;
