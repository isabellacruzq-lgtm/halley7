CREATE USER IF NOT EXISTS 'halley7_app'@'localhost' IDENTIFIED BY 'CambiaEstaClave_123';

-- Solo leer e insertar en toda la base...
GRANT SELECT, INSERT ON halley7.* TO 'halley7_app'@'localhost';
-- ...y actualizar únicamente las alertas (pendiente -> entregada)
GRANT UPDATE ON halley7.alerta TO 'halley7_app'@'localhost';

FLUSH PRIVILEGES;