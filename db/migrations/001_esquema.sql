
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- Dominio para CUITs 
CREATE DOMAIN cuit_dom AS VARCHAR(11);

-- Tipo enumerado para el estado de los movimientos
CREATE TYPE estado_enum AS ENUM (
    'en_confeccion',
    'terminado',
    'procesado'
);

-- Tipo enumerado para los dias de la semana
CREATE TYPE dia_semana_enum AS ENUM (
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
);

--- GEOGRÁFICAS 

CREATE TABLE provincia (
    id_provincia INTEGER,
    nombre VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_provincia)
);

CREATE TABLE departamento (
    id_departamento INTEGER,
    id_provincia INTEGER NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_departamento),
    CONSTRAINT fk_depto_provincia FOREIGN KEY (id_provincia) REFERENCES provincia(id_provincia) ON DELETE RESTRICT
);

CREATE TABLE localidad (
    cp INTEGER,
    nombre VARCHAR(150) NOT NULL,
    id_provincia INTEGER NOT NULL,
    cuit_encargado_regional cuit_dom,
    PRIMARY KEY (cp),
    CONSTRAINT fk_loc_provincia FOREIGN KEY (id_provincia) REFERENCES provincia(id_provincia) ON DELETE RESTRICT
);

--- ENTIDADES MAESTRAS Y CATÁLOGOS 

CREATE TABLE sala_venta (
    id_sala INTEGER,
    cp_localidad INTEGER NOT NULL,
    calle VARCHAR(150) NOT NULL,
    numero INTEGER NOT NULL,
    dia_cierre dia_semana_enum NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_sala),
    CONSTRAINT fk_sala_loc FOREIGN KEY (cp_localidad) REFERENCES localidad(cp) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE empleado (
    cuit cuit_dom,
    id_sala INTEGER NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    fecha_ingreso DATE NOT NULL,
    salario NUMERIC(12,2) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (cuit),
    CONSTRAINT fk_emp_sala FOREIGN KEY (id_sala) REFERENCES sala_venta(id_sala) ON DELETE RESTRICT
);

ALTER TABLE localidad 
    ADD CONSTRAINT fk_loc_empleado FOREIGN KEY (cuit_encargado_regional) REFERENCES empleado(cuit) ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE transportista (
    cod_transportista SERIAL PRIMARY KEY,
    razon_social VARCHAR(150) NOT NULL,
    cuit cuit_dom NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(50) NOT NULL,
    domicilio VARCHAR(200) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE cepa (
    id_cepa SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(50) NOT NULL
);

CREATE TABLE finca (
    id_finca SERIAL PRIMARY KEY,
    id_departamento INTEGER NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    superficie NUMERIC(10,2) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_finca_depto FOREIGN KEY (id_departamento) REFERENCES departamento(id_departamento) ON DELETE RESTRICT
);

CREATE TABLE parcela (
    id_finca INTEGER,
    nro_parcela INTEGER,
    id_cepa INTEGER NOT NULL,
    superficie NUMERIC(10,2) NOT NULL,
    anio_plantacion INTEGER NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_finca, nro_parcela),
    CONSTRAINT fk_parcela_finca FOREIGN KEY (id_finca) REFERENCES finca(id_finca) ON DELETE CASCADE,
    CONSTRAINT fk_parcela_cepa FOREIGN KEY (id_cepa) REFERENCES cepa(id_cepa) ON DELETE RESTRICT
);

CREATE TABLE bodega (
    cuit_bodega cuit_dom,
    razon_social VARCHAR(150) NOT NULL,
    domicilio VARCHAR(200) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (cuit_bodega)
);

--- PRODUCCIÓN Y PRODUCTOS 

CREATE TABLE lote_uva (
    nro_lote SERIAL PRIMARY KEY,
    id_finca INTEGER NOT NULL,
    nro_parcela INTEGER NOT NULL,
    cuit_bodega cuit_dom NOT NULL,
    campania INTEGER NOT NULL,
    fecha DATE NOT NULL,
    kg NUMERIC(12,2) NOT NULL,
    CONSTRAINT fk_lote_parcela FOREIGN KEY (id_finca, nro_parcela) REFERENCES parcela(id_finca, nro_parcela) ON DELETE RESTRICT,
    CONSTRAINT fk_lote_bodega FOREIGN KEY (cuit_bodega) REFERENCES bodega(cuit_bodega) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE analisis_calidad (
    id_analisis SERIAL PRIMARY KEY,
    nro_lote INTEGER NOT NULL,
    fecha DATE NOT NULL,
    brix NUMERIC(5,2) NOT NULL,
    ph NUMERIC(4,2) NOT NULL,
    acidez NUMERIC(5,2) NOT NULL,
    CONSTRAINT fk_anal_lote FOREIGN KEY (nro_lote) REFERENCES lote_uva(nro_lote) ON DELETE RESTRICT
);

CREATE TABLE vino (
    cod_vino SERIAL PRIMARY KEY,
    cuit_bodega cuit_dom NOT NULL,
    nombre VARCHAR(150) NOT NULL,
    tipo VARCHAR(50) NOT NULL,
    aniada INTEGER NOT NULL,
    volumen NUMERIC(8,2) NOT NULL,
    graduacion NUMERIC(4,2) NOT NULL,
    precio NUMERIC(12,2) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_vino_bodega FOREIGN KEY (cuit_bodega) REFERENCES bodega(cuit_bodega) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE maridaje (
    id_maridaje SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    temp_servicio INTEGER NOT NULL
);

--- TABLAS DE RUPTURA

CREATE TABLE composicion (
    cod_vino INTEGER,
    id_cepa INTEGER,
    porcentaje NUMERIC(5,2) NOT NULL,
    PRIMARY KEY (cod_vino, id_cepa),
    CONSTRAINT fk_comp_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE CASCADE,
    CONSTRAINT fk_comp_cepa FOREIGN KEY (id_cepa) REFERENCES cepa(id_cepa) ON DELETE RESTRICT
);

CREATE TABLE vino_maridaje (
    cod_vino INTEGER,
    id_maridaje INTEGER,
    PRIMARY KEY (cod_vino, id_maridaje),
    CONSTRAINT fk_vm_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE CASCADE,
    CONSTRAINT fk_vm_maridaje FOREIGN KEY (id_maridaje) REFERENCES maridaje(id_maridaje) ON DELETE CASCADE
);

CREATE TABLE transportista_cubre_localidad (
    cod_transportista INTEGER,
    cp_localidad INTEGER,
    PRIMARY KEY (cod_transportista, cp_localidad),
    CONSTRAINT fk_tcl_transp FOREIGN KEY (cod_transportista) REFERENCES transportista(cod_transportista) ON DELETE CASCADE,
    CONSTRAINT fk_tcl_loc FOREIGN KEY (cp_localidad) REFERENCES localidad(cp) ON DELETE CASCADE
);

--- JERARQUÍA DE CLIENTES 

CREATE TABLE cliente (
    id_cliente SERIAL PRIMARY KEY,
    cp_localidad INTEGER NOT NULL,
    nombre_razon_social VARCHAR(150) NOT NULL,
    tipo_doc VARCHAR(20) NOT NULL,
    nro_doc VARCHAR(50) NOT NULL,
    direccion VARCHAR(200) NOT NULL,
    fecha_alta DATE NOT NULL,
    descuento NUMERIC(5,2) NOT NULL,
    tipo_cliente VARCHAR(50) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_cliente_loc FOREIGN KEY (cp_localidad) REFERENCES localidad(cp) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE distribuidor (
    id_cliente INTEGER,
    zona_cobertura VARCHAR(150) NOT NULL,
    nro_habilitacion VARCHAR(50) NOT NULL,
    PRIMARY KEY (id_cliente),
    CONSTRAINT fk_dist_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE CASCADE
);

CREATE TABLE exportador (
    id_cliente INTEGER,
    pais_destino VARCHAR(100) NOT NULL,
    PRIMARY KEY (id_cliente),
    CONSTRAINT fk_exp_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE CASCADE
);

CREATE TABLE permiso_exportacion (
    cod_permiso SERIAL PRIMARY KEY,
    id_cliente INTEGER NOT NULL,
    fecha_emision DATE NOT NULL,
    fecha_vencimiento DATE NOT NULL,
    CONSTRAINT fk_perm_exp FOREIGN KEY (id_cliente) REFERENCES exportador(id_cliente) ON DELETE CASCADE
);

--- COMPROBANTES Y MOVIMIENTOS 

CREATE TABLE comprobante (
    nro_comprobante SERIAL PRIMARY KEY,
    id_cliente INTEGER NOT NULL,
    id_sala INTEGER NOT NULL,
    fecha TIMESTAMP NOT NULL,
    subtotal NUMERIC(12,2) NOT NULL,
    descuento NUMERIC(12,2) NOT NULL,
    total NUMERIC(12,2) NOT NULL,
    CONSTRAINT fk_comp_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente) ON DELETE RESTRICT,
    CONSTRAINT fk_comp_sala FOREIGN KEY (id_sala) REFERENCES sala_venta(id_sala) ON DELETE RESTRICT
);

CREATE TABLE renglon_comprobante (
    nro_comprobante INTEGER,
    cod_vino INTEGER,
    cantidad INTEGER NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    descuento NUMERIC(12,2) NOT NULL,
    subtotal NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (nro_comprobante, cod_vino),
    CONSTRAINT fk_rcomp_comp FOREIGN KEY (nro_comprobante) REFERENCES comprobante(nro_comprobante) ON DELETE CASCADE,
    CONSTRAINT fk_rcomp_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE RESTRICT
);

CREATE TABLE ingreso (
    cod_ingreso SERIAL PRIMARY KEY,
    cod_transportista INTEGER NOT NULL,
    cuit_bodega cuit_dom NOT NULL,
    fecha TIMESTAMP NOT NULL,
    estado estado_enum NOT NULL,
    CONSTRAINT fk_ing_transp FOREIGN KEY (cod_transportista) REFERENCES transportista(cod_transportista) ON DELETE RESTRICT,
    CONSTRAINT fk_ing_bodega FOREIGN KEY (cuit_bodega) REFERENCES bodega(cuit_bodega) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE renglon_ingreso (
    cod_ingreso INTEGER,
    cod_vino INTEGER,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (cod_ingreso, cod_vino),
    CONSTRAINT fk_ring_ing FOREIGN KEY (cod_ingreso) REFERENCES ingreso(cod_ingreso) ON DELETE CASCADE,
    CONSTRAINT fk_ring_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE RESTRICT
);

CREATE TABLE transferencia (
    nro_transferencia SERIAL PRIMARY KEY,
    id_sala INTEGER NOT NULL,
    fecha_confeccion DATE NOT NULL,
    estado estado_enum NOT NULL,
    CONSTRAINT fk_transf_sala FOREIGN KEY (id_sala) REFERENCES sala_venta(id_sala) ON DELETE RESTRICT
);

CREATE TABLE renglon_transferencia (
    nro_transferencia INTEGER,
    cod_vino INTEGER,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (nro_transferencia, cod_vino),
    CONSTRAINT fk_rtransf_transf FOREIGN KEY (nro_transferencia) REFERENCES transferencia(nro_transferencia) ON DELETE CASCADE,
    CONSTRAINT fk_rtransf_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE RESTRICT
);

--- STOCK Y AUDITORÍA

CREATE TABLE stock_sala (
    id_sala INTEGER,
    cod_vino INTEGER,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_sala, cod_vino),
    CONSTRAINT fk_ssala_sala FOREIGN KEY (id_sala) REFERENCES sala_venta(id_sala) ON DELETE RESTRICT,
    CONSTRAINT fk_ssala_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE RESTRICT
);

CREATE TABLE stock_deposito (
    cod_vino INTEGER,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (cod_vino),
    CONSTRAINT fk_sdep_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE RESTRICT
);

CREATE TABLE auditoria_precio (
    id_auditoria SERIAL PRIMARY KEY,
    cod_vino INTEGER NOT NULL,
    precio_anterior NUMERIC(12,2) NOT NULL,
    precio_nuevo NUMERIC(12,2) NOT NULL,
    fecha_hora TIMESTAMP NOT NULL,
    usuario VARCHAR(100) NOT NULL,
    CONSTRAINT fk_aud_vino FOREIGN KEY (cod_vino) REFERENCES vino(cod_vino) ON DELETE CASCADE
);
