USE smartbuildings_db;
DELIMITER $$


DROP FUNCTION IF EXISTS salute_sensore$$
CREATE FUNCTION salute_sensore(
    id_sensore INT UNSIGNED,
    data_inizio DATE,
    data_fine DATE
)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
BEGIN

    DECLARE x DECIMAL(9,6);
    DECLARE s DECIMAL(9,6);
    DECLARE p DECIMAL(9,6);
    DECLARE tipo VARCHAR(45);

    SELECT Tipologia, Soglia
    FROM Sensore
    WHERE ID = id_sensore
    INTO tipo, s;


    # Sensori a basso campionamento
    IF tipo IN ('Fessurimetro', 'Termometro', 'Pluviometro', 'Igrometro') THEN

        SELECT AVG(M.X)
        FROM Misurazione M
        WHERE M.Sensore = id_sensore
              AND M.Timestamp BETWEEN data_inizio AND data_fine
        INTO x;

        CASE
            WHEN tipo = 'Fessurimetro' THEN SET p = 0.3;
            WHEN tipo = 'Pluviometro' THEN SET p = 0.5;
            ELSE SET p = 0.7; # Termometri ed igrometri
        END CASE;

    # Sensori ad alto campionamento
    ELSE

        WITH misurazioni_rankate AS (
            SELECT SQRT(M.X*M.X + M.Y*M.Y + M.Z*M.Z) AS Modulo,
                   # Per poter prendere il top 1% delle misurazioni di ogni sensore mi serve sapere:
                   #    - Quante misurazioni ha fatto
                   COUNT(*) OVER () AS totale_misurazioni, # OVER () Serve per non fare collassare i record
                   #    - Come sono ordinate le misurazioni
                   ROW_NUMBER() OVER (
                       ORDER BY SQRT(M.X*M.X + M.Y*M.Y + M.Z*M.Z) DESC
                   ) AS rank_misurazione
            FROM Misurazione M
            WHERE M.Sensore = id_sensore
                  AND M.Timestamp BETWEEN data_inizio AND data_fine
        )
        SELECT AVG(MR.Modulo)
        INTO x
        FROM misurazioni_rankate MR
        WHERE MR.rank_misurazione <= 0.01 * MR.totale_misurazioni;

        SET p = 0.2;

        IF tipo = 'Accelerometro' THEN
            SET s = s - 1;
            SET x = ABS(x - 1);
        END IF;

    END IF;


    # Funzione salute
    IF x <= p*s THEN
        RETURN 10;
    ELSEIF x >= s THEN
        RETURN 0;
    ELSE
        RETURN 10 - 10*((x - p*s)/(s - p*x));
    END IF;

END $$


DROP PROCEDURE IF EXISTS genera_tabella_salute_sensori$$
CREATE PROCEDURE genera_tabella_salute_sensori(
    IN id_edificio INT UNSIGNED,
    IN data_calcolo DATE
)
BEGIN

    DROP TEMPORARY TABLE IF EXISTS salute_sensori;
    CREATE TEMPORARY TABLE salute_sensori(
        ID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        Tipo VARCHAR(45),
        Salute_nuova DECIMAL(4,2),
        Salute_vecchia DECIMAL(4,2)
    );

    INSERT INTO salute_sensori(ID, Tipo, Salute_nuova, Salute_vecchia)
    SELECT
        ID,
        Tipologia,
        # Salute nuova
        salute_sensore(
            ID,
            data_calcolo - INTERVAL 15 DAY,
            data_calcolo
        ),
        # Salute vecchia
        salute_sensore(
            ID,
            data_calcolo - INTERVAL 30 DAY,
            data_calcolo - INTERVAL 16 DAY
        )
    FROM Sensore
    WHERE Piano_Edificio = id_edificio;

END $$



DROP FUNCTION IF EXISTS trova_muro$$
CREATE FUNCTION trova_muro(sensore INT UNSIGNED)
RETURNS INT UNSIGNED DETERMINISTIC
BEGIN
    DECLARE muro INT UNSIGNED;
    SET muro = (
        WITH coordinate_sensore AS (
            SELECT S.X, S.Y, S.Piano_Numero, S.Piano_Edificio
            FROM Sensore S
            WHERE S.ID = sensore
        )
        SELECT M.ID
        FROM Muro M NATURAL JOIN coordinate_sensore
        WHERE  ((coordinate_sensore.X <= M.X1 AND coordinate_sensore.X >= M.X2)
                OR (coordinate_sensore.X >= M.X1 AND coordinate_sensore.X <= M.X2))
            AND ((coordinate_sensore.Y <= M.Y1 AND coordinate_sensore.Y >= M.Y2)
                OR (coordinate_sensore.Y >= M.Y1 AND coordinate_sensore.Y <= M.Y2))
        LIMIT 1
        );

    RETURN muro;
end $$



DROP PROCEDURE IF EXISTS consiglia_intervento_fessurimetro$$
CREATE PROCEDURE consiglia_intervento_fessurimetro(
    IN Sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(30);
    DECLARE consigli_muro VARCHAR(250);
    DECLARE importanza_ INT UNSIGNED;
    DECLARE muro_target INT UNSIGNED;

    SET muro_target = trova_muro(Sensore);

    IF (salute_nuova <= salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 1)
        THEN SET consigli_muro = 'Nell ultimo mese il diametro della crepa è aumentato, pur rimanendo sotto controllo. Si consiglia l''installazione di giunti per evitare interventi più invasivi in futuro';
            SET importanza_ = 3;
    ELSEIF (salute_nuova < 1)
        THEN SET consigli_muro = 'Nell ultimo mese il diametro della crepa è aumentato notevolmente e non è più sotto controllo. Si consiglia l''immediato abbattimento e ricostruzione del muro';
            SET importanza_ = 5;
    ELSE SET consigli_muro = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Struttura - Muro: ', muro_target);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_muro, importanza_);

END $$


DROP PROCEDURE IF EXISTS consiglia_intervento_pluviometro$$
CREATE PROCEDURE consiglia_intervento_pluviometro(
    IN id_sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(50);
    DECLARE consigli_ VARCHAR(300);
    DECLARE importanza_ INT UNSIGNED;

    IF salute_nuova < salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 1
        THEN SET consigli_ = 'Nell''ultimo mese sono state rilevate precipitazioni superiori alla media, si consiglia l''intervento di un esperto per valutare la presenza di infiltrazioni';
            SET importanza_ = 3;
    ELSEIF salute_nuova < 1
        THEN SET consigli_ = 'Nell''ultimo mese sono state registrate precipitazioni senza precendeti, si consiglia l''intervento di un esperto per valutare la presenza di infiltrazioni ed il potenziamento della struttura isolante dell''edificio';
            SET importanza_ = 4;
    ELSE SET consigli_ = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Esterni - Pluviometro: ', id_sensore);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_, importanza_);


END $$


DROP PROCEDURE IF EXISTS consiglia_intervento_termometro$$
CREATE PROCEDURE consiglia_intervento_termometro(
    IN id_sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(50);
    DECLARE consigli_ VARCHAR(300);
    DECLARE importanza_ INT UNSIGNED;

    IF salute_nuova < salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 3
        THEN SET consigli_ = 'Nell''ultimo mese la temperatura media è aumentata, pur restando sotto controllo. Si consiglia l''installazione di un impianto di climatizzazione';
            SET importanza_ = 2;
    ELSEIF salute_nuova < 3
        THEN SET consigli_ = 'Nell''ultimo mese la temperatura media è aumentata notevolmente e non è più sotto controllo. Si consiglia l''intervento di un esperto che controlli la coibentazione termica dell''edificio';
            SET importanza_ = 4;
    ELSE SET consigli_ = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Interni - Sen. Temperatura: ', id_sensore);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_, importanza_);


END $$


DROP PROCEDURE IF EXISTS consiglia_intervento_igrometro$$
CREATE PROCEDURE consiglia_intervento_igrometro(
    IN id_sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(50);
    DECLARE consigli_ VARCHAR(300);
    DECLARE importanza_ INT UNSIGNED;

    IF salute_nuova < salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 5
        THEN SET consigli_ = 'Nell''ultimo mese l''umidità media è aumentata, pur restando sotto controllo. Si consiglia l''impiego di deumidificatori per migliorare il comfort dell''edificio';
            SET importanza_ = 2;
    ELSEIF salute_nuova < 5
        THEN SET consigli_ = 'Nell''ultimo mese l''umidità media è aumentata notevolmente e non è più sotto controllo. Si consiglia l''intervento immediato di un esperto per evitare la formazione di muffe sulle pareti dell''edificio';
            SET importanza_ = 3;
    ELSE SET consigli_ = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Interni - Sen. Igrometro: ', id_sensore);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_, importanza_);


END $$


DROP PROCEDURE IF EXISTS consiglia_intervento_accelerometro$$
CREATE PROCEDURE consiglia_intervento_accelerometro(
    IN id_sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(50);
    DECLARE consigli_ VARCHAR(300);
    DECLARE importanza_ INT UNSIGNED;

    IF salute_nuova < salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 3
        THEN SET consigli_ = 'Nell''ultimo mese il sensore ha rilevato vibrazioni più intense della media. Si consiglia il sopralluogo di un esperto al fine di valutare l''integrità dei muri portanti e delle travi di sostegno';
            SET importanza_ = 4;
    ELSEIF salute_nuova < 3
        THEN SET consigli_ = 'L''integrità struttura dell''edificio è compromessa e deve essere messa in sicurezza da un esperto. Evacuare la struttura al più presto';
            SET importanza_ = 5;
    ELSE SET consigli_ = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Struttura - Accelerometro: ', id_sensore);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_, importanza_);


END $$


DROP PROCEDURE IF EXISTS consiglia_intervento_giroscopio$$
CREATE PROCEDURE consiglia_intervento_giroscopio(
    IN id_sensore INT UNSIGNED,
    IN salute_vecchia DECIMAL(4,2),
    IN salute_nuova DECIMAL(4,2)
)
BEGIN
    DECLARE tipo_intervento VARCHAR(50);
    DECLARE consigli_ VARCHAR(500);
    DECLARE importanza_ INT UNSIGNED;

    IF salute_nuova < salute_vecchia - 0.3*salute_vecchia AND salute_nuova >= 3
        THEN SET consigli_ = 'Nell''ultimo mese il sensore ha rilevato vibrazioni più intense della media. Si consiglia il sopralluogo di un esperto al fine di valutare l''integrità dei solai ed il loro eventuale rifacimento';
            SET importanza_ = 4;
    ELSEIF salute_nuova < 3
        THEN SET consigli_ = 'L''integrità struttura dell''edificio è compromessa e deve essere messa in sicurezza da un esperto. Evacuare la struttura al più presto';
            SET importanza_ = 5;
    ELSE SET consigli_ = 'Non sono stati individuati interventi necessari';
        SET importanza_ = 0;
    END IF;

    SET tipo_intervento = CONCAT('Struttura - Giroscopio: ', id_sensore);
    INSERT INTO interventi_consigliati VALUES (tipo_intervento, consigli_, importanza_);


END $$



DROP PROCEDURE IF EXISTS genera_tabella_interventi$$
CREATE PROCEDURE genera_tabella_interventi(
    IN rigidezza TINYINT
)
BEGIN

    DECLARE fetch_sensore INT UNSIGNED;
    DECLARE fetch_tipologia VARCHAR(45);
    DECLARE fetch_salute_nuova DECIMAL(4,2);
    DECLARE fetch_salute_vecchia DECIMAL(4,2);
    DECLARE terminato TINYINT DEFAULT 0;

    DECLARE sensori CURSOR FOR
    SELECT *
    FROM salute_sensori
    WHERE Salute_nuova <= rigidezza;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET terminato = 1;

    # Creo la tabella degli interventi consigliati
    DROP TEMPORARY TABLE IF EXISTS interventi_consigliati;
    CREATE TEMPORARY TABLE interventi_consigliati(
        Tipologia VARCHAR(50) PRIMARY KEY,
        Intervento VARCHAR(300),
        Importanza INT UNSIGNED
    );

    OPEN sensori;

    scan_sensori: LOOP

        FETCH sensori INTO fetch_sensore, fetch_tipologia, fetch_salute_nuova, fetch_salute_vecchia;
        IF terminato = 1 THEN LEAVE scan_sensori; END IF;

        CASE fetch_tipologia
            WHEN 'Fessurimetro' THEN CALL consiglia_intervento_fessurimetro(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
            WHEN 'Pluviometro' THEN CALL consiglia_intervento_pluviometro(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
            WHEN 'Termometro' THEN CALL consiglia_intervento_termometro(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
            WHEN 'Igrometro' THEN CALL consiglia_intervento_igrometro(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
            WHEN 'Accelerometro' THEN CALL consiglia_intervento_accelerometro(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
            WHEN 'Giroscopio' THEN CALL consiglia_intervento_giroscopio(fetch_sensore, fetch_salute_vecchia, fetch_salute_nuova);
        END CASE;

    END LOOP;


    SELECT *
    FROM interventi_consigliati
    WHERE Importanza <> 0
    ORDER BY Importanza DESC;

END $$



DROP PROCEDURE IF EXISTS consiglia_interventi$$
CREATE PROCEDURE consiglia_interventi(
    IN ID_Edificio INT UNSIGNED,
    IN data_calcolo DATE,
    IN rigidezza TINYINT
)
BEGIN

    CALL genera_tabella_salute_sensori(ID_Edificio, data_calcolo);
    CALL genera_tabella_interventi(rigidezza);

END $$