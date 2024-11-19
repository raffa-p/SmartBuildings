USE smartbuildings_db;



-- ---------------------------------------------------------------------------------------------------------------------
-- Test delle operazioni
-- ---------------------------------------------------------------------------------------------------------------------

/*
 Operazione B
 */
CALL inserisci_turno(1, 'DDDDDDDDDDDDDDDD', 'DDDDDDDDDDDDDDDD',
    '2020-12-02 10:00:00', '2020-12-02 18:00:00');
CALL inserisci_turno(1, 'AAAAAAAAAAAAAAAA', 'DDDDDDDDDDDDDDDD',
    '2020-12-02 13:00:00', '2020-12-02 15:00:00');
CALL inserisci_turno(1, 'BBBBBBBBBBBBBBBB', 'DDDDDDDDDDDDDDDD',
    '2020-12-02 11:00:00', '2020-12-02 17:00:00');
INSERT INTO Contribuzione(Lavoro, Turno, Ore) VALUES
    (1, 1, 7),
    (1, 2, 1.5),
    (1, 3, 5);

/*
 Operazione A
 */
CALL inserisci_utilizzi(1, 1, 600);
CALL inserisci_utilizzi(1, 2, 20);
CALL inserisci_utilizzi(1, 3, 15);
CALL inserisci_utilizzi(1, 4, 3);
UPDATE Lavoro SET Terminato = 1 WHERE ID = 1;
UPDATE StadioAvanzamento SET DataFine = '2020-12-23' WHERE ID = 1;

/*
 Operazione D
 */
# Dovrebbe ritornare gli utilizzi elencati sopra
CALL report_materiali(2020, 12);

/*
 Operazione C
 */
# Dovrebbe ritornare 64*3=192 e 10.5
SELECT metratura_edificio(1), metratura_edificio(99);

/*
 Operazione E
 */
# Dovrebbe essere come la foto nella documentazione
CALL disegna_pianta(1,0);
# Dovrebbe essere un poligono concavo
CALL disegna_pianta(99,0);

/*
 Operazione F
 */
 # Dovrebbe essere circa 350k
CALL termina_progetto(1);
SELECT Costo FROM Progetto WHERE ID = 1;

/*
 Operazione G
 */
# Dovrebbe ritornare gli utilizzi elencati sopra
CALL report_sensori(1, '2023-01-20 23:59:59');

/*
 Operazione H
 */
# Dovrebbe dire che il rischio è diminuito e che le allerte sono molto inferiori alla norma
CALL report_territorio('43010');



-- ---------------------------------------------------------------------------------------------------------------------
-- Test dell'Analytics 1
-- ---------------------------------------------------------------------------------------------------------------------
# Dovrebbe restituire 12 record con rigidezza = 10
CALL consiglia_interventi(1, '2023-02-01', 10);
# Dovrebbe restituire 3 record con rigidezza = 2
CALL consiglia_interventi(1, '2023-02-01', 2);
# Dovrebbe restituire 9 record con rigidezza = 10
CALL consiglia_interventi(1, '2023-01-31', 10);
# Dovrebbe restituire 3 record con rigidezza = 2
CALL consiglia_interventi(1, '2023-01-31', 2);


-- ---------------------------------------------------------------------------------------------------------------------
-- Test dell'Analytics 2
-- ---------------------------------------------------------------------------------------------------------------------

# Test della parte sullo stato di un edificio
SELECT
    # Rischi ambientale e strutturale relativi al periodo nuovo, dovrebbe essere nella media
    rischio(1,'2023-01-31',TRUE,TRUE) AS ambientale_nuovo,
 	rischio(1,'2023-01-31',FALSE,TRUE) AS strutturale_nuovo,

	# Rischi ambientale e strutturale relativi al periodo vecchio, dovrebbero essere bassi
	rischio(1,'2023-01-31',TRUE,FALSE) AS ambientale_vecchio,
	rischio(1,'2023-01-31',FALSE,FALSE) AS strutturale_vecchio,

	# Stato dell'edificio, combina i due valori sopra, dovrebbe essere nella media
	stato_edificio(1, '2023-01-31') AS Stato;


# Test della parte sulla calamità
CALL stima_intensita_calamita('2023-01-31 10:01:00');
SELECT
    # Distanza tra l'edificio e la calamitò, dovrebbe essere 42 KM
    distanza_coordinate(10.236771, 44.069816, 10.388135, 43.720942) AS  Distanza,

    # Dovrebbero restituire circa 0.12 e 0.08
    peak_ground_measurements('2023-01-31 10:01:00', 1, 'Accelerometro') AS PGA,
    peak_ground_measurements('2023-01-31 10:01:00', 1, 'Giroscopio') AS PGR,

    # Dovrebbe essere circa 7
    Intensita,

    # I due valori dovrebbero essere circa uguali
    PGV_to_mercalli(
        0.5 * peak_ground_measurements('2023-01-31 10:01:00', 1, 'Accelerometro')
           + 0.5 * peak_ground_measurements('2023-01-31 10:01:00', 1, 'Giroscopio')
    ) AS Intensita_Misurata,
    stima_intensita_percepita('2023-01-31 10:01:00', 42) AS Intensita_Stimata,

    # Data una percentuale di distruzione di circa il 27% ed un progetto da circa 350k dovrebbe essere sui 93k
    stima_danni('2023-01-31 10:01:00', 1) AS Danni
FROM Calamita
WHERE Timestamp = '2023-01-31 10:01:00';