USE smartbuildings_db;
DELIMITER $$
SET @COEFF_ATTENUAZIONE = 600;



-- ---------------------------------------------------------------------------------------------------------------------
-- Stato di un edificio
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS rischio_area_geografica$$
CREATE FUNCTION rischio_area_geografica(
    id_edificio INT UNSIGNED,
    tipo VARCHAR(45),
    data_calcolo DATE
)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
    /*
    Passo 1 del paragrafo 8.1 della documentazione
    */
    RETURN (
        SELECT Coefficiente
        FROM Rischio
        WHERE Tipologia = tipo
              AND AreaGeografica = (
                    SELECT AreaGeografica
                    FROM Edificio
                    WHERE ID = id_edificio
              ) AND DataMisurazione >= ALL (
                    SELECT R.DataMisurazione
                    FROM Rischio R
                    WHERE R.AreaGeografica = AreaGeografica
                          AND R.Tipologia = tipo
                          AND R.DataMisurazione <= data_calcolo
              ) AND DataMisurazione <= data_calcolo
    );

DROP FUNCTION IF EXISTS rischio_edificio$$
CREATE FUNCTION rischio_edificio(
    id_edificio INT UNSIGNED,
    data_calcolo DATE,
    ambientale TINYINT,
    nuovo TINYINT
)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
BEGIN
     /*
    Passo 2 e 3 del paragrafo 8.1 della documentazione
     */

    DECLARE data_inizio DATE DEFAULT IF(nuovo, data_calcolo - INTERVAL 16 DAY, data_calcolo - INTERVAL 30 DAY);
    DECLARE data_fine DATE DEFAULT IF(nuovo, data_calcolo, data_calcolo - INTERVAL 15 DAY);
    DECLARE rischio_sensori DECIMAL(5,2);
    DECLARE rischio_area_geografica DECIMAL(5,2);

    # Rischio ambientale
    IF ambientale THEN

        SELECT AVG(10 - salute_sensore(
                ID,
                data_inizio,
                data_fine
            ))
        FROM Sensore
        WHERE Piano_Edificio = id_edificio
              AND Tipologia IN ('Termometro', 'Pluviometro', 'Igrometro')
        INTO rischio_sensori;

        SET rischio_area_geografica = rischio_area_geografica(
            id_edificio,
            'Idrogeologico',
            data_fine
        );

    # Rischio strutturale
    ELSE

        SELECT AVG(10 - salute_sensore(
                ID,
                data_inizio,
                data_fine
            ))
        FROM Sensore
        WHERE Piano_Edificio = id_edificio
              AND Tipologia IN ('Fessurimetro', 'Accelerometro', 'Grioscopio')
        INTO rischio_sensori;

        SET rischio_area_geografica = rischio_area_geografica(
            id_edificio,
            'Sismico',
            data_fine
        );

    END IF;


    RETURN ((rischio_area_geografica + 1) * rischio_sensori);

END $$

DROP FUNCTION IF EXISTS stato_edificio$$
CREATE FUNCTION stato_edificio(
    id_edificio INT UNSIGNED,
    data_calcolo DATE
)
RETURNS TINYINT NOT DETERMINISTIC READS SQL DATA
BEGIN
    /*
     Paragrafo 8.1 della documentazione
     */
    DECLARE rischio_ambientale_new DECIMAL(5,2);    # Relativo ai 15 giorni precedenti al calcolo
    DECLARE rischio_ambientale_old DECIMAL(5,2);    # Relativo ai 15 giorni ancora prima
    DECLARE rischio_ambientale_previsto DECIMAL(5,2);

    DECLARE rischio_strutturale_new DECIMAL(5,2);   # Relativo ai 15 giorni precedenti al calcolo
    DECLARE rischio_strutturale_old DECIMAL(5,2);   # Relativo ai 15 giorni ancora prima
    DECLARE rischio_strutturale_previsto DECIMAL(5,2);

    DECLARE rischio_finale_previsto DECIMAL(5,2);

    SET rischio_ambientale_new = rischio_edificio(id_edificio,data_calcolo,TRUE,TRUE);
    SET rischio_ambientale_old = rischio_edificio(id_edificio,data_calcolo,TRUE,FALSE);

    SET rischio_strutturale_new = rischio_edificio(id_edificio,data_calcolo,FALSE,TRUE);
    SET rischio_strutturale_old = rischio_edificio(id_edificio,data_calcolo,FALSE,FALSE);

    SET rischio_ambientale_previsto = rischio_ambientale_new * IF(rischio_ambientale_new > rischio_ambientale_old, 1.15, 0.85);
    SET rischio_strutturale_previsto = rischio_strutturale_new * IF(rischio_strutturale_new > rischio_strutturale_old, 1.15, 0.85);

    SET rischio_finale_previsto = rischio_ambientale_previsto + rischio_strutturale_previsto;

    RETURN IF(100 - rischio_finale_previsto < 0, 0, 100 - rischio_finale_previsto);

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Intensità di un evento calamitoso
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS distanza_coordinate$$
CREATE FUNCTION distanza_coordinate(
    lat1 DECIMAL(9,6),
    lon1 DECIMAL(9,6),
    lat2 DECIMAL(9,6),
    lon2 DECIMAL(9,6)
)
RETURNS INT DETERMINISTIC
BEGIN
    /*
     Ritorna la distanza in KM (numero intero) tra due punti della superficie terrestre
     */

    DECLARE delta_lon DECIMAL(9,6);
    DECLARE delta_lat DECIMAL(9,6);

    # Converte le latitudini e longitudini in radianti
    SET lat1 = lat1 * PI() / 180;
    SET lon1 = lon1 * PI() / 180;
    SET lat2 = lat2 * PI() / 180;
    SET lon2 = lon2 * PI() / 180;

    SET delta_lat = lat2 - lat1;
    SET delta_lon = lon2 - lon1;

    # 6371 è il raggio della terra in KM, il resto è noto come formula dell'emisenoverso
    RETURN 6371 * 2 * ASIN(SQRT( POW(SIN(delta_lat/2),2) + COS(lat1) * COS(lat2) * POW(SIN(delta_lon/2),2) ));

END $$

DROP FUNCTION IF EXISTS peak_ground_measurements$$
CREATE FUNCTION peak_ground_measurements(
    timestamp_calamita DATETIME,
    edificio INT UNSIGNED,
    tipo VARCHAR(45)
)
RETURNS DECIMAL(9,6) NOT DETERMINISTIC READS SQL DATA
    /*
     Ritorna la PGA o PGR di un edificio ad un certo timestamp come descritto nel paragrafo 8.2 della documentazione
     */
    RETURN (
        WITH misurazioni_rankate AS (
            SELECT M.Sensore,
                   S.Soglia,
                   S.Piano_Numero,
                   SQRT(M.X * M.X + M.Y * M.Y + M.Z * M.Z) AS Modulo,
                   /*
                    Voglio prenderne il top 1%, mi serve dunque sapere:
                    */
                   #    - Quante misurazioni ha fatto il sensore
                   COUNT(*) OVER (
                       PARTITION BY M.Sensore
                   ) AS totale_misurazioni,
                   #    - Come sono ordinate le misurazioni
                   ROW_NUMBER() OVER (
                       PARTITION BY M.Sensore
                       ORDER BY SQRT(M.X * M.X + M.Y * M.Y + M.Z * M.Z) DESC
                   ) AS rank_misurazione
            FROM Misurazione M INNER JOIN Sensore S on M.Sensore = S.ID
            WHERE M.Timestamp BETWEEN timestamp_calamita - INTERVAL 1 MINUTE AND timestamp_calamita + INTERVAL 1 MINUTE
                  AND Sensore IN (
                      SELECT ID
                      FROM Sensore
                      WHERE Piano_Edificio = edificio
                            AND Tipologia = tipo
                            AND Piano_Numero IN (0,1,2)
                  )
        ), PGM_per_sensore AS (
            SELECT IF(
                    tipo = 'Accelerometro',
                    AVG( ABS(MR.Modulo - 1) * (1-0.1*MR.Piano_Numero) ),
                    AVG( MR.Modulo * (1-0.1*MR.Piano_Numero) )
                ) AS PGM
            FROM misurazioni_rankate MR
            WHERE MR.rank_misurazione <= 0.01 * MR.totale_misurazioni
            GROUP BY MR.Sensore
        )
        SELECT AVG(PGM_per_sensore.PGM)
        FROM PGM_per_sensore
    );

DROP FUNCTION IF EXISTS PGV_to_Mercalli$$
CREATE FUNCTION PGV_to_mercalli(
    PGV DECIMAL(9,6)
)
RETURNS DECIMAL(4,2) DETERMINISTIC
    /*
     Implementazione della funzione di approssimazione della scala mercalli descritta nel paragrafo 8.2 della documentazione
     */
    IF PGV <= 0 THEN RETURN 0;
    ELSEIF PGV <= 0.234686 THEN RETURN 9 * POW(PGV, 0.17);
    ELSE RETURN 9.4 * POW(PGV, 0.2);
    END IF;

DROP PROCEDURE IF EXISTS stima_intensita_calamita$$
CREATE PROCEDURE stima_intensita_calamita(
    IN timestamp_calamita DATETIME
)
BEGIN

    # Calcolo qui con default perchè voglio usarli nel cursore
    DECLARE latitudine_epicentro DECIMAL(9,6) DEFAULT (
        SELECT Latitudine FROM Calamita WHERE Timestamp = timestamp_calamita
    );
    DECLARE longitudine_epicentro DECIMAL(9,6) DEFAULT (
        SELECT Longitudine FROM Calamita WHERE Timestamp = timestamp_calamita
    );
    DECLARE fetch_edificio INT UNSIGNED;
    DECLARE fetch_distanza INT;
    DECLARE finito TINYINT DEFAULT 0;
    DECLARE PGV_edificio DECIMAL(9,6);
    DECLARE Mercalli_epicentro DECIMAL(9,6);

    DECLARE edifici_colpiti CURSOR FOR
    SELECT ID, distanza_coordinate(Latitudine, Longitudine, latitudine_epicentro, longitudine_epicentro)
    FROM Edificio
    WHERE AreaGeografica IN (
        SELECT AreaGeografica
        FROM Evento
        WHERE Calamita = timestamp_calamita
    );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;


    /*
     Questa parte di codice utilizza la materialized view :

     CREATE TABLE IF NOT EXISTS MV_statistiche_edifici_colpiti (
        `Calamita` DATETIME,
        `Edificio` INT UNSIGNED,
        `Distanza` INT,
        `Mercalli` DECIMAL(4,2),    # Equivalente Mercalli della PGV percepita dall'edificio
        PRIMARY KEY (`Calamita`, `Edificio`)
     );

     Materialized view e non temporary table perchè le intensità percepite dai
        singoli edifici sono richieste per stimare i danni subiti da quest'ultimi,
        quindi averli sempre a disposizione in una MV fa risparmiare conti

     La materialized view inoltre non necessita di aggiornamenti, infatti i record inseriti rimangono sempre tali.

     */
    IF EXISTS(
        SELECT 1
        FROM MV_statistiche_edifici_colpiti
        WHERE Calamita = timestamp_calamita
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'L''intensità della calamità indicata è giò stata stimata';
    END IF;

    OPEN edifici_colpiti;
    scan_edifici: LOOP

        FETCH edifici_colpiti INTO fetch_edificio, fetch_distanza;
        IF finito = 1 THEN LEAVE scan_edifici; END IF;

        SET PGV_edificio = 0.5 * (
            # PGA
            peak_ground_measurements(timestamp_calamita, fetch_edificio,'Accelerometro')
                +
            # PGR
            peak_ground_measurements(timestamp_calamita, fetch_edificio, 'Giroscopio')
        );

        INSERT INTO MV_statistiche_edifici_colpiti(Calamita, Edificio, Distanza, Mercalli) VALUES
            (timestamp_calamita, fetch_edificio, fetch_distanza, PGV_to_mercalli(PGV_edificio));

    END LOOP;

    SELECT AVG( Mercalli * POW(Distanza/@COEFF_ATTENUAZIONE + 1, 2) )
    FROM MV_statistiche_edifici_colpiti
    WHERE Calamita = timestamp_calamita
    INTO Mercalli_epicentro;

    # Aggiorna il record della calamità
    UPDATE Calamita SET Intensita = Mercalli_epicentro WHERE Timestamp = timestamp_calamita;
END $$

DROP FUNCTION IF EXISTS stima_intensita_percepita$$
CREATE FUNCTION stima_intensita_percepita(
    timestamp_calamita DATETIME,
    raggio INT
)
RETURNS DECIMAL(4,2) DETERMINISTIC READS SQL DATA
BEGIN
    /*
     Ritorna l'inensità percepita ad un raggio qualsiasi dall'epicentro di una calamità,
     non serve nella stima dei danni ma è una procedura utile da avere a disposizione.
     */
    DECLARE intensita_epicentro DECIMAL(4,2);

    SELECT Intensita
    FROM Calamita
    WHERE Timestamp = timestamp_calamita
    INTO intensita_epicentro;

    RETURN intensita_epicentro * 1/POW(raggio/@COEFF_ATTENUAZIONE + 1, 2);
END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Stima dei danni
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS stima_danni$$
CREATE FUNCTION stima_danni(
    timestamp_calamita DATETIME,
    id_edificio INT UNSIGNED
)
RETURNS INT NOT DETERMINISTIC READS SQL DATA
BEGIN

    DECLARE latitudine_epicentro DECIMAL(9,6);
    DECLARE longitudine_epicentro DECIMAL(9,6);
    DECLARE latitudine_edificio DECIMAL(9,6);
    DECLARE longitudine_edificio DECIMAL(9,6);
    DECLARE intensita_percepita DECIMAL(4,2);
    DECLARE percentuale_distruzione DECIMAL(4,2);
    DECLARE stato_edificio TINYINT;
    DECLARE valore_edificio INT;

    SELECT Latitudine, Longitudine
    FROM Calamita
    WHERE Timestamp = timestamp_calamita
    INTO latitudine_epicentro, longitudine_epicentro;

    SELECT Latitudine, Longitudine
    FROM Edificio
    WHERE ID = id_edificio
    INTO latitudine_edificio, longitudine_edificio;


    /*
     Utilizzando la MV non devo rifare tutti i conti
     */
    SELECT Mercalli
    FROM MV_statistiche_edifici_colpiti
    WHERE Calamita = timestamp_calamita
          AND Edificio = id_edificio
    INTO intensita_percepita;

    IF (intensita_percepita IS NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'L''edificio specificato non è stato colpito dalla calimità indicata';
    END IF;

    # Per fare il modo che l'evento calamitoso non influenzi lo stato dell'edificio questo viene calcolato un giorno prima
    SET stato_edificio = stato_edificio(id_edificio, timestamp_calamita - INTERVAL 1 DAY);

    SELECT SUM(IFNULL(Costo,0))
    FROM Progetto
    WHERE Edificio = id_edificio
    INTO valore_edificio;

    IF intensita_percepita <= 4 THEN
        SET percentuale_distruzione = 0;
    ELSEIF percentuale_distruzione >= 10 THEN
        SET percentuale_distruzione = 1;
    ELSE
        SET percentuale_distruzione = 0.02*POW(intensita_percepita-3,2) * (200-stato_edificio)/100;
    END IF;

    RETURN valore_edificio * percentuale_distruzione;
END $$




