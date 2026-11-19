SET NAMES utf8mb4;

DROP DATABASE IF EXISTS halley7;
CREATE DATABASE halley7
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE halley7;

-- =====================================================================
-- 1. DATOS DE REFERENCIA (de estacion.csv y personal.csv)
-- =====================================================================

CREATE TABLE modulo (
    codigo      VARCHAR(10) NOT NULL,
    nombre      VARCHAR(60) NOT NULL,
    es_exterior BOOLEAN     NOT NULL DEFAULT FALSE,
    PRIMARY KEY (codigo)
) ENGINE=InnoDB;

CREATE TABLE puerta (
    codigo                   VARCHAR(10) NOT NULL,
    modulo_1                 VARCHAR(10) NOT NULL,
    modulo_2                 VARCHAR(10) NOT NULL,
    tiene_lector             BOOLEAN     NOT NULL,
    -- Solo P8: palanca de emergencia que abre sin tarjeta y sin dejar registro
    tiene_palanca_emergencia BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Recorrer el pasillo entre dos módulos conectados toma 2 minutos
    minutos_recorrido        TINYINT     NOT NULL DEFAULT 2,
    PRIMARY KEY (codigo),
    CONSTRAINT fk_puerta_modulo1 FOREIGN KEY (modulo_1) REFERENCES modulo (codigo),
    CONSTRAINT fk_puerta_modulo2 FOREIGN KEY (modulo_2) REFERENCES modulo (codigo),
    CONSTRAINT ck_puerta_distintos CHECK (modulo_1 <> modulo_2)
) ENGINE=InnoDB;

CREATE TABLE persona (
    id_persona INT         NOT NULL AUTO_INCREMENT,
    tarjeta    VARCHAR(10) NOT NULL,
    nombre     VARCHAR(80) NOT NULL,
    cargo      VARCHAR(60) NOT NULL,
    PRIMARY KEY (id_persona),
    -- La persona y la tarjeta son cosas distintas (Petrov dice haber perdido
    -- la suya), por eso hay un id propio y la tarjeta es solo un dato único.
    UNIQUE KEY uq_persona_tarjeta (tarjeta)
) ENGINE=InnoDB;

CREATE TABLE persona_acceso (
    id_persona    INT         NOT NULL,
    codigo_puerta VARCHAR(10) NOT NULL,
    PRIMARY KEY (id_persona, codigo_puerta),
    CONSTRAINT fk_acceso_persona FOREIGN KEY (id_persona)    REFERENCES persona (id_persona),
    CONSTRAINT fk_acceso_puerta  FOREIGN KEY (codigo_puerta) REFERENCES puerta (codigo)
) ENGINE=InnoDB;

-- =====================================================================
-- 2. FUENTES Y EVIDENCIA ORIGINAL (C1, C3, C5)
-- =====================================================================

-- Las seis fuentes de evidencia (los dos archivos de referencia NO son fuentes)
CREATE TABLE fuente (
    id_fuente          INT          NOT NULL AUTO_INCREMENT,
    codigo             VARCHAR(20)  NOT NULL,
    nombre_archivo     VARCHAR(60)  NOT NULL,
    formato_archivo    VARCHAR(30)  NOT NULL,
    formato_hora       VARCHAR(120) NOT NULL,
    descripcion        VARCHAR(200) NOT NULL,
    -- ¿Sigue registrando durante un corte de energía?
    -- TRUE/FALSE según el enunciado; NULL = el enunciado no lo especifica.
    registra_sin_energia BOOLEAN    NULL,
    PRIMARY KEY (id_fuente),
    UNIQUE KEY uq_fuente_codigo (codigo)
) ENGINE=InnoDB;

-- Cada vez que se cargan archivos o llega una lectura en vivo
CREATE TABLE carga_evidencia (
    id_carga       INT          NOT NULL AUTO_INCREMENT,
    origen         ENUM('ARCHIVO','VIVO') NOT NULL,
    nombre_archivo VARCHAR(100) NULL,
    hash_archivo   CHAR(64)     NULL,   -- SHA-256 del archivo completo (si es archivo)
    fecha_carga    TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_carga),
    CONSTRAINT ck_carga_hash CHECK (hash_archivo IS NULL OR CHAR_LENGTH(hash_archivo) = 64)
) ENGINE=InnoDB;

-- Un registro = una línea de CSV, un mensaje de radio, un elemento de
-- "registros" en energia.json o una entrada de la bitácora.
-- El contenido se guarda EXACTAMENTE como llegó (con sus errores).
CREATE TABLE evidencia_original (
    id_evidencia    BIGINT       NOT NULL AUTO_INCREMENT,
    id_fuente       INT          NOT NULL,
    id_carga        INT          NOT NULL,
    numero_registro INT          NULL,      -- posición dentro del archivo; NULL si es en vivo
    contenido_crudo TEXT         NOT NULL,
    hash_sha256     CHAR(64)     NOT NULL,
    hash_previo     CHAR(64)     NOT NULL,
    hash_cadena     CHAR(64)     NOT NULL,
    fecha_recepcion TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_evidencia),
    UNIQUE KEY uq_evidencia_posicion (id_carga, numero_registro),
    KEY ix_evidencia_fuente (id_fuente),
    CONSTRAINT fk_evidencia_fuente FOREIGN KEY (id_fuente) REFERENCES fuente (id_fuente),
    CONSTRAINT fk_evidencia_carga  FOREIGN KEY (id_carga)  REFERENCES carga_evidencia (id_carga),
    CONSTRAINT ck_evidencia_hashes CHECK (
        CHAR_LENGTH(hash_sha256) = 64 AND CHAR_LENGTH(hash_previo) = 64 AND CHAR_LENGTH(hash_cadena) = 64)
) ENGINE=InnoDB;

-- Alias detectados por Haskell (una sola identidad por persona / módulo).
-- Empiezan vacías: solo se llenan con lo que aparezca en la evidencia.
CREATE TABLE alias_persona (
    id_alias           INT          NOT NULL AUTO_INCREMENT,
    alias              VARCHAR(80)  NOT NULL,
    id_persona         INT          NOT NULL,
    id_evidencia_origen BIGINT      NULL,
    nota               VARCHAR(255) NULL,
    PRIMARY KEY (id_alias),
    UNIQUE KEY uq_alias_persona (alias),
    CONSTRAINT fk_alias_persona   FOREIGN KEY (id_persona)          REFERENCES persona (id_persona),
    CONSTRAINT fk_alias_persona_e FOREIGN KEY (id_evidencia_origen) REFERENCES evidencia_original (id_evidencia)
) ENGINE=InnoDB;

CREATE TABLE alias_modulo (
    id_alias            INT          NOT NULL AUTO_INCREMENT,
    alias               VARCHAR(20)  NOT NULL,
    codigo_modulo       VARCHAR(10)  NOT NULL,
    id_evidencia_origen BIGINT       NULL,
    nota                VARCHAR(255) NULL,
    PRIMARY KEY (id_alias),
    UNIQUE KEY uq_alias_modulo (alias),
    CONSTRAINT fk_alias_modulo   FOREIGN KEY (codigo_modulo)       REFERENCES modulo (codigo),
    CONSTRAINT fk_alias_modulo_e FOREIGN KEY (id_evidencia_origen) REFERENCES evidencia_original (id_evidencia)
) ENGINE=InnoDB;

-- Problemas encontrados en las fuentes. El registro original NO se toca:
-- aquí queda el motivo por el que no se usó (o se usó normalizado).
CREATE TABLE registro_invalido (
    id_invalido              BIGINT       NOT NULL AUTO_INCREMENT,
    id_evidencia             BIGINT       NOT NULL,
    motivo                   ENUM('CORRUPTO','DUPLICADO','CONTRADICTORIO','ALIAS',
                                  'FORMATO_HORA','INCOMPLETO','OTRO') NOT NULL,
    detalle                  TEXT         NOT NULL,
    -- Registro con el que choca (el original del duplicado, el que contradice...)
    id_evidencia_relacionada BIGINT       NULL,
    -- FALSE = se descartó; TRUE = se usó después de normalizarlo (ej. un alias)
    se_uso_en_linea          BOOLEAN      NOT NULL DEFAULT FALSE,
    detectado_por            VARCHAR(30)  NOT NULL DEFAULT 'haskell',
    fecha_deteccion          TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_invalido),
    UNIQUE KEY uq_invalido (id_evidencia, motivo),
    CONSTRAINT fk_invalido_evidencia  FOREIGN KEY (id_evidencia)            REFERENCES evidencia_original (id_evidencia),
    CONSTRAINT fk_invalido_relacionada FOREIGN KEY (id_evidencia_relacionada) REFERENCES evidencia_original (id_evidencia)
) ENGINE=InnoDB;

-- =====================================================================
-- 3. CORRECCIONES (C5): siempre aparte, nunca sobre la original
-- =====================================================================

CREATE TABLE correccion (
    id_correccion      BIGINT       NOT NULL AUTO_INCREMENT,
    id_fuente          INT          NOT NULL,
    id_evidencia       BIGINT       NULL,   -- registro concreto; NULL si afecta a toda la fuente
    codigo_puerta      VARCHAR(10)  NULL,   -- ej.: reloj desfasado de un lector
    tipo_correccion    VARCHAR(30)  NOT NULL,   -- 'DESFASE_RELOJ', 'ALIAS', 'VALOR'...
    desfase_segundos   INT          NULL,
    valor_corregido    VARCHAR(255) NULL,
    agencia            VARCHAR(80)  NOT NULL,
    motivo             TEXT         NOT NULL,
    -- Texto exacto que Java usó para calcular el hash
    contenido_canonico TEXT         NOT NULL,
    hash_sha256        CHAR(64)     NOT NULL,
    hash_previo        CHAR(64)     NOT NULL,
    hash_cadena        CHAR(64)     NOT NULL,
    fecha_registro     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_correccion),
    CONSTRAINT fk_correccion_fuente    FOREIGN KEY (id_fuente)     REFERENCES fuente (id_fuente),
    CONSTRAINT fk_correccion_evidencia FOREIGN KEY (id_evidencia)  REFERENCES evidencia_original (id_evidencia),
    CONSTRAINT fk_correccion_puerta    FOREIGN KEY (codigo_puerta) REFERENCES puerta (codigo),
    CONSTRAINT ck_correccion_hashes CHECK (
        CHAR_LENGTH(hash_sha256) = 64 AND CHAR_LENGTH(hash_previo) = 64 AND CHAR_LENGTH(hash_cadena) = 64)
) ENGINE=InnoDB;

-- =====================================================================
-- 4. LÍNEA DE TIEMPO (C1)
-- =====================================================================

-- Una "versión" es una foto: qué evidencia (y en qué modo) se usó para
-- construir la línea. Cuando llega evidencia nueva se crea OTRA versión;
-- las anteriores no se tocan, así las respuestas viejas se pueden reconstruir.
CREATE TABLE version_linea_tiempo (
    id_version           INT          NOT NULL AUTO_INCREMENT,
    modo                 ENUM('ORIGINAL','CORREGIDA') NOT NULL,
    ultimo_id_evidencia  BIGINT       NOT NULL,   -- se usó la evidencia con id <= este
    ultimo_id_correccion BIGINT       NULL,       -- idem para correcciones (modo CORREGIDA)
    -- SHA-256( hash_cadena de la última evidencia + hash_cadena de la última
    -- corrección, o 64 ceros si no hay )
    hash_estado          CHAR(64)     NOT NULL,
    fecha_generacion     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_version),
    CONSTRAINT fk_version_evidencia  FOREIGN KEY (ultimo_id_evidencia)  REFERENCES evidencia_original (id_evidencia),
    CONSTRAINT fk_version_correccion FOREIGN KEY (ultimo_id_correccion) REFERENCES correccion (id_correccion),
    CONSTRAINT ck_version_hash CHECK (CHAR_LENGTH(hash_estado) = 64)
) ENGINE=InnoDB;

-- Cada evento unifica hora (UTC) e identidad. Si la hora no es exacta
-- (ej. presencia a las 01.30, solo al minuto) se guarda un intervalo.
CREATE TABLE evento_linea_tiempo (
    id_evento      BIGINT       NOT NULL AUTO_INCREMENT,
    id_version     INT          NOT NULL,
    id_evidencia   BIGINT       NOT NULL,
    instante_desde DATETIME     NOT NULL,
    instante_hasta DATETIME     NOT NULL,   -- igual a "desde" si la hora es exacta
    tipo_evento    VARCHAR(30)  NOT NULL,   -- TARJETA, RADIO, CORTE_ENERGIA, PRESENCIA...
    id_persona     INT          NULL,
    codigo_modulo  VARCHAR(10)  NULL,
    codigo_puerta  VARCHAR(10)  NULL,
    resultado      VARCHAR(20)  NULL,       -- OK / DENEGADO...
    valor          DECIMAL(10,2) NULL,      -- temperatura, personas, consumo...
    detalle        TEXT         NULL,
    PRIMARY KEY (id_evento),
    KEY ix_evento_version_hora (id_version, instante_desde),
    CONSTRAINT fk_evento_version   FOREIGN KEY (id_version)    REFERENCES version_linea_tiempo (id_version),
    CONSTRAINT fk_evento_evidencia FOREIGN KEY (id_evidencia)  REFERENCES evidencia_original (id_evidencia),
    CONSTRAINT fk_evento_persona   FOREIGN KEY (id_persona)    REFERENCES persona (id_persona),
    CONSTRAINT fk_evento_modulo    FOREIGN KEY (codigo_modulo) REFERENCES modulo (codigo),
    CONSTRAINT fk_evento_puerta    FOREIGN KEY (codigo_puerta) REFERENCES puerta (codigo),
    CONSTRAINT ck_evento_intervalo CHECK (instante_hasta >= instante_desde)
) ENGINE=InnoDB;

-- =====================================================================
-- 5. INVESTIGADORES, CONSULTAS Y RESPUESTAS (C2, C4)
-- =====================================================================

CREATE TABLE investigador (
    id_investigador INT          NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(80)  NOT NULL,
    agencia         VARCHAR(80)  NULL,
    PRIMARY KEY (id_investigador)
) ENGINE=InnoDB;

CREATE TABLE consulta (
    id_consulta     BIGINT       NOT NULL AUTO_INCREMENT,
    id_investigador INT          NOT NULL,
    tipo_consulta   VARCHAR(40)  NOT NULL,   -- ej. QUIEN_EN_MODULO, DONDE_PERSONA...
    parametros      JSON         NOT NULL,
    modo            ENUM('ORIGINAL','CORREGIDA') NOT NULL DEFAULT 'ORIGINAL',
    quiere_alerta   BOOLEAN      NOT NULL DEFAULT FALSE,
    fecha_consulta  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_consulta),
    KEY ix_consulta_investigador (id_investigador),
    CONSTRAINT fk_consulta_investigador FOREIGN KEY (id_investigador) REFERENCES investigador (id_investigador)
) ENGINE=InnoDB;

CREATE TABLE respuesta (
    id_respuesta    BIGINT       NOT NULL AUTO_INCREMENT,
    id_consulta     BIGINT       NOT NULL,
    id_version      INT          NOT NULL,   -- con qué foto de la evidencia se respondió
    -- SI / NO / NO_SE_PUEDE_SABER; LISTA para preguntas cuya respuesta es una lista
    veredicto       ENUM('SI','NO','NO_SE_PUEDE_SABER','LISTA') NOT NULL,
    contenido_json  TEXT         NOT NULL,   -- respuesta exacta que se mostró
    explicacion     TEXT         NOT NULL,
    hash_sha256     CHAR(64)     NOT NULL,   -- SHA-256 de contenido_json
    fecha_respuesta TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_respuesta),
    KEY ix_respuesta_consulta (id_consulta),
    CONSTRAINT fk_respuesta_consulta FOREIGN KEY (id_consulta) REFERENCES consulta (id_consulta),
    CONSTRAINT fk_respuesta_version  FOREIGN KEY (id_version)  REFERENCES version_linea_tiempo (id_version),
    CONSTRAINT ck_respuesta_hash CHECK (CHAR_LENGTH(hash_sha256) = 64)
) ENGINE=InnoDB;

-- Evidencia que sostiene (o contradice) cada respuesta
CREATE TABLE respuesta_evidencia (
    id_respuesta BIGINT       NOT NULL,
    id_evidencia BIGINT       NOT NULL,
    rol          ENUM('SOSTIENE','CONTRADICE','CONTEXTO') NOT NULL,
    nota         VARCHAR(255) NULL,
    PRIMARY KEY (id_respuesta, id_evidencia, rol),
    CONSTRAINT fk_re_respuesta FOREIGN KEY (id_respuesta) REFERENCES respuesta (id_respuesta),
    CONSTRAINT fk_re_evidencia FOREIGN KEY (id_evidencia) REFERENCES evidencia_original (id_evidencia)
) ENGINE=InnoDB;

-- Correcciones usadas por una respuesta en modo CORREGIDA
CREATE TABLE respuesta_correccion (
    id_respuesta  BIGINT NOT NULL,
    id_correccion BIGINT NOT NULL,
    PRIMARY KEY (id_respuesta, id_correccion),
    CONSTRAINT fk_rc_respuesta  FOREIGN KEY (id_respuesta)  REFERENCES respuesta (id_respuesta),
    CONSTRAINT fk_rc_correccion FOREIGN KEY (id_correccion) REFERENCES correccion (id_correccion)
) ENGINE=InnoDB;

-- Historial: cada vez que una consulta se responde de nuevo (llegó evidencia
-- nueva, hubo una corrección...) se agrega una fila; no se reescribe nada.
CREATE TABLE historial_respuesta (
    id_historial   BIGINT       NOT NULL AUTO_INCREMENT,
    id_consulta    BIGINT       NOT NULL,
    id_respuesta   BIGINT       NOT NULL,
    numero_version INT          NOT NULL,   -- 1, 2, 3... por consulta
    motivo         ENUM('INICIAL','NUEVA_EVIDENCIA','CORRECCION','REEVALUACION') NOT NULL,
    cambio_respecto_anterior BOOLEAN NOT NULL DEFAULT FALSE,
    fecha          TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id_historial),
    UNIQUE KEY uq_historial_version (id_consulta, numero_version),
    UNIQUE KEY uq_historial_respuesta (id_respuesta),
    CONSTRAINT fk_historial_consulta  FOREIGN KEY (id_consulta)  REFERENCES consulta (id_consulta),
    CONSTRAINT fk_historial_respuesta FOREIGN KEY (id_respuesta) REFERENCES respuesta (id_respuesta)
) ENGINE=InnoDB;

-- =====================================================================
-- 6. ALERTAS (C4) — esta tabla SÍ se puede actualizar (estado de entrega)
-- =====================================================================

CREATE TABLE alerta (
    id_alerta          BIGINT       NOT NULL AUTO_INCREMENT,
    id_consulta        BIGINT       NOT NULL,
    id_investigador    INT          NOT NULL,
    id_evidencia_nueva BIGINT       NOT NULL,
    id_respuesta_nueva BIGINT       NULL,
    mensaje            VARCHAR(300) NOT NULL,
    estado             ENUM('PENDIENTE','ENTREGADA') NOT NULL DEFAULT 'PENDIENTE',
    fecha_creacion     TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    fecha_entrega      TIMESTAMP(3) NULL,
    PRIMARY KEY (id_alerta),
    KEY ix_alerta_pendientes (id_investigador, estado),
    CONSTRAINT fk_alerta_consulta      FOREIGN KEY (id_consulta)        REFERENCES consulta (id_consulta),
    CONSTRAINT fk_alerta_investigador  FOREIGN KEY (id_investigador)    REFERENCES investigador (id_investigador),
    CONSTRAINT fk_alerta_evidencia     FOREIGN KEY (id_evidencia_nueva) REFERENCES evidencia_original (id_evidencia),
    CONSTRAINT fk_alerta_respuesta     FOREIGN KEY (id_respuesta_nueva) REFERENCES respuesta (id_respuesta)
) ENGINE=InnoDB;

-- =====================================================================
-- 7. INTEGRIDAD E INFORMES (C5, C6)
-- =====================================================================

CREATE TABLE verificacion_integridad (
    id_verificacion      INT          NOT NULL AUTO_INCREMENT,
    fecha_verificacion   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    alcance              ENUM('EVIDENCIA','CORRECCIONES','RESPUESTAS','TODO') NOT NULL,
    registros_revisados  INT          NOT NULL,
    resultado            ENUM('OK','ALTERADO') NOT NULL,
    primer_id_alterado   BIGINT       NULL,
    hash_cadena_final    CHAR(64)     NULL,
    detalle              TEXT         NULL,
    solicitado_por       VARCHAR(50)  NULL,
    PRIMARY KEY (id_verificacion)
) ENGINE=InnoDB;

CREATE TABLE informe_caso (
    id_informe       INT          NOT NULL AUTO_INCREMENT,
    id_version       INT          NOT NULL,
    fecha_generacion TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    ruta_archivo     VARCHAR(255) NOT NULL,
    hash_sha256      CHAR(64)     NOT NULL,   -- SHA-256 del archivo del informe
    PRIMARY KEY (id_informe),
    CONSTRAINT fk_informe_version FOREIGN KEY (id_version) REFERENCES version_linea_tiempo (id_version),
    CONSTRAINT ck_informe_hash CHECK (CHAR_LENGTH(hash_sha256) = 64)
) ENGINE=InnoDB;

-- =====================================================================
-- 8. DATOS INICIALES (solo lo que dice el PDF: estacion.csv y personal.csv)
-- =====================================================================

INSERT INTO modulo (codigo, nombre, es_exterior) VALUES
('COM',   'Comedor',                           FALSE),
('DOR',   'Dormitorios',                       FALSE),
('LAB-A', 'Laboratorio A',                     FALSE),
('LAB-B', 'Laboratorio B',                     FALSE),
('GEN',   'Generadores',                       FALSE),
('RAD',   'Sala de radio',                     FALSE),
('ALM',   'Almacén',                           FALSE),
('EXT',   'Exterior (la plataforma de hielo)', TRUE);

-- estacion.csv. Solo P8 tiene palanca de emergencia (según la sección 2 del PDF)
INSERT INTO puerta (codigo, modulo_1, modulo_2, tiene_lector, tiene_palanca_emergencia) VALUES
('P1', 'COM',   'DOR',   FALSE, FALSE),
('P2', 'DOR',   'LAB-A', TRUE,  FALSE),
('P3', 'LAB-A', 'LAB-B', TRUE,  FALSE),
('P4', 'LAB-B', 'GEN',   TRUE,  FALSE),
('P5', 'GEN',   'RAD',   TRUE,  FALSE),
('P6', 'RAD',   'COM',   FALSE, FALSE),
('P7', 'GEN',   'ALM',   TRUE,  FALSE),
('P8', 'ALM',   'EXT',   TRUE,  TRUE);

-- personal.csv (la tarjeta de Irene es IV-07, tal como está en el original)
INSERT INTO persona (id_persona, tarjeta, nombre, cargo) VALUES
(1, 'JS-01', 'Tomás Okafor',    'Jefe de estación'),
(2, 'DV-02', 'Daniel Vidal',    'Médico'),
(3, 'MR-03', 'Marta Ruiz',      'Ingeniera eléctrica'),
(4, 'LP-04', 'Lucas Petrov',    'Radiooperador'),
(5, 'AK-05', 'Aiko Kimura',     'Bióloga'),
(6, 'IV-07', 'Irene Valcárcel', 'Glacióloga');

-- Columna "accesos" de personal.csv, una fila por persona y puerta
INSERT INTO persona_acceso (id_persona, codigo_puerta) VALUES
(1,'P2'),(1,'P3'),(1,'P4'),(1,'P5'),(1,'P7'),(1,'P8'),   -- Okafor
(2,'P2'),(2,'P3'),                                         -- Vidal
(3,'P2'),(3,'P4'),(3,'P5'),(3,'P7'),                       -- Ruiz
(4,'P2'),(4,'P5'),(4,'P7'),                                -- Petrov
(5,'P2'),(5,'P3'),                                         -- Kimura
(6,'P2'),(6,'P3'),(6,'P4');                                -- Valcárcel

-- Las seis fuentes de evidencia (secciones 2 y 3 del PDF).
-- registra_sin_energia: tarjetas y presencia dejan de funcionar sin energía;
-- temperatura y radio tienen batería propia; para las demás el PDF no lo dice.
INSERT INTO fuente (codigo, nombre_archivo, formato_archivo, formato_hora, descripcion, registra_sin_energia) VALUES
('tarjetas',    'tarjetas.csv',    'CSV',              'ISO 8601 al segundo (ej. 2041-06-14T00:12:04)',      'Cada uso de tarjeta en una puerta con lector',                   FALSE),
('radio',       'radio.txt',       'TXT',              '[HH:MM] al minuto; la fecha está solo en el encabezado', 'Transcripción automática de la consola de radio',             TRUE),
('energia',     'energia.json',    'JSON',             'ISO 8601 al segundo',                                'Lecturas de consumo eléctrico y eventos de corte',               NULL),
('presencia',   'presencia.csv',   'CSV (separador ;)', 'HH.MM al minuto, sin fecha',                         'Número de personas por módulo',                                  FALSE),
('temperatura', 'temperatura.csv', 'CSV',              'Epoch en segundos',                                  'Temperatura del almacén y del exterior',                         TRUE),
('bitacora',    'bitacora.txt',    'TXT',              'dd/mm y hora aproximada escrita en el texto',        'Bitácora manuscrita del jefe de estación, digitalizada',         NULL);

-- =====================================================================
-- 9. VISTAS
-- =====================================================================

-- Línea de tiempo legible (nombres en vez de ids)
CREATE VIEW v_linea_tiempo AS
SELECT ev.id_version, v.modo, ev.instante_desde, ev.instante_hasta, ev.tipo_evento,
       p.nombre AS persona, ev.codigo_modulo, ev.codigo_puerta, ev.resultado,
       ev.valor, ev.detalle, ev.id_evidencia
FROM evento_linea_tiempo ev
JOIN version_linea_tiempo v ON v.id_version = ev.id_version
LEFT JOIN persona p ON p.id_persona = ev.id_persona;

-- Verificación de integridad: si devuelven filas, ALGO FUE ALTERADO.
-- (Vacías = todo en orden.) Recalculan los hashes y revisan la cadena.
CREATE VIEW v_evidencia_alterada AS
SELECT t.id_evidencia,
       CASE
         WHEN t.hash_sha256 <> SHA2(t.contenido_crudo, 256)                      THEN 'CONTENIDO_ALTERADO'
         WHEN t.hash_cadena <> SHA2(CONCAT(t.hash_previo, t.hash_sha256), 256)  THEN 'CADENA_ROTA'
         ELSE 'ENLACE_INCORRECTO'
       END AS problema
FROM (SELECT e.id_evidencia, e.contenido_crudo, e.hash_sha256, e.hash_previo, e.hash_cadena,
             LAG(e.hash_cadena) OVER (ORDER BY e.id_evidencia) AS hash_anterior_real
      FROM evidencia_original e) AS t
WHERE t.hash_sha256 <> SHA2(t.contenido_crudo, 256)
   OR t.hash_cadena <> SHA2(CONCAT(t.hash_previo, t.hash_sha256), 256)
   OR t.hash_previo <> COALESCE(t.hash_anterior_real, REPEAT('0', 64));

CREATE VIEW v_correccion_alterada AS
SELECT t.id_correccion,
       CASE
         WHEN t.hash_sha256 <> SHA2(t.contenido_canonico, 256)                   THEN 'CONTENIDO_ALTERADO'
         WHEN t.hash_cadena <> SHA2(CONCAT(t.hash_previo, t.hash_sha256), 256)  THEN 'CADENA_ROTA'
         ELSE 'ENLACE_INCORRECTO'
       END AS problema
FROM (SELECT c.id_correccion, c.contenido_canonico, c.hash_sha256, c.hash_previo, c.hash_cadena,
             LAG(c.hash_cadena) OVER (ORDER BY c.id_correccion) AS hash_anterior_real
      FROM correccion c) AS t
WHERE t.hash_sha256 <> SHA2(t.contenido_canonico, 256)
   OR t.hash_cadena <> SHA2(CONCAT(t.hash_previo, t.hash_sha256), 256)
   OR t.hash_previo <> COALESCE(t.hash_anterior_real, REPEAT('0', 64));

CREATE VIEW v_respuesta_alterada AS
SELECT r.id_respuesta, 'CONTENIDO_ALTERADO' AS problema
FROM respuesta r
WHERE r.hash_sha256 <> SHA2(r.contenido_json, 256);

-- =====================================================================
-- 10. TRIGGERS DE INMUTABILIDAD
-- Bloquean UPDATE y DELETE en las tablas de evidencia, correcciones,
-- línea de tiempo y respuestas (solo se puede INSERTAR).
-- Nota: un administrador con permisos totales podría borrar los triggers;
-- para eso existen los hashes + las vistas v_*_alterada, y el usuario de
-- aplicación limitado de db/usuario_app.sql.
-- =====================================================================

-- Los 3 triggers siguientes verifican el hash al insertar (necesitan DELIMITER)
DELIMITER $$

CREATE TRIGGER trg_evidencia_original_verifica_hash
BEFORE INSERT ON evidencia_original FOR EACH ROW
BEGIN
    IF NEW.hash_sha256 <> SHA2(NEW.contenido_crudo, 256) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Hash SHA-256 no coincide con el contenido de la evidencia';
    END IF;
    IF NEW.hash_cadena <> SHA2(CONCAT(NEW.hash_previo, NEW.hash_sha256), 256) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cadena de hashes de la evidencia es incorrecta';
    END IF;
END$$

CREATE TRIGGER trg_correccion_verifica_hash
BEFORE INSERT ON correccion FOR EACH ROW
BEGIN
    IF NEW.hash_sha256 <> SHA2(NEW.contenido_canonico, 256) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Hash SHA-256 no coincide con el contenido de la correccion';
    END IF;
    IF NEW.hash_cadena <> SHA2(CONCAT(NEW.hash_previo, NEW.hash_sha256), 256) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La cadena de hashes de la correccion es incorrecta';
    END IF;
END$$

CREATE TRIGGER trg_respuesta_verifica_hash
BEFORE INSERT ON respuesta FOR EACH ROW
BEGIN
    IF NEW.hash_sha256 <> SHA2(NEW.contenido_json, 256) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Hash SHA-256 no coincide con el contenido de la respuesta';
    END IF;
END$$

DELIMITER ;

-- Bloqueo de UPDATE / DELETE (cada trigger es una sola instrucción)
CREATE TRIGGER trg_carga_evidencia_no_update BEFORE UPDATE ON carga_evidencia FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en carga_evidencia';
CREATE TRIGGER trg_carga_evidencia_no_delete BEFORE DELETE ON carga_evidencia FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en carga_evidencia';

CREATE TRIGGER trg_evidencia_original_no_update BEFORE UPDATE ON evidencia_original FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en evidencia_original';
CREATE TRIGGER trg_evidencia_original_no_delete BEFORE DELETE ON evidencia_original FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en evidencia_original';

CREATE TRIGGER trg_registro_invalido_no_update BEFORE UPDATE ON registro_invalido FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en registro_invalido';
CREATE TRIGGER trg_registro_invalido_no_delete BEFORE DELETE ON registro_invalido FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en registro_invalido';

CREATE TRIGGER trg_correccion_no_update BEFORE UPDATE ON correccion FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en correccion';
CREATE TRIGGER trg_correccion_no_delete BEFORE DELETE ON correccion FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en correccion';

CREATE TRIGGER trg_version_linea_no_update BEFORE UPDATE ON version_linea_tiempo FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en version_linea_tiempo';
CREATE TRIGGER trg_version_linea_no_delete BEFORE DELETE ON version_linea_tiempo FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en version_linea_tiempo';

CREATE TRIGGER trg_evento_linea_no_update BEFORE UPDATE ON evento_linea_tiempo FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en evento_linea_tiempo';
CREATE TRIGGER trg_evento_linea_no_delete BEFORE DELETE ON evento_linea_tiempo FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en evento_linea_tiempo';

CREATE TRIGGER trg_consulta_no_update BEFORE UPDATE ON consulta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en consulta';
CREATE TRIGGER trg_consulta_no_delete BEFORE DELETE ON consulta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en consulta';

CREATE TRIGGER trg_respuesta_no_update BEFORE UPDATE ON respuesta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en respuesta';
CREATE TRIGGER trg_respuesta_no_delete BEFORE DELETE ON respuesta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en respuesta';

CREATE TRIGGER trg_respuesta_evidencia_no_update BEFORE UPDATE ON respuesta_evidencia FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en respuesta_evidencia';
CREATE TRIGGER trg_respuesta_evidencia_no_delete BEFORE DELETE ON respuesta_evidencia FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en respuesta_evidencia';

CREATE TRIGGER trg_respuesta_correccion_no_update BEFORE UPDATE ON respuesta_correccion FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en respuesta_correccion';
CREATE TRIGGER trg_respuesta_correccion_no_delete BEFORE DELETE ON respuesta_correccion FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en respuesta_correccion';

CREATE TRIGGER trg_historial_respuesta_no_update BEFORE UPDATE ON historial_respuesta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en historial_respuesta';
CREATE TRIGGER trg_historial_respuesta_no_delete BEFORE DELETE ON historial_respuesta FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en historial_respuesta';

CREATE TRIGGER trg_verificacion_no_update BEFORE UPDATE ON verificacion_integridad FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en verificacion_integridad';
CREATE TRIGGER trg_verificacion_no_delete BEFORE DELETE ON verificacion_integridad FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en verificacion_integridad';

CREATE TRIGGER trg_informe_caso_no_update BEFORE UPDATE ON informe_caso FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite UPDATE en informe_caso';
CREATE TRIGGER trg_informe_caso_no_delete BEFORE DELETE ON informe_caso FOR EACH ROW
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tabla inmutable: no se permite DELETE en informe_caso';