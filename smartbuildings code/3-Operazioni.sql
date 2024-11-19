USE smartbuildings_db;
SET GLOBAL EVENT_SCHEDULER = OFF; # Altrimenti rimuove le misurazioni vecchie (cosa che per i test non vogliamo)
SET @DURATA_MASSIMA_TURNO = 8;
SET @MAX_OPERAI_CONTEMPORANEI = 15;
DELIMITER $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione A, comprende:
--  - L'operazione per tenere aggiornata la ridondanza sulla disponibilità dei materiali
--  - Il vincolo generico 5
-- ---------------------------------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS inserisci_utilizzi$$
CREATE PROCEDURE inserisci_utilizzi(
    IN lavoro_id INT UNSIGNED,
    IN materiale_id INT UNSIGNED,
    IN quantita SMALLINT
)
BEGIN
    /*
    Specificando solamente il lavoro, il materiale che si intende utilizzare e la quantità, questa prcedura
    inserisce automaticamente tanti record di utilizzo quanti sono gli ordini diversi da cui è necessario
    prendere il materiale per soddisfare la quantità rischiesta, aggiornando nel frattempo la quantità
    rimasta in magazzino di ognuno.
     */

    DECLARE finito TINYINT DEFAULT 0;
    DECLARE fetch_id SMALLINT;
    DECLARE fetch_disponibilita SMALLINT;
    DECLARE fetch_data_acquisto DATE;
    DECLARE quantita_rimasta_da_inserire SMALLINT;

    /*
     Prende gli ordini relativi al materiale da utilizzare con disponilità > 0 e li ordina dal più
     vecchio al più recente, in modo da utilizzare prima i materiali degli ordini più vecchi in magazzino.
     */
    DECLARE ordini CURSOR FOR
    SELECT ID, Disponibilita, DataAcquisto
    FROM Ordine
    WHERE Materiale = materiale_id AND Disponibilita > 0
    ORDER BY DataAcquisto;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;

    /*
    Evito chiamate del tipo:
        CALL inserisci_utilizzi(1, 1, 200);
        CALL inserisci_utilizzi(1, 1, 145);
    bisogna invece fare così:
        CALL inserisci_utilizzi(1, 1, 345);
    */
    IF EXISTS(
        SELECT 1
        FROM Utilizzo INNER JOIN Ordine ON Ordine = ID
        WHERE Lavoro = lavoro_id
              AND Materiale = materiale_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il lavoro utilizza già il materiale indicato, sommare gli utilizzi in un''unica chiamata';
    END IF;


    IF quantita < 0 OR quantita > (
        SELECT SUM(Disponibilita)
        FROM Ordine
        WHERE Materiale = materiale_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Scorte di materiale non sufficienti o quantità negativa';
    END IF;


    SET quantita_rimasta_da_inserire = quantita;

    OPEN ordini;
    scan_ordini: LOOP
        FETCH ordini INTO fetch_id, fetch_disponibilita, fetch_data_acquisto;
        IF finito = 1 OR quantita_rimasta_da_inserire = 0 THEN LEAVE scan_ordini; END IF;

        /*
         Se l'ordine attuale non è sufficiente per soddisafre il bisogno di materiale richiesto allora
         inserisce tutta la quantità rimasta e passa all'ordine successivo, altrimenti inserisce solo
         la quantità richiesta ed esce dal ciclo
         */

        # Se l'ordine attuale non è sufficiente per soddisfare il bisogno di materiale richiesto
        IF quantita_rimasta_da_inserire >= fetch_disponibilita THEN
            # Utilizza tutta la quantità rimasta
            INSERT INTO Utilizzo VALUES (lavoro_id, fetch_id, fetch_disponibilita);
            # Aggiorna la disponibilità dell'ordine
            UPDATE Ordine SET Disponibilita = 0 WHERE ID = fetch_id;
            # Passa all'ordine successivo
            SET quantita_rimasta_da_inserire = quantita_rimasta_da_inserire - fetch_disponibilita;

        # Se l'ordine attuale è sufficiente per soddisfare il bisogno di materiale richiesto
        ELSE
            # Utilizza soltanto la quantità richiesta
            INSERT INTO Utilizzo VALUES (lavoro_id, fetch_id, quantita_rimasta_da_inserire);
            # Aggiorna la disponibilità dell'ordine
            UPDATE Ordine SET Disponibilita = Disponibilita - quantita_rimasta_da_inserire WHERE ID = fetch_id;
            # Termina il ciclo
            LEAVE scan_ordini;
        END IF;
    END LOOP;

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione B
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS operai_coordinabili$$
CREATE FUNCTION operai_coordinabili(
    CodFiscale CHAR(16),
    data_calcolo DATE
)
RETURNS TINYINT DETERMINISTIC
BEGIN
    /*
     Ritorna il numero di operai che l'operaio CodFiscale poteva controllare in data Data
     Gli operai coordinabili partono da una base operai_coordinabili_base e scalano
     linearmente con gli anni d'esperienza secondo il coefficiente aumento_annuale
     */

    DECLARE operai_coordinabili_base TINYINT DEFAULT 8;
    DECLARE aumento_annuale DECIMAL(1,1) DEFAULT .5;

    DECLARE anni_esperienza TINYINT;
    DECLARE operai_coordinabili_calcolati TINYINT;

    SELECT P.AnniEsperienza
    FROM smartbuildings_db.Personale P
    WHERE P.CodFiscale = CodFiscale
    INTO anni_esperienza;

    IF anni_esperienza IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il codice fiscale non appartiene a nessun operaio';
    END IF;

    IF data_calcolo = CURDATE() THEN
        RETURN operai_coordinabili_base + ROUND(anni_esperienza * aumento_annuale);
    END IF;

    SET operai_coordinabili_calcolati = operai_coordinabili_base + ROUND(
        (anni_esperienza - TIMESTAMPDIFF(YEAR, data_calcolo, CURDATE())) * aumento_annuale
    );

    # Se ho messo date strane o vengono conti strani
    IF (operai_coordinabili_calcolati < operai_coordinabili_base) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La data specificata è troppo avanti o indietro nel tempo';
    END IF;

    RETURN operai_coordinabili_calcolati;
END $$

DROP FUNCTION IF EXISTS operai_al_lavoro$$
CREATE FUNCTION operai_al_lavoro(
    stadio_di_avanzamento INT UNSIGNED,
    tempo DATETIME
)
RETURNS TINYINT NOT DETERMINISTIC READS SQL DATA
    RETURN (
        SELECT COUNT(*)
        FROM Turno
        WHERE StadioAvanzamento = stadio_di_avanzamento
              AND (Inizio <= tempo AND Fine >= tempo)
    );

DROP PROCEDURE IF EXISTS inserisci_turno$$
CREATE PROCEDURE inserisci_turno(
     IN stadio_avanzamento INT UNSIGNED,
     IN CodFiscale_operaio CHAR(16),
     IN CodFiscale_supervisore CHAR(16),
     IN inizio_turno DATETIME,
     IN fine_turno DATETIME
)
BEGIN

    DECLARE sovrapposizione INT DEFAULT 0;
    DECLARE operai_contemporanei INT;
    DECLARE tempo DATETIME;
    DECLARE inizio_turno_supervisore DATETIME;
    DECLARE fine_turno_supervisore DATETIME;
    DECLARE finito TINYINT DEFAULT 0;

    DECLARE inizi_turni CURSOR FOR
    SELECT Inizio
    FROM Turno
    WHERE StadioAvanzamento = stadio_avanzamento
          AND Inizio BETWEEN inizio_turno AND fine_turno;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;

    # Controllo che i codici fiscali corrispondano a personale attivo
    IF 1 <> (SELECT Attivo
             FROM Personale
             WHERE CodFiscale = CodFiscale_operaio)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Imppossibile assegnare un turno ad un operaio non attivo';
    END IF;
    IF 1 <> (SELECT Attivo
             FROM Personale
             WHERE CodFiscale = CodFiscale_supervisore)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Imppossibile assegnare un turno ad un supervisore non attivo';
    END IF;

    # Controllo stadio di avanzamento (deve essere in corso)
    IF (SELECT DataFine
        FROM StadioAvanzamento
        WHERE ID = stadio_avanzamento) IS NOT NULL
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lo stadio di avanzamento è già concluso';
    END IF;

    # Convalida inizio e fine turno
    IF (fine_turno <= inizio_turno OR TIMESTAMPDIFF(MINUTE, inizio_turno, fine_turno)/60 > @DURATA_MASSIMA_TURNO)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Orari del turno non validi (Massimo numero di ore = 8)';
    END IF;

    # Controllo sovrapposizione con altri turni dello stesso operaio
    SET sovrapposizione = (
                            SELECT COUNT(*)
                            FROM Turno
                            WHERE CodFiscale_operaio = Turno.Operaio
                                  AND (Fine >= inizio_turno AND Inizio <= fine_turno)
                            );
    IF sovrapposizione <> 0
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il turno dell''operaio si sovrappone con altri suoi turni';
    END IF;

    # Controllo se il numero max di operai per lo stadio di avanzamento e' rispettato
    # All'inizio il massimo di operai contemporanei è quando inizia il turno l'operaio
    SET operai_contemporanei = operai_al_lavoro(stadio_avanzamento, inizio_turno);
    OPEN inizi_turni;
    scan_turni: LOOP
        FETCH inizi_turni INTO tempo;
        IF finito = 1 THEN LEAVE scan_turni; END IF;
        # Ogni volta che un'altro inizia il turno vedo se questo numero è aumentato
        SET operai_contemporanei = IF(
            operai_al_lavoro(stadio_avanzamento, tempo) > operai_contemporanei,
            operai_al_lavoro(stadio_avanzamento, tempo),
            operai_contemporanei
        );
    END LOOP;
    IF operai_contemporanei > @MAX_OPERAI_CONTEMPORANEI
        THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il turno viola il limite massimo di operai contemporanei';
    END IF;


    # Controllo che il turno sia completamente contenuto in un turno del supervisore
    #   SOLO SE IL SUPERVISORE NON E' SE STESSO
    IF CodFiscale_supervisore != CodFiscale_operaio THEN

        SELECT Inizio, Fine
        FROM Turno
        WHERE StadioAvanzamento = stadio_avanzamento
              AND Operaio = CodFiscale_supervisore
              AND (Inizio <= inizio_turno AND Fine >= fine_turno)
        INTO inizio_turno_supervisore, fine_turno_supervisore;

        IF inizio_turno_supervisore IS NULL # O fine turno, o entrambi, è uguale, è per dire se non hai trovato niente:
            THEN SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Il supervisore indicato non lavora negli orari specificati';
        END IF;

    # Controllo se sforo il numero massimo di operai per supervisore
        IF operai_coordinabili(CodFiscale_supervisore, DATE(inizio_turno)) <= (
            SELECT COUNT(DISTINCT Operaio)
            FROM Turno
            WHERE StadioAvanzamento = stadio_avanzamento # più efficiente
                  AND Supervisore = CodFiscale_supervisore
                  AND Inizio BETWEEN inizio_turno_supervisore AND fine_turno_supervisore
                # AND Fine BETWEEN inizio_turno_supervisore AND fine_turno_supervisore
            # basta controllare una delle due, tanto dal momento che il turno inizia
            # deve anche finire prima del supervisore e viceversa

        ) THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il supervisore indicato supervisione già troppi operai';
        END IF;

     END IF;

    # Inserimento in Turno
    INSERT INTO Turno(StadioAvanzamento, Operaio, Supervisore, Inizio, Fine) VALUES
        (stadio_avanzamento, CodFiscale_operaio, CodFiscale_supervisore, inizio_turno, fine_turno);

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione C
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS metratura_piano$$
CREATE FUNCTION metratura_piano (
    id_edificio INT UNSIGNED,
    numero_piano TINYINT UNSIGNED
)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
BEGIN

    /*
        Idea dell'algoritmo:
     tra tutti i vertici del poligono formato dai muri esterni del piano dell'edificio specificato ne si prende
     uno a caso (limit 1) e si parte da li, ogni ciclo si calcolano i due vertici adiacenti a quello in cui
     sono attualmente (sono i vertici dei muri esterni che lo hanno come x1 y1 o x2 y2) e si va in quello che
     non ho già coperto: al primo ciclo posso scegliere uno qualsiasi tra i due vertici adiacenti perchè non
     ho ancora coperto niente, questo determina il verso del giro (oraio o antiorario), dopo di chè la scelta
     è forzata; si calcola dunque l'area del trapezio che ha come basi la y del vertice in cui sono e la y del
     vertice in cui voglio andare e come lati il segmento che va dal vertice in cui sono al vertice in cui
     voglio andare e la sua proiezione sull'asse delle x; l'area di questo trapezio ha un segno che è dato dalla
     direzione in cui mi sto muovendo (rientranze nel poligono hanno infatti segno negativo e giustamente
     contribuiscono a togliere un pezzo di area); infine viene preso il valore assoluto della somma di tutti
     questi contributi perchè se percorriamo il poligono in modo orario otteniamo un'area positiva mentre se lo
     percorriamo in modo antiorario una negativa (ovviamente di modulo uguale), il verso di percorrenza è casuale
     e noi vogliamo sempre ottenere un'area positiva dunque ne prendiamo il valore assoluto.
     */

    DECLARE area DECIMAL(5, 2) DEFAULT 0;
    DECLARE i_am_X DECIMAL(5,2);
    DECLARE i_am_Y DECIMAL(5,2);
    DECLARE start_X DECIMAL(5,2);
    DECLARE start_Y DECIMAL(5,2);
    DECLARE go_X DECIMAL(5,2) DEFAULT NULL;
    DECLARE go_Y DECIMAL(5,2) DEFAULT NULL;


    # Sceglie un vertice di partenza casuale tra tutti quelli dei muri esterni
    SELECT X1, Y1
    FROM Muro
    WHERE Piano_Numero = numero_piano
          AND Piano_Edificio = id_edificio
          AND 1 = (
              SELECT COUNT(*)
              FROM Parete P
              WHERE P.Muro = ID
          )
    LIMIT 1
    INTO i_am_X, i_am_Y;

    # Devo ricordarmi dove sono partito
    SET start_X = i_am_X, start_Y = i_am_Y;

    DROP TEMPORARY TABLE IF EXISTS vertici_coperti;
    CREATE TEMPORARY TABLE vertici_coperti (
        `X` DECIMAL(5,2),
        `Y` DECIMAL(5,2),
        PRIMARY KEY (`X`, `Y`)
    );


    # Gira il poligono formato dai muri esterni
    rotate: LOOP

        # Calcolo il vertice adiacente non ancora coperto
        SELECT *
        FROM (
            (
                # Prendo gli x1, y1 dei muri esterni che hanno il vertice attuale come x2, y2
                SELECT X1 AS X, Y1 AS Y
                FROM Muro
                WHERE Piano_Numero = numero_piano
                    AND Piano_Edificio = id_edificio
                    AND 1 = (
                        SELECT COUNT(*)
                        FROM Parete P
                        WHERE P.Muro = ID
                    )
                    AND (X2 = i_am_X AND Y2 = i_am_Y)
            ) UNION (
                # E li unisco agli x2, y2 dei muri esterni che hanno il vertice attuale come x1, y1
                SELECT X2 AS X, Y2 AS Y
                FROM Muro
                WHERE Piano_Numero = numero_piano
                    AND Piano_Edificio = id_edificio
                    AND 1 = (
                        SELECT COUNT(*)
                        FROM Parete P
                        WHERE P.Muro = ID
                    )
                    AND (X1 = i_am_X AND Y1 = i_am_Y)
            )
        ) AS directions
        # Ottengo due vertici, uno dei quali è sicuramente già coperto (tranne che al primo passo)...
        WHERE (directions.X, directions.Y) NOT IN (SELECT * FROM vertici_coperti)
        # ... per questo c'è limit 1, al primo passo ne scelgo uno a caso tra i due usciti
        LIMIT 1
        INTO go_X, go_Y;

        # Se il vertice dove andare è vuoto il poligono non è chiuso
        IF (go_X IS NULL OR go_Y IS NULL) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Impossibile calcolare l''area di un poligono aperto, controllare la disposizione dei muri';
        END IF;

        # Se il vertice dove andare è se stesso allora sono tornato al punto di partenza
        IF (go_X = i_am_X AND go_Y = i_am_Y) THEN
            # Aggiungo l'utimo pezzo di area ed esco
            SET area = area + ((i_am_Y + start_Y) * (i_am_X - start_X) * 0.5);
            LEAVE rotate;
        END IF;

        # Calcola l'area con segno del trapezio
        SET area = area + ((i_am_Y + go_Y) * (i_am_X - go_X) * 0.5);

        # Segno come coperto il vertice con il quale ho appena eseguito i calcoli
        INSERT INTO vertici_coperti VALUES (i_am_X, i_am_Y);

        # Mi sposto nel vertice nuovo
        SET i_am_X = go_X;
        SET i_am_Y = go_Y;

    END LOOP;

    RETURN ABS(area);

END $$

DROP FUNCTION IF EXISTS metratura_edificio$$
CREATE FUNCTION metratura_edificio (
    id_edificio INT UNSIGNED
)
RETURNS DECIMAL(5,2) NOT DETERMINISTIC READS SQL DATA
BEGIN

    DECLARE area DECIMAL(5,2) DEFAULT 0;
    DECLARE fetch_piano TINYINT;
    DECLARE finito TINYINT DEFAULT 0;

    DECLARE piani CURSOR FOR
    SELECT Numero
    FROM Piano
    WHERE Edificio = id_edificio;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;

    OPEN piani;

    scan_piani: LOOP
        FETCH piani INTO fetch_piano;
        IF finito = 1 THEN LEAVE scan_piani; END IF;
        SET area = area + metratura_piano(id_edificio, fetch_piano);
    END LOOP;

    RETURN area;
END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione D
-- ---------------------------------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS report_materiali$$
CREATE PROCEDURE report_materiali(
    IN anno SMALLINT,
    IN mese TINYINT
)
BEGIN

    WITH utilizzi AS (
        SELECT Ordine, Quantita
        FROM Utilizzo
            WHERE Lavoro IN (
                SELECT ID
                FROM Lavoro
                WHERE StadioAvanzamento IN (
                    SELECT ID
                    FROM StadioAvanzamento
                    WHERE DataFine IS NOT NULL
                          AND YEAR(DataFine) = anno
                          AND MONTH(DataFine) = mese
                    )
            )
    ), utilizzi_per_materiale AS (
        SELECT Materiale AS ID_Materiale, SUM(Quantita) AS Quantita
        FROM utilizzi INNER JOIN Ordine ON Ordine = ID
        GROUP BY Materiale
    )
    SELECT ID_Materiale, Nome, Quantita
    FROM utilizzi_per_materiale INNER JOIN Materiale ON ID_Materiale = ID;

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione E
-- ---------------------------------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS disegna_pianta$$
CREATE PROCEDURE disegna_pianta(
    IN edificio INT UNSIGNED,
    IN piano TINYINT UNSIGNED
)
BEGIN
    DECLARE html TEXT;
    # La dimensione massima del riquadro svg della pianta, ...
    DECLARE svg_max_dimension INT DEFAULT 600;
    # ... tutte le misure vengono scalate per farle stare dentro
    # il fattore di scala viene calcolato guardando la massima x ed y dei muri
    DECLARE scale INT;
    DECLARE max_x INT;
    DECLARE max_y INT;
    # Nel riquadro svg sposta tutto di 5 pixel sennò il browser taglia i bordi
    DECLARE offset INT DEFAULT 5;
    # Variabili dei cursori
    DECLARE fetch_x1 DECIMAL(5,2);
    DECLARE fetch_y1 DECIMAL(5,2);
    DECLARE fetch_x2 DECIMAL(5,2);
    DECLARE fetch_y2 DECIMAL(5,2);
    DECLARE fetch_tipologia VARCHAR(100);
    DECLARE color CHAR(7);
    DECLARE finito TINYINT DEFAULT 0;

    DECLARE muri CURSOR FOR
    SELECT X1, Y1, X2, Y2
    FROM Muro
    WHERE Piano_Edificio = edificio
          AND Piano_Numero = piano;

    DECLARE aperture CURSOR FOR
    SELECT X1, Y1, X2, Y2, Tipologia
    FROM Apertura
    WHERE Piano_Edificio = edificio
          AND Piano_Numero = piano;

    DECLARE sensori CURSOR FOR
    SELECT X, Y
    FROM Sensore
    WHERE Piano_Edificio = edificio
          AND Piano_Numero = piano;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finito = 1;


    # Intestazione
    SET html = '<!DOCTYPE html>
<html>
<body>
<head>
    <style>
    p {
        font-family:''Segoe UI'';
        font-size: 1.2rem;
    }
    </style>
</head>
<div align=center>
<p>Edificio: ';
    SET html = CONCAT(html, edificio, ' | Piano: ', piano, '</p>', CHAR(13)); # CHAR(13) è \n

    # Calcola il fattore di scala e lo imposta nel file html
    SELECT GREATEST(MAX(M.X1), MAX(M.X2)), GREATEST(MAX(M.Y1), MAX(M.Y2))
    FROM Muro M
    WHERE Piano_Edificio = edificio
          AND Piano_Numero = piano
    INTO max_x, max_y;

    SET scale = svg_max_dimension / GREATEST(max_x, max_y);

    SET html = CONCAT(
        html, '<svg style="padding:5px; margin:5px; transform:scaleY(-1)" width="',
        max_x*scale + offset*2, '" height="', max_y*scale + offset*2, '">'
    );  # Offset*2 per tenere conto di entrambi i bordi

    OPEN muri;
    scan_muri: LOOP
        FETCH muri INTO fetch_x1, fetch_y1, fetch_x2, fetch_y2;
        IF finito = 1 THEN LEAVE scan_muri; END IF;
        SET html = CONCAT(html, CHAR(13),
            '<line x1="', fetch_x1*scale + offset,
            '" y1="', fetch_y1*scale + offset,
            '" x2="', fetch_x2*scale + offset,
            '" y2="', fetch_y2*scale + offset,
            '" stroke="black" stroke-width="3px"/>'
        );
    END LOOP;

    SET finito = 0;

    OPEN aperture;
    scan_aperture: LOOP
        FETCH aperture INTO fetch_x1, fetch_y1, fetch_x2, fetch_y2, fetch_tipologia;
        IF finito = 1 THEN LEAVE scan_aperture; END IF;

        # Per le aperture in base alla tipologia imposta un colore
        CASE
            WHEN fetch_tipologia = 'Finestra' THEN SET color = '#2ab2c7';
            WHEN fetch_tipologia = 'Porta' THEN SET color = '#2ac776';
            ELSE SET color = '#c77e2a';
        END CASE;

        SET html = CONCAT(html, CHAR(13),
            '<line x1="', fetch_x1*scale + offset,
            '" y1="', fetch_y1*scale + offset,
            '" x2="', fetch_x2*scale + offset,
            '" y2="', fetch_y2*scale + offset,
            '" stroke="', color,
            '" stroke-width="3px"/>'
        );
    END LOOP;

    SET finito = 0;

    OPEN sensori;
    scan_sensori: LOOP
        FETCH sensori INTO fetch_x1, fetch_y1;
        IF finito = 1 THEN LEAVE scan_sensori; END IF;
        SET html = CONCAT(html, CHAR(13),
            '<circle cx="', fetch_x1*scale + offset,
            '" cy="', fetch_y1*scale + offset,
            '" r="5" fill="#ff2b20"/>'
        );
    END LOOP;

    SET html = CONCAT(html, '
</svg>
</div>
</body>
</html>');

    SELECT html;
    /*
    Volendo si può fare
    INTO OUTFILE 'test.html';
    ma servono dei permessi particolari da mettere nella config di mysql
     */
END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione F
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS paga_oraria$$
CREATE FUNCTION paga_oraria(
    CodFiscale CHAR(16),
    data_calcolo DATE
)
RETURNS DECIMAL(10,2) DETERMINISTIC
BEGIN
    /*
     Ritorna la paga oraria che aveva l'operaio CodFiscale in data Data
     La paga oraria parte da una base paga_oraria_base e scala linearmente
     con gli anni d'esperienza secondo il coefficiente aumento_annuale
     */

    DECLARE paga_oraria_base DECIMAL(10,2) DEFAULT 10;
    DECLARE aumento_annuale DECIMAL(10,2) DEFAULT 1;

    DECLARE anni_esperienza TINYINT;
    DECLARE paga_calcolata DECIMAL(10,2);

    SELECT P.AnniEsperienza
    FROM smartbuildings_db.Personale P
    WHERE P.CodFiscale = CodFiscale
    INTO anni_esperienza;

    IF anni_esperienza IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il codice fiscale non appartiene a nessun operaio';
    END IF;

    IF data_calcolo = CURDATE() THEN
        RETURN paga_oraria_base + anni_esperienza * aumento_annuale;
    END IF;

    SET paga_calcolata = paga_oraria_base + (
        anni_esperienza - TIMESTAMPDIFF(YEAR, data_calcolo, CURDATE())
    ) * aumento_annuale;

    # Se ho messo date strane o vengono conti strani
    IF (paga_calcolata < paga_oraria_base) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La data specificata è troppo avanti o indietro nel tempo';
    END IF;

    RETURN paga_calcolata;
END $$

DROP FUNCTION IF EXISTS costo_materiali$$
CREATE FUNCTION costo_materiali(
    stadio_avanzamento INT UNSIGNED
)
RETURNS DECIMAL(10,2) NOT DETERMINISTIC READS SQL DATA
    RETURN (
        SELECT SUM(U.Quantita * O.PrezzoUnitario)
        FROM Utilizzo U INNER JOIN Ordine O ON U.Ordine = O.ID
        WHERE U.Lavoro IN (
            SELECT L.ID
            FROM Lavoro L
            WHERE L.StadioAvanzamento = stadio_avanzamento
        )
    );

DROP FUNCTION IF EXISTS costo_manodopera$$
CREATE FUNCTION costo_manodopera(
    stadio_avanzamento INT UNSIGNED
)
RETURNS DECIMAL(10,2) NOT DETERMINISTIC READS SQL DATA
    RETURN (
        SELECT SUM(
            TIMESTAMPDIFF(MINUTE, Inizio, Fine)/60
            * paga_oraria(Operaio, DATE(Inizio)) # converto da datetime
        )
        FROM Turno
        WHERE StadioAvanzamento = stadio_avanzamento
    );

DROP FUNCTION IF EXISTS costo_progetto$$
CREATE FUNCTION costo_progetto(
    id_progetto INT UNSIGNED
)
RETURNS DECIMAL(10,2) NOT DETERMINISTIC READS SQL DATA
    RETURN (
        ( # Costo dirigenza
            SELECT SUM(Compenso)
            FROM Dirigenza
            WHERE Progetto = id_progetto
        )
            +
        ( # Costo degli stadi di avanzamento
            SELECT SUM(costo_materiali(ID) + costo_manodopera(ID))
            FROM StadioAvanzamento
            WHERE Progetto = id_progetto
        )
    );

DROP PROCEDURE IF EXISTS termina_progetto;
CREATE PROCEDURE termina_progetto(
    IN id_progetto INT UNSIGNED
)
    UPDATE Progetto SET Costo = costo_progetto(id_progetto) WHERE ID = id_progetto;



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione G
-- ---------------------------------------------------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS report_sensori$$
CREATE PROCEDURE report_sensori(
    IN id_edificio INT UNSIGNED,
    IN timestamp_calcolo DATETIME
)
BEGIN

    /*
    Dato un edificio ed un timestamp, si vuole generare la classifica dei sensori che si discostano di più
    (in percentuale) dai rispettivi valori di soglia; la classifica tiene conto dei soli sensori a basso
    campionamento (fessurimetri, termometri, pluviometri ed igrometri) e viene stilata considerando la
    differenza, tra il valore di soglia e la media del 10% delle misurazioni più alte registrate nelle
    ultime 24 ore dal timestamp specificato.
     */

    WITH misurazioni AS (
        SELECT M.Sensore, S.Tipologia, S.Soglia, S.Importanza, M.X AS Valore,
        # Ogni sensore a basso campionamento registra 48 misurazioni ogni 24 ore, dunque il 10% sono circa 5 misurazioni,
        # per poter prendere le 5 più alte di ogni sensore mi serve assegnare ad ognuna un rank:
               ROW_NUMBER() OVER (
                     PARTITION BY M.Sensore
                     ORDER BY M.X DESC
               ) AS rank_misurazione
        FROM Misurazione M INNER JOIN Sensore S on M.Sensore = S.ID
        WHERE M.Timestamp BETWEEN timestamp_calcolo - INTERVAL 24 HOUR AND timestamp_calcolo
              AND Sensore IN (
                    SELECT ID
                    FROM Sensore
                    WHERE Piano_Edificio = id_edificio
                          AND Tipologia IN ('Fessurimetro', 'Termometro', 'Pluviometro', 'Igrometro')
              )
    )
    SELECT M.Sensore, M.Tipologia, ROUND((AVG(M.Valore) - M.Soglia)/M.Soglia, 2)  AS `Scostamento percentuale`, M.Importanza
    FROM misurazioni M
    WHERE M.rank_misurazione BETWEEN 1 AND 5 # .. così posso filtrare le prime 5
    GROUP BY M.Sensore                       # l'AVG lo calcolo per ogni top 5 di ogni sensore
    ORDER BY `Scostamento percentuale` DESC;

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Operazione H
-- ---------------------------------------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS avg_rischi$$
CREATE FUNCTION avg_rischi(
    area_geografica VARCHAR(255),
    data_calcolo DATE
)

RETURNS DECIMAL(4,2) NOT DETERMINISTIC READS SQL DATA

    /*
    Fa la media dei rischi in vigore in una certa area geografica ad un certo istante nel tempo
    Con "in vigore" si intende gli ultimi misurati, quelli che valgono.
    */

    RETURN (
        SELECT AVG(R1.Coefficiente)
        FROM Rischio R1
        WHERE R1.AreaGeografica = area_geografica
              AND R1.DataMisurazione <= data_calcolo
              AND R1.DataMisurazione >= ALL (
                  SELECT R2.DataMisurazione
                  FROM Rischio R2
                  WHERE R2.AreaGeografica = area_geografica
                        AND R2.DataMisurazione <= data_calcolo
                        AND R2.Tipologia = R1.Tipologia
              )
    );

DROP PROCEDURE IF EXISTS report_territorio$$
CREATE PROCEDURE report_territorio(
    IN area_geografica VARCHAR(255)
)
BEGIN

    /*
     Data un'area geografica, ne si vuole restituire:

     Il trend dei coefficienti, calcolato come la percentuale di incremento o decremento tra i coefficienti
      di rischio in vigore al momento dell'esecuzione e quelli che erano in vigore 6 mesi prima;

     Il trend delle allerte, calcolato come la percentuale di incremento o decremento tra il numero di allerte
      generate dai sensori presenti negli edifici appartenenti all'area geografica e le allerte attese
      (come specificato nella tavola dei volumi, ci si aspetta che accelerometri e giroscopi possano generare
      un'allerta 'fisiologica' al giorno).
     */

    DECLARE avg_rischio_ora DECIMAL(2,1);
    DECLARE avg_rischio_vecchio DECIMAL(2,1);
    DECLARE trend_rischio VARCHAR(255);

    DECLARE data_prima_allerta DATETIME;
    DECLARE allerte_attese INT;
    DECLARE allerte_generate INT;
    DECLARE trend_allerte VARCHAR(255);


    SET avg_rischio_ora = avg_rischi(area_geografica, CURDATE());
    SET avg_rischio_vecchio = avg_rischi(area_geografica, CURDATE() - INTERVAL 6 MONTH );


    IF avg_rischio_ora IS NULL OR avg_rischio_vecchio IS NULL THEN
        SET trend_rischio = NULL;
    ELSEIF avg_rischio_ora = avg_rischio_vecchio THEN
        SET trend_rischio = 'Negli ultimi 6 mesi la media dei coefficienti di rischio dell''area geografica specificata è rimasta stabile';
    ELSE
        SET trend_rischio = CONCAT(
            'Negli ultimi 6 mesi la media dei coefficienti di rischio dell''area geografica specificata è passata da ',
            avg_rischio_vecchio,
            ' a ',
            avg_rischio_ora,
            IF (avg_rischio_ora < avg_rischio_vecchio, ', una diminuzione del ', ', un aumento del '),
            ROUND(avg_rischio_ora/avg_rischio_vecchio * 100 - 100, 1),
            '%'
        );
    END IF;

    /*
     Seleziono la data della prima allerta perchè mi serve per stimare le allerte generate, ad esempio se
     la data della prima allerta presente è di 45 giorni fa io so che, dato che accelerometri e giroscopi
     generano circa un'allerta al giorno, le allerte attese saranno 45 * numero di accelerometri e giroscopi
     */
    SELECT MIN(Misurazione_Timestamp), COUNT(*)
    FROM Allerta
    WHERE Misurazione_Sensore IN (
          SELECT ID
          FROM Sensore
          WHERE Piano_Edificio IN (
                SELECT ID
                FROM Edificio
                WHERE AreaGeografica = area_geografica
          )
    ) INTO data_prima_allerta, allerte_generate;

    SELECT COUNT(*) * TIMESTAMPDIFF(DAY, data_prima_allerta, CURDATE())
    FROM Sensore
    WHERE Tipologia IN ('Accelerometro', 'Giroscopio')
          AND Piano_Edificio IN (
              SELECT ID
              FROM Edificio
              WHERE AreaGeografica = area_geografica
          )
    INTO allerte_attese;

    IF allerte_attese IS NULL OR allerte_generate IS NULL THEN
        SET trend_allerte = NULL;
    ELSEIF allerte_generate = allerte_attese THEN
        SET trend_allerte = 'Le allerte generate dai sensori presenti negli edifici appartenenti all''area geografica specificata sono state esattamente uguali alle aspettative';
    ELSE
        SET trend_allerte = CONCAT(
            'Le allerte generate dai sensori presenti negli edifici appartenenti all''area geografica specificata (',
            allerte_generate,
            ') sono state ',
            IF(allerte_generate < allerte_attese, 'inferiori', 'superiori'),
            ' del ',
             ROUND(allerte_generate/allerte_attese * 100 - 100, 1),
            '% rispetto alle aspettative (',
            allerte_attese,
            ')'
        );
    END IF;

    SELECT trend_rischio AS Trend
    UNION
    SELECT trend_allerte AS Trend;

END $$



-- ---------------------------------------------------------------------------------------------------------------------
-- Eventi e trigger aggiuntivi
-- ---------------------------------------------------------------------------------------------------------------------
DROP EVENT IF EXISTS aggiornamento_anni_esperienza$$
CREATE EVENT aggiornamento_anni_esperienza
ON SCHEDULE EVERY 1 YEAR STARTS CONCAT(YEAR(CURDATE()) + 1, '-01-01 00:00:00')
DO
    UPDATE Personale
    SET AnniEsperienza = AnniEsperienza + 1
    WHERE Attivo = 1;

DROP EVENT IF EXISTS cancellazione_misure_vecchie$$
CREATE EVENT cancellazione_misure_vecchie
ON SCHEDULE EVERY 1 MONTH
DO
    DELETE FROM Misurazione WHERE Timestamp < CURDATE() - INTERVAL 1 MONTH ;

DROP TRIGGER IF EXISTS controllo_superamento_soglia$$
CREATE TRIGGER controllo_superamento_soglia
AFTER INSERT ON Misurazione
FOR EACH ROW
BEGIN

    IF (
        SELECT Tipologia
        FROM Sensore
        WHERE ID = NEW.Sensore
    ) IN (
        'Fessurimetro',
        'Termometro',
        'Pluviometro',
        'Igrometro'
    ) THEN

        IF New.X >= (
            SELECT Soglia
            FROM Sensore
            WHERE ID = NEW.Sensore
        ) THEN
            INSERT INTO Allerta VALUES (NEW.Sensore, NEW.Timestamp);
        END IF;

    ELSE # Per accelerometri e giroscopi si confronta il modulo

        IF SQRT(
            NEW.X * NEW.X
            + NEW.Y * NEW.Y
            + NEW.Z * NEW.Z
        ) >= (
            SELECT Soglia
            FROM Sensore
            WHERE ID = NEW.Sensore
        ) THEN
            INSERT INTO Allerta VALUES (NEW.Sensore, NEW.Timestamp);
        END IF;

    END IF;

END $$
