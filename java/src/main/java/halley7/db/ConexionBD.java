package halley7.db;

import halley7.config.Configuracion;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Punto único para abrir conexiones JDBC a MySQL.
 * Cada llamada a obtenerConexion() devuelve una conexión NUEVA: quien la pide
 * debe cerrarla (try-with-resources). Cada hilo usa su propia conexión, lo que
 * sirve para las consultas simultáneas (C4) sin necesitar un pool todavía.
 */
public final class ConexionBD {

    // La estación funciona en UTC: forzamos UTC también en la conexión.
    // sslMode=DISABLED y allowPublicKeyRetrieval=true: solo para MySQL local.
    private static final String PARAMETROS =
        "useUnicode=true&characterEncoding=UTF-8"
      + "&connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true"
      + "&sslMode=DISABLED&allowPublicKeyRetrieval=true";

    private static Configuracion configuracion;

    private ConexionBD() { }

    private static synchronized Configuracion configuracion() {
        if (configuracion == null) {
            configuracion = Configuracion.cargar();
        }
        return configuracion;
    }

    public static Connection obtenerConexion() throws SQLException {
        Configuracion c = configuracion();
        String url = "jdbc:mysql://" + c.obtener("bd.host", "localhost")
                   + ":" + c.obtener("bd.puerto", "3306")
                   + "/" + c.obtener("bd.nombre", "halley7")
                   + "?" + PARAMETROS;
        return DriverManager.getConnection(url, c.obtener("bd.usuario"), c.obtener("bd.clave", ""));
    }
}