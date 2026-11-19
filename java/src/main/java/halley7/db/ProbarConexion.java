package halley7.db;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Programa pequeño para comprobar la conexión y ver cuántas filas tiene cada tabla.
 * Ejecutar desde la carpeta java/ (ver instrucciones).
 */
public class ProbarConexion {

    // Nombres fijos escritos aquí (no vienen del usuario), por eso es seguro concatenarlos.
    private static final String[] TABLAS = {
        "modulo", "puerta", "persona", "persona_acceso", "fuente",
        "carga_evidencia", "evidencia_original", "registro_invalido", "correccion",
        "version_linea_tiempo", "evento_linea_tiempo", "investigador", "consulta",
        "respuesta", "respuesta_evidencia", "historial_respuesta", "alerta",
        "verificacion_integridad", "informe_caso"
    };

    public static void main(String[] args) {
        try (Connection conexion = ConexionBD.obtenerConexion();
             Statement st = conexion.createStatement()) {

            System.out.println("Conexión correcta a la base: " + conexion.getCatalog());
            System.out.println();
            for (String tabla : TABLAS) {
                try (ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM " + tabla)) {
                    rs.next();
                    System.out.printf("  %-26s %d filas%n", tabla, rs.getInt(1));
                }
            }
            try (ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM v_evidencia_alterada")) {
                rs.next();
                System.out.println();
                System.out.println("Registros de evidencia alterados: " + rs.getInt(1) + " (debe ser 0)");
            }
        } catch (SQLException | IllegalStateException e) {
            System.err.println("No se pudo conectar o consultar: " + e.getMessage());
            System.exit(1);
        }
    }
}