USE smartbuildings_db;
DELIMITER $$


/*
 (VG 1) Ogni muro che si vuole inserire deve avere almeno un vertice in comune
 con un muro già esistente dello stesso piano dello stesso edificio e non deve
 sovrapporsi completamente ad esso
 */
DROP TRIGGER IF EXISTS VG1$$
CREATE TRIGGER VG1
BEFORE INSERT ON Muro
FOR EACH ROW
BEGIN

    /*
     Per semplicità questo vincolo non tiene conto del fatto che i muri
     possano essere intersecati o parzialmente sovrapposti, assicura
     solamente che che i muri non siano messi totalmente a caso
     */

    DECLARE is_primo_muro TINYINT DEFAULT 0;
    DECLARE ha_vertici_in_comune TINYINT DEFAULT 0;
    DECLARE is_sovrapposto_completamente TINYINT DEFAULT 0;

    # Il muro è il primo che inserisco
    SET is_primo_muro = NOT EXISTS(
            SELECT 1
            FROM Muro
            WHERE Piano_Numero = NEW.Piano_Numero
                  AND Piano_Edificio = NEW.Piano_Edificio
    );

    # Il muro ha almeno un vertice in comune con un muro già presente
    SET ha_vertici_in_comune = EXISTS(
        SELECT 1
        FROM Muro
        WHERE Piano_Numero = NEW.Piano_Numero
              AND Piano_Edificio = NEW.Piano_Edificio
              AND (
                  (X1 = NEW.X1 AND Y1 = NEW.Y1)     # Il vertice X1,Y1 nuovo è tra i vertici X1,Y1 esistenti
                  OR (X2 = NEW.X1 AND Y2 = NEW.Y1)  # Il vertice X1,Y1 nuovo è tra i vertici X2,Y2 esistenti
                  OR (X1 = NEW.X2 AND Y1 = NEW.Y2)  # Il vertice X2,Y2 nuovo è tra i vertici X1,Y1 esistenti
                  OR (X2 = NEW.X2 AND Y2 = NEW.Y2)  # Il vertice X2,Y2 nuovo è tra i vertici X2,Y2 esistenti
              )
    );

    # Il muro si sovrappone completamente con un muro già esistente
    SET is_sovrapposto_completamente = EXISTS(
        SELECT 1
        FROM Muro
        WHERE Piano_Numero = NEW.Piano_Numero
              AND Piano_Edificio = NEW.Piano_Edificio
              AND (
                  (X1 = NEW.X1 AND Y1 = NEW.Y1 AND X2 = NEW.X2 AND Y2 = NEW.Y2)
                  OR (X2 = NEW.X1 AND Y2 = NEW.Y1 AND X1 = NEW.X2 AND Y1 = NEW.Y2)
              )
    );

    IF
        # Se il muro non è il primo che inserisco
        NOT is_primo_muro
        # ed inoltre
        AND (
            # o non ha vertici in comune con un muro già presente
            NOT ha_vertici_in_comune
            # o li ha ma si sovrappone completamente ad un muro già presente
            OR is_sovrapposto_completamente
        )
        # allora il vincolo non è rispettato
    THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il muro da inserire deve avere almeno un vertice in comune con un muro già esistente';
    END IF;

END $$



/*
 (VG 2)  Una parete deve essere composta da un muro ed un vano appartenenti allo stesso
 piano dello stesso edificio ed ogni muro deve essere associato ad al più due pareti.
 */
DROP TRIGGER IF EXISTS VG2$$
CREATE TRIGGER VG2
BEFORE INSERT ON Parete
FOR EACH ROW
BEGIN

    DECLARE ID_Edificio INT UNSIGNED;
    DECLARE Piano_target TINYINT UNSIGNED;

    # Controllo che il muro e il vano siano nello stesso edificio
    SET ID_Edificio = (SELECT Piano_Edificio
                       FROM Muro
                       WHERE ID = NEW.Muro
    );

    IF ID_Edificio <> (SELECT Piano_Edificio
                       FROM Vano
                       WHERE ID = NEW.Vano)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il vano e il muro appartengono a due edifici diversi';
    END IF;

    # Controllo che il muro e il vano siano sullo stesso piano
    SET Piano_target = (SELECT Piano_Numero
                        FROM Muro
                        WHERE ID = NEW.Muro
    );

    IF Piano_target <> (SELECT Piano_Numero
                        FROM Vano
                        WHERE ID = NEW.Vano)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il vano e il muro non appartengono allo stesso piano';
    END IF;

    # Controllo che il muro non sia già associato a due pareti
    IF 2 = (
        SELECT COUNT(*)
        FROM Parete
        WHERE Muro = NEW.Muro
    )
    THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Il muro è già associato a due pareti';
    END IF;

END $$



/*
 (VG 3) Un'apertura deve essere contenuta per intero in almeno un muro dello stesso piano dello stesso edificio.
 */
DROP FUNCTION IF EXISTS MY_MIN$$
CREATE FUNCTION MY_MIN(A DECIMAL(5,2), B DECIMAL(5,2))
RETURNS DECIMAL(5,2) DETERMINISTIC
    RETURN IF(A < B, A, B);

DROP FUNCTION IF EXISTS MY_MAX$$
CREATE FUNCTION MY_MAX(A DECIMAL(5,2), B DECIMAL(5,2))
RETURNS DECIMAL(5,2) DETERMINISTIC
    RETURN IF(A > B, A, B);

DROP TRIGGER IF EXISTS VG3$$
CREATE TRIGGER VG3
BEFORE INSERT ON Apertura
FOR EACH ROW
BEGIN

    /*
     Per semplicità questo vincolo non tiene conto del fatto che le
     aperture possano essere intersecate o parzialmente sovrapposte,
     assicura solamente che non siano messe totalmente a caso
     */

    # Deve esistere almeno un muro che:
    IF NOT EXISTS(
        SELECT 1
        FROM Muro
             WHERE Piano_Edificio = NEW.Piano_Edificio
                   AND Piano_Numero = NEW.Piano_Numero
                   # può contenere interamente l'apertura
                   AND (
                       # [per contenerla deve essere vero che la più piccola x del muro deve essere minore
                       #  della più piccola x dell'apertura e stessa cosa per il maggiore e per la y...]
                       MY_MIN(NEW.X1, NEW.X2) >= MY_MIN(X1, X2)
                       AND MY_MAX(NEW.X1, NEW.X2) <= MY_MAX(X1, X2)
                       AND MY_MIN(NEW.Y1, NEW.Y2) >= MY_MIN(Y1, Y2)
                       AND MY_MAX(NEW.Y1, NEW.Y2) <= MY_MAX(Y1, Y2)
                   )
                   # e, se questo succede, allora ci sono due casi:
                   AND (
                       IF (
                           X2 = X1 OR Y2 = Y2,

                           # O il muro è orizzontale/verticale, ma allora il vincolo sopra basta
                           #  a garantire che l'apertura sia esattamente sovrapposta ad esso
                           TRUE,

                           # Oppure devo controllare che i vertici dell'apertura soddisfino
                           #  l'equazione della retta che passa per i vertici del muro
                           #  ossia y=m(x-x0)+y0 dove x0=x1, y0=y1 e m=(Y2-Y1)/(X2-X1)
                           # Nota: DECIMAL(5,2) assicura che questa operazione sia
                           #  numericamente stabile e che non restituisca falsi positivi
                           #  dovuti ad approssimazioni
                           NEW.Y1 = ((Y2-Y1)/(X2-X1)) * (NEW.X1-X1) + Y1        # Il vertice NEW.X1, NEW.Y1 la soddisfa
                           AND NEW.Y2 = ((Y2-Y1)/(X2-X1)) * (NEW.X2-X1) + Y1    # Il vertice NEW.X2, NEW.Y2 la soddisfa
                       )
                   )
    ) OR (
            # L'apertura si sovrappone completamente con una già esistente
            EXISTS(
                SELECT 1
                FROM Apertura
                WHERE Piano_Numero = NEW.Piano_Numero
                      AND Piano_Edificio = NEW.Piano_Edificio
                      AND (
                          (X1 = NEW.X1 AND Y1 = NEW.Y1 AND X2 = NEW.X2 AND Y2 = NEW.Y2)
                          OR (X2 = NEW.X1 AND Y2 = NEW.Y1 AND X1 = NEW.X2 AND Y1 = NEW.Y2)
                      )
            )
        )
    THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'L''apertura deve essere interamente contenuta in un muro';
    END IF;

END $$



/*
 (VG 4) Ogni Materiale può essere al più uno tra MattoneForato e Piastrella.
 */
DROP TRIGGER IF EXISTS VG4_MattoneForato$$
CREATE TRIGGER VG4_MattoneForato
BEFORE INSERT ON MattoneForato
FOR EACH ROW
BEGIN

    # Controllo se e' gia' presente in Piastrella
    IF 1 = (SELECT COUNT(*)
            FROM Piastrella
            WHERE Piastrella.Materiale = NEW.Materiale)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il materiale è già classificato come piastrella';
    END IF;

END $$

DROP TRIGGER IF EXISTS VG4_Piastrella$$
CREATE TRIGGER VG4_Piastrella
BEFORE INSERT ON Piastrella
FOR EACH ROW
BEGIN

    # Controllo se e' gia' presente in MattoneForato
    IF 1 = (SELECT COUNT(*)
            FROM MattoneForato
            WHERE MattoneForato.Materiale = NEW.Materiale)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il materiale e gia classificato come Mattone Forato';
    END IF;

END $$



/*
 (VG 6) Non è possibile inserire un progetto edilizio se ne è ancora in corso un altro per lo stesso edificio.
 */
DROP TRIGGER IF EXISTS VG6$$
CREATE TRIGGER VG6
BEFORE INSERT ON Progetto
FOR EACH ROW
BEGIN

    IF EXISTS(
        SELECT 1
        FROM Progetto
        WHERE Edificio = NEW.Edificio
              AND Costo = NULL
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Esiste ancora un progetto in corso per tale edificio';
    END IF;

END $$



/*
 (VG 7) Gli stadi di avanzamento dello stesso progetto non si sovrappongono ed il
 primo di questi può iniziare solamente dopo la data di approvazione del progetto.
 */
DROP TRIGGER IF EXISTS VG7$$
CREATE TRIGGER VG7
BEFORE INSERT ON StadioAvanzamento
FOR EACH ROW
BEGIN

    DECLARE data_approvazione DATE;

    # Controllo sovrapposizione
    IF 0 < (SELECT COUNT(*)
            FROM StadioAvanzamento
            WHERE Progetto = NEW.Progetto
                AND (DataFine IS NOT NULL OR DataFine > NEW.DataInizio))
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ci puo essere un solo stadio di avanzamento alla volta';
    END IF;

    SET data_approvazione = (SELECT DataApprovazione
                             FROM Progetto
                             WHERE ID = NEW.Progetto);
    IF (data_approvazione IS NULL)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Impossibile inserire lo Stadio di Avanzamento se il progetto non risulta approvato';
    ELSEIF (data_approvazione > NEW.DataInizio)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il primo stadio di avanzamento deve iniziare dopo l''approvazione del progetto';
    END IF;

END $$



/*
 (VG 8) Uno stadio di avanzamento può terminare solo se tutti i lavori al suo interno sono terminati.
 */
DROP TRIGGER IF EXISTS VG8$$
CREATE TRIGGER VG8
AFTER UPDATE ON StadioAvanzamento
FOR EACH ROW
BEGIN

    IF NEW.DataFine IS NOT NULL AND EXISTS(
        SELECT 1
        FROM Lavoro
        WHERE StadioAvanzamento = NEW.ID
              AND Terminato = 0
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Uno stadio di avanzamento può terminare solo se tutti i lavori al suo interno sono terminati';
    END IF;

END $$



/*
 (VG 9) Ogni lavoro può essere al più uno tra InterventoVano, InterventoParete ed InterventoMuro
 e tutti i lavori dello stesso progetto devono essere effettuati sullo stesso edificio
 */
DROP FUNCTION IF EXISTS esistono_lavori$$
CREATE FUNCTION esistono_lavori (id_lavoro INT UNSIGNED)
RETURNS TINYINT NOT DETERMINISTIC READS SQL DATA
    RETURN (
        (
            SELECT COUNT(*)
            FROM InterventoParete
            WHERE InterventoParete.Lavoro = id_lavoro
        ) + (
            SELECT COUNT(*)
            FROM InterventoVano
            WHERE InterventoVano.Lavoro = id_lavoro
        ) + (
            SELECT COUNT(*)
            FROM InterventoMuro
            WHERE InterventoMuro.Lavoro = id_lavoro
        )
    );

DROP TRIGGER IF EXISTS VG9_InterventoMuro$$
CREATE TRIGGER VG9_InterventoMuro
BEFORE INSERT ON InterventoMuro
FOR EACH ROW
BEGIN

    DECLARE ID_Edificio INT UNSIGNED;

    IF esistono_lavori(NEW.Lavoro) > 1
        THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ogni lavoro deve essere al più uno tra InterventoVano, InterventoParete ed InterventoMuro';
    END IF;

    # Controllo che il muro appartenga all'edificio giusto
    SET ID_Edificio = (SELECT Edificio
                       FROM InterventoMuro
                            INNER JOIN
                            Lavoro ON InterventoMuro.Lavoro = Lavoro.ID
                            INNER JOIN
                            StadioAvanzamento ON Lavoro.StadioAvanzamento = StadioAvanzamento.ID
                            INNER JOIN
                            Progetto ON StadioAvanzamento.Progetto = Progetto.ID
                       WHERE Lavoro.ID = NEW.Lavoro
    );
    IF ID_Edificio <> (SELECT Piano_Edificio
                       FROM Muro
                       WHERE ID = NEW.Muro)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il muro non appartiene all edificio giusto';
    END IF;

END $$

DROP TRIGGER IF EXISTS VG9_InterventoVano$$
CREATE TRIGGER VG9_InterventoVano
BEFORE INSERT ON InterventoVano
FOR EACH ROW
BEGIN

    DECLARE ID_Edificio INT UNSIGNED;

    IF esistono_lavori(NEW.Lavoro)
        THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ogni lavoro deve essere al più uno tra InterventoVano, InterventoParete ed InterventoMuro';
    END IF;

    # Controllo che il vano appartenga all'edificio giusto
    SET ID_Edificio = (SELECT Edificio
                       FROM InterventoVano
                            INNER JOIN
                            Lavoro ON InterventoVano.Lavoro = Lavoro.ID
                            INNER JOIN
                            StadioAvanzamento ON Lavoro.StadioAvanzamento = StadioAvanzamento.ID
                            INNER JOIN
                            Progetto ON StadioAvanzamento.Progetto = Progetto.ID
                       WHERE Lavoro.ID = NEW.Lavoro
    );
    IF ID_Edificio <> (SELECT Piano_Edificio
                       FROM Muro
                       WHERE ID = NEW.Vano)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il muro non appartiene all edificio giusto';
    END IF;

END $$

DROP TRIGGER IF EXISTS VG9_InterventoParete$$
CREATE TRIGGER VG9_InterventoParete
BEFORE INSERT ON InterventoParete
FOR EACH ROW
BEGIN

    DECLARE ID_Edificio INT UNSIGNED;

    IF esistono_lavori(NEW.Lavoro)
        THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ogni lavoro deve essere al più uno tra InterventoVano, InterventoParete ed InterventoMuro';
    END IF;

    # Controllo che la parete appartenga all'edificio giusto
    SET ID_Edificio = (SELECT Edificio
                       FROM InterventoParete
                            INNER JOIN
                            Lavoro ON InterventoParete.Lavoro = Lavoro.ID
                            INNER JOIN
                            StadioAvanzamento ON Lavoro.StadioAvanzamento = StadioAvanzamento.ID
                            INNER JOIN
                            Progetto ON StadioAvanzamento.Progetto = Progetto.ID
                       WHERE Lavoro.ID = NEW.Lavoro
    );
    IF ID_Edificio <> (SELECT Piano_Edificio
                       FROM Muro
                       WHERE Muro.ID = NEW.Parete_Muro)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il muro non appartiene all edificio giusto';
    END IF;

END $$



/*
 (VG 10) Tutto il personale impiegato nella relazione dirigenza deve essere personale attivo.
 */
DROP TRIGGER IF EXISTS VG10$$
CREATE TRIGGER VG10
BEFORE INSERT ON Dirigenza
FOR EACH ROW
BEGIN

    IF 0 = (SELECT Attivo
            FROM Personale
            WHERE CodFiscale = NEW.Personale)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il dirigente deve essere tra il personale attivo per poter essere inserito';
    END IF;

END $$



/*
(VG 11) Si può contribuire ad un lavoro se e solo se questo non è terminato ed appartiene
allo stesso stadio di avanzamento del turno, inoltre, per ogni turno, la somma delle ore
di contribuzione ai vari lavori non può superare la durata del turno.
 */
DROP TRIGGER IF EXISTS VG11$$
CREATE TRIGGER VG11
BEFORE INSERT ON Contribuzione
FOR EACH ROW
BEGIN

    DECLARE stadio_avanzamento_target INT UNSIGNED;
    DECLARE durata_turno DECIMAL(2,1);
    DECLARE ore_di_contribuzione DECIMAL(2,1);

    # Controllo che il lavoro non sia terminato
    IF 1 = (SELECT Terminato
            FROM Lavoro
            WHERE ID = NEW.Lavoro)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Il lavoro è già terminato';
    END IF;

    # Controllo appartenenza StadioAvanzamento
    SET stadio_avanzamento_target = (SELECT StadioAvanzamento
                                     FROM Turno
                                     WHERE NEW.Turno = Turno.ID
    );
    IF stadio_avanzamento_target <> (SELECT StadioAvanzamento
                                     FROM Lavoro
                                     WHERE NEW.Lavoro = Lavoro.ID)
        THEN SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Lavoro e turno appartengono a due stadi di avanzamento diversi';
    END IF;


    # Per ogni turno, la somma delle ore di contribuzione ai vari lavori non può superare la durata del turno.

    SET durata_turno = (
        SELECT TIMESTAMPDIFF(MINUTE, Inizio, Fine) / 60
        FROM Turno
        WHERE ID = NEW.Turno
    );

    SET ore_di_contribuzione = IFNULL (
        (
            SELECT SUM(Ore)
            FROM Contribuzione
            WHERE Turno = NEW.Turno
        ), 0
    ) + NEW.Ore;

    IF ore_di_contribuzione > durata_turno
        THEN SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Monte ore del turno superato';
    END IF;

END $$



/*
 (VG 13) Non è possibile modificare il valore di soglia di un sensore se questo ha record
 nell'entità misurazione, infatti ci potrebbe essere una misurazione che con la nuova
 soglia avrebbe dovuto generare un'allerta che invece non è presente.
 */
DROP TRIGGER IF EXISTS VG13$$
CREATE TRIGGER VG13
BEFORE UPDATE ON Sensore
FOR EACH ROW
BEGIN
    IF NEW.Soglia != OLD.Soglia
        AND EXISTS (SELECT 1
                    FROM Misurazione
                    WHERE Sensore = OLD.ID
        )
        THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Impossibile modificare la soglia di allerta, rimuovere le misurazioni precedenti per procedere';
    END IF;
END $$



/*
 (VG 14) Non possono esistere due sensori dello stesso tipo nello stesso identico punto di un edificio.
 */
DROP TRIGGER IF EXISTS VG14$$
CREATE TRIGGER VG14
BEFORE INSERT ON Sensore
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Sensore
        WHERE Piano_Numero = NEW.Piano_Numero
              AND Piano_Edificio = NEW.Piano_Edificio
              AND X = NEW.X
              AND Y = NEW.Y
              AND Z = NEW.Z
              AND Tipologia = NEW.Tipologia
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Esiste già un sensore di questo tipo in questo punto';
    END IF;
END $$
