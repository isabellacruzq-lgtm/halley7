package halley7.db;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.junit.jupiter.api.Test;

/**
 * Requisitos: MySQL encendido, database.sql ya importado y config.properties listo.
 * Las pruebas que insertan datos lo hacen dentro de una transacción que se
 * deshace (rollback) al final: no queda ninguna evidencia de prueba guardada.
 */
class ConexionBDTest {

    private static final String CEROS = "0".repeat(64);

    // ---------- utilidades de las pruebas ----------

    private static String sha256(String texto) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] resumen = md.digest(texto.getBytes(StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        for (byte b : resumen) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    private static int contar(Connection c, String tabla) throws SQLException {
        try (Statement st = c.createStatement();
             ResultSet rs = st.executeQuery("SELECT COUNT(*) FROM " + tabla)) {
            rs.next();
            return rs.getInt(1);
        }
    }

    private static void ejecutar(Connection c, String sql) throws SQLException {
        try (Statement st = c.createStatement()) {
            st.executeUpdate(sql);
        }
    }

    private static long insertarCarga(Connection c) throws SQLException {
        String sql = "INSERT INTO carga_evidencia (origen, nombre_archivo) VALUES ('ARCHIVO', 'prueba-unitaria')";
        try (PreparedStatement ps = c.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }

    private static long insertarEvidencia(Connection c, long idCarga, String contenido,
                                          String hash, String hashCadena) throws SQLException {
        String sql = "INSERT INTO evidencia_original "
                   + "(id_fuente, id_carga, numero_registro, contenido_crudo, hash_sha256, hash_previo, hash_cadena) "
                   + "VALUES ((SELECT id_fuente FROM fuente WHERE codigo = 'tarjetas'), ?, 1, ?, ?, ?, ?)";
        try (PreparedStatement ps = c.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setLong(1, idCarga);
            ps.setString(2, contenido);
            ps.setString(3, hash);
            ps.setString(4, CEROS);
            ps.setString(5, hashCadena);
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                rs.next();
                return rs.getLong(1);
            }
        }
    }

    // ---------- pruebas ----------

    @Test
    void laConexionFunciona() throws Exception {
        try (Connection c = ConexionBD.obtenerConexion()) {
            assertTrue(c.isValid(2));
        }
    }

    @Test
    void losDatosDeReferenciaEstanCompletos() throws Exception {
        try (Connection c = ConexionBD.obtenerConexion()) {
            assertEquals(8, contar(c, "modulo"));
            assertEquals(8, contar(c, "puerta"));
            assertEquals(6, contar(c, "persona"));
            assertEquals(20, contar(c, "persona_acceso"));
            assertEquals(6, contar(c, "fuente"));
        }
    }

    @Test
    void laEvidenciaOriginalNoSePuedeModificarNiBorrar() throws Exception {
        try (Connection c = ConexionBD.obtenerConexion()) {
            c.setAutoCommit(false);
            try {
                long idCarga = insertarCarga(c);
                String contenido = "linea de prueba";
                String hash = sha256(contenido);
                long idEvidencia = insertarEvidencia(c, idCarga, contenido, hash, sha256(CEROS + hash));

                SQLException alActualizar = assertThrows(SQLException.class, () ->
                    ejecutar(c, "UPDATE evidencia_original SET contenido_crudo = 'otra' "
                              + "WHERE id_evidencia = " + idEvidencia));
                assertTrue(alActualizar.getMessage().contains("inmutable"));

                SQLException alBorrar = assertThrows(SQLException.class, () ->
                    ejecutar(c, "DELETE FROM evidencia_original WHERE id_evidencia = " + idEvidencia));
                assertTrue(alBorrar.getMessage().contains("inmutable"));
            } finally {
                c.rollback(); // no dejamos nada guardado
            }
        }
    }

    @Test
    void unHashQueNoCoincideConElContenidoSeRechaza() throws Exception {
        try (Connection c = ConexionBD.obtenerConexion()) {
            c.setAutoCommit(false);
            try {
                long idCarga = insertarCarga(c);
                String hashDeOtroTexto = sha256("otro texto distinto");
                SQLException e = assertThrows(SQLException.class, () ->
                    insertarEvidencia(c, idCarga, "texto", hashDeOtroTexto, sha256(CEROS + hashDeOtroTexto)));
                assertTrue(e.getMessage().contains("Hash SHA-256"));
            } finally {
                c.rollback();
            }
        }
    }

    @Test
    void lasVistasDeIntegridadNoReportanAlteraciones() throws Exception {
        try (Connection c = ConexionBD.obtenerConexion()) {
            assertEquals(0, contar(c, "v_evidencia_alterada"));
            assertEquals(0, contar(c, "v_correccion_alterada"));
            assertEquals(0, contar(c, "v_respuesta_alterada"));
        }
    }
}