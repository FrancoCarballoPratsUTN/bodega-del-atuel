--Revocar privilegios por defecto otorgados al rol PUBLIC
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

--Rol 1: Propietario de la base de datos
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'propietario_base_datos') THEN
        CREATE ROLE propietario_base_datos LOGIN PASSWORD 'owner_password_secreta';
    END IF;
END
$$;

GRANT ALL PRIVILEGES ON SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO propietario_base_datos;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO propietario_base_datos;


--Rol 2: API Lectura y Escritura. Conexión del servidor de la API backend para operaciones DML.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_api_lectura_escritura') THEN
        CREATE ROLE rol_api_lectura_escritura LOGIN PASSWORD 'api_password_secreta';
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO rol_api_lectura_escritura;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_api_lectura_escritura;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO rol_api_lectura_escritura;

--Rol 3: Reportes Solo Lectura. Consultas analíticas, exportación de datos y vistas.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_reportes_solo_lectura') THEN
        CREATE ROLE rol_reportes_solo_lectura LOGIN PASSWORD 'reportes_password_secreta';
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO rol_reportes_solo_lectura;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_reportes_solo_lectura;

--Privilegios automáticos para objetos futuros
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT USAGE, SELECT ON SEQUENCES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT EXECUTE ON ROUTINES TO rol_api_lectura_escritura;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT ON TABLES TO rol_reportes_solo_lectura;