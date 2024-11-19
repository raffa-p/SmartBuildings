SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';


-- -----------------------------------------------------
-- Schema smartbuildings_db
-- -----------------------------------------------------
DROP SCHEMA IF EXISTS `smartbuildings_db` ;
CREATE SCHEMA IF NOT EXISTS `smartbuildings_db` DEFAULT CHARACTER SET utf8mb4 ;
USE `smartbuildings_db` ;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Allerta`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Allerta` (
  `Misurazione_Sensore` INT UNSIGNED NOT NULL,
  `Misurazione_Timestamp` DATETIME(6) NOT NULL,
  PRIMARY KEY (`Misurazione_Sensore`, `Misurazione_Timestamp`),
  CONSTRAINT `fk_Allerta_Misurazione`
    FOREIGN KEY (`Misurazione_Sensore` , `Misurazione_Timestamp`)
    REFERENCES `smartbuildings_db`.`Misurazione` (`Sensore` , `Timestamp`)
    ON DELETE CASCADE
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Apertura`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Apertura` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Piano_Numero` TINYINT UNSIGNED NOT NULL,
  `Piano_Edificio` INT UNSIGNED NOT NULL,
  `X1` DECIMAL(5,2) NOT NULL CHECK (X1 >= 0),
  `Y1` DECIMAL(5,2) NOT NULL CHECK (Y1 >= 0),
  `X2` DECIMAL(5,2) NOT NULL CHECK (X2 >= 0),
  `Y2` DECIMAL(5,2) NOT NULL CHECK (Y2 >= 0),
  `Z` DECIMAL(5,2) NOT NULL CHECK (Z >= 0),
  `Altezza` DECIMAL(5,2) NOT NULL CHECK (Altezza > 0),
  `Tipologia` VARCHAR(100) NOT NULL,
  `Orientamento` CHAR(2) NULL DEFAULT NULL CHECK (Orientamento IN ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')),
  CHECK (ABS(X2-X1) + ABS(Y2-Y1) != 0),
  PRIMARY KEY (`ID`),
  INDEX `fk_Apertura_Piano_idx` (`Piano_Numero` ASC, `Piano_Edificio` ASC) VISIBLE,
  CONSTRAINT `fk_Apertura_Piano`
    FOREIGN KEY (`Piano_Numero` , `Piano_Edificio`)
    REFERENCES `smartbuildings_db`.`Piano` (`Numero` , `Edificio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`AreaGeografica`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`AreaGeografica` (
  `CodPostale` VARCHAR(255) NOT NULL,
  PRIMARY KEY (`CodPostale`))
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Calamita`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Calamita` (
  `Timestamp` DATETIME NOT NULL,
  `Latitudine` DECIMAL(9,6) NOT NULL CHECK (Latitudine BETWEEN -90 AND 90),
  `Longitudine` DECIMAL(9,6) NOT NULL CHECK (Longitudine BETWEEN -180 AND 180),
  `Tipologia` VARCHAR(100) NOT NULL,
  `Intensita` DECIMAL(4,2) NULL DEFAULT NULL,
  PRIMARY KEY (`Timestamp`))
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Contribuzione`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Contribuzione` (
  `Lavoro` INT UNSIGNED NOT NULL,
  `Turno` INT UNSIGNED NOT NULL,
  `Ore` DECIMAL(2,1) NOT NULL CHECK (Ore > 0),
  PRIMARY KEY (`Lavoro`, `Turno`),
  INDEX `fk_Contribuzione_Turno_idx` (`Turno` ASC) VISIBLE,
  CONSTRAINT `fk_Contribuzione_Lavoro`
    FOREIGN KEY (`Lavoro`)
    REFERENCES `smartbuildings_db`.`Lavoro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Contribuzione_Turno`
    FOREIGN KEY (`Turno`)
    REFERENCES `smartbuildings_db`.`Turno` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Dirigenza`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Dirigenza` (
  `Progetto` INT UNSIGNED NOT NULL,
  `Personale` CHAR(16) NOT NULL,
  `Ruolo` VARCHAR(45) NOT NULL,
  `Compenso` DECIMAL(10,2) NOT NULL CHECK (Compenso > 0),
  PRIMARY KEY (`Progetto`, `Personale`),
  INDEX `fk_Dirigenza_Personale_idx` (`Personale` ASC) VISIBLE,
  CONSTRAINT `fk_Dirigenza_Progetto`
    FOREIGN KEY (`Progetto`)
    REFERENCES `smartbuildings_db`.`Progetto` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Dirigenza_Personale`
    FOREIGN KEY (`Personale`)
    REFERENCES `smartbuildings_db`.`Personale` (`CodFiscale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Edificio`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Edificio` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `AreaGeografica` VARCHAR(255) NOT NULL,
  `Latitudine` DECIMAL(9,6) NOT NULL CHECK (Latitudine BETWEEN -90 AND 90),
  `Longitudine` DECIMAL(9,6) NOT NULL CHECK (Longitudine BETWEEN -180 AND 180),
  `Tipologia` VARCHAR(100) NOT NULL,
  PRIMARY KEY (`ID`),
  INDEX `fk_Edificio_AreaGeografica_idx` (`AreaGeografica` ASC) VISIBLE,
  CONSTRAINT `fk_Edificio_AreaGeografica`
    FOREIGN KEY (`AreaGeografica`)
    REFERENCES `smartbuildings_db`.`AreaGeografica` (`CodPostale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Evento`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Evento` (
  `AreaGeografica` VARCHAR(255) NOT NULL,
  `Calamita` DATETIME NOT NULL,
  PRIMARY KEY (`AreaGeografica`, `Calamita`),
  INDEX `fk_Evento_Calamita_idx` (`Calamita` ASC) VISIBLE,
  CONSTRAINT `fk_Evento_AreaGeografica`
    FOREIGN KEY (`AreaGeografica`)
    REFERENCES `smartbuildings_db`.`AreaGeografica` (`CodPostale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Evento_Calamita`
    FOREIGN KEY (`Calamita`)
    REFERENCES `smartbuildings_db`.`Calamita` (`Timestamp`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`InterventoMuro`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`InterventoMuro` (
  `Lavoro` INT UNSIGNED NOT NULL,
  `Muro` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`Lavoro`, `Muro`),
  INDEX `fk_InterventoMuro_Muro_idx` (`Muro` ASC) VISIBLE,
  CONSTRAINT `fk_InterventoMuro_Lavoro`
    FOREIGN KEY (`Lavoro`)
    REFERENCES `smartbuildings_db`.`Lavoro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_InterventoMuro_Muro`
    FOREIGN KEY (`Muro`)
    REFERENCES `smartbuildings_db`.`Muro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`InterventoParete`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`InterventoParete` (
  `Lavoro` INT UNSIGNED NOT NULL,
  `Parete_Vano` INT UNSIGNED NOT NULL,
  `Parete_Muro` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`Lavoro`, `Parete_Vano`, `Parete_Muro`),
  INDEX `fk_InterventoParete_Parete_idx` (`Parete_Vano` ASC, `Parete_Muro` ASC) VISIBLE,
  CONSTRAINT `fk_InterventoParete_Lavoro`
    FOREIGN KEY (`Lavoro`)
    REFERENCES `smartbuildings_db`.`Lavoro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_InterventoParete_Parete`
    FOREIGN KEY (`Parete_Vano` , `Parete_Muro`)
    REFERENCES `smartbuildings_db`.`Parete` (`Vano` , `Muro`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`InterventoVano`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`InterventoVano` (
  `Lavoro` INT UNSIGNED NOT NULL,
  `Vano` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`Lavoro`, `Vano`),
  INDEX `fk_InterventoVano_Vano_idx` (`Vano` ASC) VISIBLE,
  CONSTRAINT `fk_InterventoVano_Lavoro`
    FOREIGN KEY (`Lavoro`)
    REFERENCES `smartbuildings_db`.`Lavoro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_InterventoVano_Vano`
    FOREIGN KEY (`Vano`)
    REFERENCES `smartbuildings_db`.`Vano` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Lavoro`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Lavoro` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `StadioAvanzamento` INT UNSIGNED NOT NULL,
  `Terminato` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `Indicazioni` VARCHAR(255) NULL DEFAULT NULL,
  PRIMARY KEY (`ID`),
  INDEX `fk_Lavoro_StadioAvanzamento_idx` (`StadioAvanzamento` ASC) VISIBLE,
  CONSTRAINT `fk_Lavoro_StadioAvanzamento`
    FOREIGN KEY (`StadioAvanzamento`)
    REFERENCES `smartbuildings_db`.`StadioAvanzamento` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Materiale`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Materiale` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Nome` VARCHAR(45) NOT NULL,
  `Costituenti` VARCHAR(100) NOT NULL,
  `Impiego` VARCHAR(100) NOT NULL,
  `Lunghezza` DECIMAL(5,2) NULL DEFAULT NULL CHECK (Lunghezza > 0),
  `Larghezza` DECIMAL(5,2) NULL DEFAULT NULL CHECK (Larghezza > 0),
  `Altezza` DECIMAL(5,2) NULL DEFAULT NULL CHECK (Altezza > 0),
  PRIMARY KEY (`ID`))
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`MattoneForato`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`MattoneForato` (
  `Materiale` INT UNSIGNED NOT NULL,
  `FormaAlveolatura` VARCHAR(45) NOT NULL,
  `MaterialeAlveolatura` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`Materiale`),
  CONSTRAINT `fk_MattoneForato_Materiale`
    FOREIGN KEY (`Materiale`)
    REFERENCES `smartbuildings_db`.`Materiale` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Misurazione`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Misurazione` (
  `Sensore` INT UNSIGNED NOT NULL,
  `Timestamp` DATETIME(6) NOT NULL,
  `X` DECIMAL(9,6) NOT NULL,
  `Y` DECIMAL(9,6) NULL DEFAULT NULL,
  `Z` DECIMAL(9,6) NULL DEFAULT NULL,
  PRIMARY KEY (`Sensore`, `Timestamp`),
  CONSTRAINT `fk_Misurazione_Sensore`
    FOREIGN KEY (`Sensore`)
    REFERENCES `smartbuildings_db`.`Sensore` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Muro`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Muro` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Piano_Numero` TINYINT UNSIGNED NOT NULL,
  `Piano_Edificio` INT UNSIGNED NOT NULL,
  `X1` DECIMAL(5,2) NOT NULL CHECK (X1 >= 0),
  `Y1` DECIMAL(5,2) NOT NULL CHECK (Y1 >= 0),
  `X2` DECIMAL(5,2) NOT NULL CHECK (X2 >= 0),
  `Y2` DECIMAL(5,2) NOT NULL CHECK (Y2 >= 0),
  CHECK (ABS(X2-X1) + ABS(Y2-Y1) != 0),
  PRIMARY KEY (`ID`),
  INDEX `fk_Muro_Piano_idx` (`Piano_Numero` ASC, `Piano_Edificio` ASC) VISIBLE,
  CONSTRAINT `fk_Muro_Piano`
    FOREIGN KEY (`Piano_Numero` , `Piano_Edificio`)
    REFERENCES `smartbuildings_db`.`Piano` (`Numero` , `Edificio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Ordine`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Ordine` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Materiale` INT UNSIGNED NOT NULL,
  `Fornitore` VARCHAR(45) NOT NULL,
  `Lotto` VARCHAR(45) NOT NULL,
  `DataAcquisto` DATE NOT NULL,
  `PrezzoUnitario` DECIMAL(10,2) NOT NULL CHECK (PrezzoUnitario >= 0),
  `Unita` SMALLINT NOT NULL CHECK (Unita > 0),
  `Disponibilita` SMALLINT NOT NULL,
  CHECK (Disponibilita BETWEEN 0 AND Unita),
  PRIMARY KEY (`ID`),
  INDEX `fk_Ordine_Materiale_idx` (`Materiale` ASC) VISIBLE,
  CONSTRAINT `fk_Ordine_Materiale`
    FOREIGN KEY (`Materiale`)
    REFERENCES `smartbuildings_db`.`Materiale` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Parete`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Parete` (
  `Vano` INT UNSIGNED NOT NULL,
  `Muro` INT UNSIGNED NOT NULL,
  INDEX `fk_Parete_Muro_idx` (`Muro` ASC) VISIBLE,
  INDEX `fk_Parete_Vano_idx` (`Vano` ASC) VISIBLE,
  PRIMARY KEY (`Vano`, `Muro`),
  CONSTRAINT `fk_Parete_Vano`
    FOREIGN KEY (`Vano`)
    REFERENCES `smartbuildings_db`.`Vano` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Parete_Muro`
    FOREIGN KEY (`Muro`)
    REFERENCES `smartbuildings_db`.`Muro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Personale`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Personale` (
  `CodFiscale` CHAR(16) NOT NULL,
  `DataNascita` DATE NOT NULL,
  `Telefono` VARCHAR(20) NOT NULL,
  `Nome` VARCHAR(45) NOT NULL,
  `Cognome` VARCHAR(45) NOT NULL,
  `Attivo` TINYINT NOT NULL DEFAULT 1,
  `AnniEsperienza` TINYINT NULL DEFAULT NULL,
  PRIMARY KEY (`CodFiscale`))
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Piano`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Piano` (
  `Numero` TINYINT UNSIGNED NOT NULL CHECK (Numero >= 0),
  `Edificio` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`Numero`, `Edificio`),
  INDEX `fk_Piano_Edificio_idx` (`Edificio` ASC) VISIBLE,
  CONSTRAINT `fk_Piano_Edificio`
    FOREIGN KEY (`Edificio`)
    REFERENCES `smartbuildings_db`.`Edificio` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Piastrella`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Piastrella` (
  `Materiale` INT UNSIGNED NOT NULL,
  `Forma` VARCHAR(45) NOT NULL,
  `Stile` VARCHAR(45) NOT NULL,
  PRIMARY KEY (`Materiale`),
  CONSTRAINT `fk_Piastrella_Materiale`
    FOREIGN KEY (`Materiale`)
    REFERENCES `smartbuildings_db`.`Materiale` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Progetto`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Progetto` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Edificio` INT UNSIGNED NOT NULL,
  `DataPresentazione` DATE NOT NULL,
  `DataApprovazione` DATE NULL DEFAULT NULL,
  `Descrizione` VARCHAR(100) NOT NULL,
  `Costo` DECIMAL(10,2) NULL DEFAULT NULL,
  CHECK (DataApprovazione >= DataPresentazione),
  PRIMARY KEY (`ID`),
  INDEX `fk_Progetto_Edificio_idx` (`Edificio` ASC) VISIBLE,
  CONSTRAINT `fk_Progetto_Edificio`
    FOREIGN KEY (`Edificio`)
    REFERENCES `smartbuildings_db`.`Edificio` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Rischio`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Rischio` (
  `AreaGeografica` VARCHAR(255) NOT NULL,
  `Tipologia` VARCHAR(45) NOT NULL,
  `DataMisurazione` DATE NOT NULL,
  `Coefficiente` TINYINT NOT NULL CHECK (Coefficiente BETWEEN 0 AND 5),
  PRIMARY KEY (`AreaGeografica`, `Tipologia`, `DataMisurazione`),
  CONSTRAINT `fk_Rischio_AreaGeografica`
    FOREIGN KEY (`AreaGeografica`)
    REFERENCES `smartbuildings_db`.`AreaGeografica` (`CodPostale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Sensore`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Sensore` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Piano_Numero` TINYINT UNSIGNED NOT NULL,
  `Piano_Edificio` INT UNSIGNED NOT NULL,
  `Tipologia` VARCHAR(45) NOT NULL CHECK (
      Tipologia IN ('Accelerometro', 'Giroscopio', 'Fessurimetro', 'Termometro', 'Pluviometro', 'Igrometro')
  ),
  `Soglia` DECIMAL(9,6) NOT NULL CHECK (Soglia >= 0),
  `X` DECIMAL(5,2) NOT NULL CHECK (X >= 0),
  `Y` DECIMAL(5,2) NOT NULL CHECK (Y >= 0),
  `Z` DECIMAL(5,2) NOT NULL CHECK (Z >= 0),
  `Importanza` DECIMAL(3,2) NOT NULL DEFAULT 1 CHECK (Importanza BETWEEN 0 AND 1),
  PRIMARY KEY (`ID`),
  INDEX `fk_Sensore_Edificio_idx` (`Piano_Edificio` ASC, `Piano_Numero` ASC) VISIBLE,
  CONSTRAINT `fk_Sensore_Edificio`
    FOREIGN KEY (`Piano_Edificio` , `Piano_Numero`)
    REFERENCES `smartbuildings_db`.`Piano` (`Edificio` , `Numero`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`StadioAvanzamento`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`StadioAvanzamento` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Progetto` INT UNSIGNED NOT NULL,
  `Descrizione` VARCHAR(100) NOT NULL,
  `DataInizio` DATE NOT NULL,
  `DataFinePrevista` DATE NOT NULL,
  `DataFine` DATE NULL DEFAULT NULL,
  CHECK (DataFinePrevista >= DataInizio),
  CHECK (DataFine >= DataInizio),
  PRIMARY KEY (`ID`),
  INDEX `fk_StadioAvanzamento_Progetto_idx` (`Progetto` ASC) VISIBLE,
  CONSTRAINT `fk_StadioAvanzamento_Progetto`
    FOREIGN KEY (`Progetto`)
    REFERENCES `smartbuildings_db`.`Progetto` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Turno`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Turno` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `StadioAvanzamento` INT UNSIGNED NOT NULL,
  `Operaio` CHAR(16) NOT NULL,
  `Supervisore` CHAR(16) NOT NULL,
  `Inizio` DATETIME NOT NULL,
  `Fine` DATETIME NOT NULL,
  PRIMARY KEY (`ID`),
  INDEX `fk_Turno_Personale-Supervisore_idx` (`Supervisore` ASC) VISIBLE,
  INDEX `fk_Turno_Personale-Operaio_idx` (`Operaio` ASC) VISIBLE,
  INDEX `fk_Turno_StadioAvanzamento_idx` (`StadioAvanzamento` ASC) VISIBLE,
  CONSTRAINT `fk_Turno_Personale-Operaio`
    FOREIGN KEY (`Operaio`)
    REFERENCES `smartbuildings_db`.`Personale` (`CodFiscale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Turno_Personale-Supervisore`
    FOREIGN KEY (`Supervisore`)
    REFERENCES `smartbuildings_db`.`Personale` (`CodFiscale`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Turno_StadioAvanzamento`
    FOREIGN KEY (`StadioAvanzamento`)
    REFERENCES `smartbuildings_db`.`StadioAvanzamento` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Utilizzo`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Utilizzo` (
  `Lavoro` INT UNSIGNED NOT NULL,
  `Ordine` INT UNSIGNED NOT NULL,
  `Quantita` SMALLINT NOT NULL CHECK (Quantita >= 0),
  PRIMARY KEY (`Lavoro`, `Ordine`),
  INDEX `fk_Utilizzo_Ordine_idx` (`Ordine` ASC) VISIBLE,
  CONSTRAINT `fk_Utilizzo_Lavoro`
    FOREIGN KEY (`Lavoro`)
    REFERENCES `smartbuildings_db`.`Lavoro` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION,
  CONSTRAINT `fk_Utilizzo_Ordine`
    FOREIGN KEY (`Ordine`)
    REFERENCES `smartbuildings_db`.`Ordine` (`ID`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`Vano`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS `smartbuildings_db`.`Vano` (
  `ID` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `Piano_Numero` TINYINT UNSIGNED NOT NULL,
  `Piano_Edificio` INT UNSIGNED NOT NULL,
  `Funzione` VARCHAR(100) NOT NULL,
  `LunghezzaMax` DECIMAL(5,2) NOT NULL CHECK (LunghezzaMax > 0),
  `LarghezzaMax` DECIMAL(5,2) NOT NULL CHECK (LarghezzaMax > 0),
  `AltezzaMax` DECIMAL(5,2) NULL DEFAULT NULL CHECK (AltezzaMax > 0),
  PRIMARY KEY (`ID`),
  INDEX `fk_Vano_Piano_idx` (`Piano_Numero` ASC, `Piano_Edificio` ASC) VISIBLE,
  CONSTRAINT `fk_Vano_Piano`
    FOREIGN KEY (`Piano_Numero` , `Piano_Edificio`)
    REFERENCES `smartbuildings_db`.`Piano` (`Numero` , `Edificio`)
    ON DELETE NO ACTION
    ON UPDATE NO ACTION)
ENGINE = InnoDB;


-- -----------------------------------------------------
-- Table `smartbuildings_db`.`MV_statistiche_edifici_colpiti`
-- -----------------------------------------------------
CREATE TABLE IF NOT EXISTS MV_statistiche_edifici_colpiti (
    `Calamita` DATETIME,
    `Edificio` INT UNSIGNED,
    `Distanza` INT,
    `Mercalli` DECIMAL(4,2),
    PRIMARY KEY (`Calamita`, `Edificio`)
);


SET SQL_MODE=@OLD_SQL_MODE;
SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS;
SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS;
