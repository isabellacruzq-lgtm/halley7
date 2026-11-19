package halley7.config;

import java.io.IOException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

/**
 * Lee config/config.properties (usuario y clave de MySQL, etc.).
 * Así las credenciales no quedan escritas dentro del código.
 */
public final class Configuracion {

    private final Properties propiedades = new Properties();

    private Configuracion(Path ruta) {
        try (Reader lector = Files.newBufferedReader(ruta, StandardCharsets.UTF_8)) {
            propiedades.load(lector);
        } catch (IOException e) {
            throw new IllegalStateException("No pude leer " + ruta + ": " + e.getMessage(), e);
        }
    }

    /**
     * Busca el archivo en este orden:
     *  1) la ruta indicada con -Dhalley7.config=...
     *  2) config/config.properties        (si ejecutas desde la raíz del proyecto)
     *  3) ../config/config.properties     (si ejecutas desde la carpeta java/)
     */
    public static Configuracion cargar() {
        String[] candidatos = {
            System.getProperty("halley7.config"),
            "config/config.properties",
            "../config/config.properties"
        };
        for (String candidato : candidatos) {
            if (candidato == null) continue;
            Path ruta = Path.of(candidato);
            if (Files.isRegularFile(ruta)) {
                return new Configuracion(ruta);
            }
        }
        throw new IllegalStateException(
            "No encontré config/config.properties. Copia config/config.properties.example "
          + "como config/config.properties y escribe tu usuario y clave de MySQL.");
    }

    /** Devuelve el valor de una clave; falla con un mensaje claro si falta. */
    public String obtener(String clave) {
        String valor = propiedades.getProperty(clave);
        if (valor == null || valor.isBlank()) {
            throw new IllegalStateException("Falta la clave '" + clave + "' en config.properties");
        }
        return valor.trim();
    }

    /** Devuelve el valor de una clave, o el valor por defecto si no existe. */
    public String obtener(String clave, String porDefecto) {
        String valor = propiedades.getProperty(clave);
        return (valor == null) ? porDefecto : valor.trim();
    }
}