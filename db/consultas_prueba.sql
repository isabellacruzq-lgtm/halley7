USE halley7;

-- 1) Tablas y vistas creadas (esperado: 22 tablas y 4 vistas)
SHOW FULL TABLES;

-- 2) Datos de referencia
--    Esperado: modulo=8, puerta=8, persona=6, persona_acceso=20, fuente=6
SELECT 'modulo' AS tabla, COUNT(*) AS filas FROM modulo
UNION ALL SELECT 'puerta',         COUNT(*) FROM puerta
UNION ALL SELECT 'persona',        COUNT(*) FROM persona
UNION ALL SELECT 'persona_acceso', COUNT(*) FROM persona_acceso
UNION ALL SELECT 'fuente',         COUNT(*) FROM fuente;

-- 3) Puertas con sus módulos (P1 y P6 sin lector; P8 con palanca de emergencia)
SELECT p.codigo AS puerta, m1.nombre AS desde, m2.nombre AS hasta,
       IF(p.tiene_lector, 'sí', 'no') AS lector,
       IF(p.tiene_palanca_emergencia, 'sí', 'no') AS palanca
FROM puerta p
JOIN modulo m1 ON m1.codigo = p.modulo_1
JOIN modulo m2 ON m2.codigo = p.modulo_2
ORDER BY p.codigo;

-- 4) Accesos por persona (deben coincidir con personal.csv)
SELECT pe.tarjeta, pe.nombre, pe.cargo,
       GROUP_CONCAT(pa.codigo_puerta ORDER BY pa.codigo_puerta SEPARATOR ' ') AS accesos
FROM persona pe
JOIN persona_acceso pa ON pa.id_persona = pe.id_persona
GROUP BY pe.id_persona, pe.tarjeta, pe.nombre, pe.cargo
ORDER BY pe.id_persona;

-- 5) ¿Quién tiene acceso a P4? Esperado: Okafor, Ruiz y Valcárcel
--    (Vidal no: por eso su intento de las 02:40 aparece DENEGADO)
SELECT pe.nombre
FROM persona pe
JOIN persona_acceso pa ON pa.id_persona = pe.id_persona
WHERE pa.codigo_puerta = 'P4';

-- 6) Fuentes y si registran durante un corte de energía (NULL = no especificado)
SELECT codigo, nombre_archivo, formato_hora, registra_sin_energia FROM fuente;

-- 7) Triggers de inmutabilidad (esperado: 29 filas)
SELECT trigger_name, event_object_table, action_timing, event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'halley7'
ORDER BY event_object_table, event_manipulation;

-- 8) SHA-256 en MySQL. Resultado esperado para 'abc':
--    ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
SELECT SHA2('abc', 256) AS sha256_de_abc;

-- 9) Verificación de integridad. Las tres consultas deben devolver 0 filas.
SELECT * FROM v_evidencia_alterada;
SELECT * FROM v_correccion_alterada;
SELECT * FROM v_respuesta_alterada;

-- 10) Prueba MANUAL de inmutabilidad. Ejecuta UNA instrucción a la vez, en orden.
--     Todo se deshace con el ROLLBACK final, no queda nada guardado
--     (el contador AUTO_INCREMENT sí avanza; no importa).
START TRANSACTION;

INSERT INTO carga_evidencia (origen, nombre_archivo) VALUES ('ARCHIVO', 'prueba-manual');
SET @carga = LAST_INSERT_ID();
SET @txt = 'linea de prueba';

INSERT INTO evidencia_original
    (id_fuente, id_carga, numero_registro, contenido_crudo, hash_sha256, hash_previo, hash_cadena)
VALUES
    ((SELECT id_fuente FROM fuente WHERE codigo = 'tarjetas'), @carga, 1, @txt,
     SHA2(@txt, 256), REPEAT('0', 64), SHA2(CONCAT(REPEAT('0', 64), SHA2(@txt, 256)), 256));

-- Las dos siguientes DEBEN fallar con "Tabla inmutable..."
UPDATE evidencia_original SET contenido_crudo = 'otra cosa' WHERE id_evidencia = LAST_INSERT_ID();
DELETE FROM evidencia_original WHERE id_evidencia = LAST_INSERT_ID();

-- Esta DEBE fallar con "Hash SHA-256 no coincide..."
INSERT INTO evidencia_original
    (id_fuente, id_carga, numero_registro, contenido_crudo, hash_sha256, hash_previo, hash_cadena)
VALUES
    ((SELECT id_fuente FROM fuente WHERE codigo = 'tarjetas'), @carga, 2, 'texto',
     SHA2('otro texto', 256), REPEAT('0', 64), REPEAT('0', 64));

ROLLBACK;