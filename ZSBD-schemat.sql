SET SERVEROUTPUT ON;
/* ==========================================================================
   SEKCJA 1: SEKWENCJE
   ========================================================================== */
CREATE SEQUENCE proj_seq_uzytkownik START WITH 1;
CREATE SEQUENCE proj_seq_sport START WITH 1;
CREATE SEQUENCE proj_seq_wydarzenie START WITH 1;
CREATE SEQUENCE proj_seq_kurs START WITH 1;
CREATE SEQUENCE proj_seq_zaklad START WITH 1;
CREATE SEQUENCE proj_seq_log START WITH 1;

/* ==========================================================================
   SEKCJA 2: TABELE
   ========================================================================== */
CREATE TABLE proj_uzytkownik (
  id_uzytkownika NUMBER PRIMARY KEY,
  imie VARCHAR2(50),
  nazwisko VARCHAR2(50),
  pesel VARCHAR2(11),
  email VARCHAR2(100) UNIQUE,
  saldo NUMBER(10,2) DEFAULT 0,
  data_rejestracji DATE DEFAULT SYSDATE
);

CREATE TABLE proj_sport (
  id_sportu NUMBER PRIMARY KEY,
  nazwa VARCHAR2(50) NOT NULL,
  opis VARCHAR2(200)
);

CREATE TABLE proj_wydarzenie (
  id_wydarzenia NUMBER PRIMARY KEY,
  nazwa VARCHAR2(100),
  data_meczu DATE,
  id_sportu NUMBER REFERENCES proj_sport(id_sportu),
  status VARCHAR2(20)
);

CREATE TABLE proj_kurs (
  id_kursu NUMBER PRIMARY KEY,
  id_wydarzenia NUMBER REFERENCES proj_wydarzenie(id_wydarzenia),
  typ_zakladu VARCHAR2(30),
  kurs NUMBER(5,2),
  data_utworzenia DATE DEFAULT SYSDATE
);

CREATE TABLE proj_zaklad (
  id_zakladu NUMBER PRIMARY KEY,
  id_uzytkownika NUMBER REFERENCES proj_uzytkownik(id_uzytkownika),
  id_kursu NUMBER REFERENCES proj_kurs(id_kursu),
  stawka NUMBER(10,2), data_zawarcia DATE DEFAULT SYSDATE,
  status VARCHAR2(20), potencjalna_wygrana NUMBER(10,2)
);

CREATE TABLE proj_log_operacji (
  id_logu NUMBER PRIMARY KEY,
  tabela VARCHAR2(30),
  operacja VARCHAR2(20),
  data_operacji DATE DEFAULT SYSDATE, 
  id_rekordu NUMBER
);

CREATE TABLE proj_archiwum_zakladow AS
    SELECT * FROM proj_zaklad WHERE 1=0;

CREATE TABLE proj_podsumowanie_okresowe (
  typ_okresu VARCHAR2(1), 
  okres VARCHAR2(10),
  liczba_zakladow NUMBER,
  suma_stawek NUMBER(12,2), 
  suma_wygranych NUMBER(12,2),
  zysk_firmy NUMBER(12,2),
  data_generacji DATE DEFAULT SYSDATE
);

-- Tabela importowa
CREATE TABLE proj_import_plikow (
    id_pliku NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nazwa_pliku VARCHAR2(100),
    zawartosc_json CLOB,
    data_wgrania DATE DEFAULT SYSDATE,
    status VARCHAR2(20) DEFAULT 'NOWY'
);

-- Tabela stagingowa
CREATE TABLE proj_stg_events (
  nazwa_meczu VARCHAR2(200),
  data_txt VARCHAR2(50), 
  nazwa_sportu VARCHAR2(50),
  status_load VARCHAR2(20) DEFAULT 'NEW'
);

/* ==========================================================================
   SEKCJA 3: WIDOKI I FUNKCJE
   ========================================================================== */
CREATE OR REPLACE VIEW proj_v_suma_stawek AS
SELECT 
    id_uzytkownika, 
    liczba_zakladow, 
    suma_stawek,
    SUM(suma_stawek) OVER () AS suma_globalna
FROM (
    SELECT 
        id_uzytkownika, 
        COUNT(*)    AS liczba_zakladow, 
        SUM(stawka) AS suma_stawek
    FROM proj_zaklad 
    GROUP BY id_uzytkownika
);

CREATE OR REPLACE FUNCTION proj_sprawdz_pesel (
    p_pesel VARCHAR2
) RETURN BOOLEAN IS
BEGIN
    IF LENGTH(p_pesel) = 11 
       AND REGEXP_LIKE(p_pesel, '^[0-9]+$') 
    THEN 
        RETURN TRUE;
    ELSE 
        RETURN FALSE; 
    END IF;
END;
/

CREATE OR REPLACE FUNCTION proj_sprawdz_event(
    p_nazwa VARCHAR2,
    p_data_meczu DATE,
    p_id_sportu NUMBER
) RETURN BOOLEAN IS
BEGIN
    IF p_nazwa IS NULL OR TRIM(p_nazwa) = '' THEN
        RETURN FALSE;
    ELSIF p_data_meczu < SYSDATE THEN
        RETURN FALSE;
    ELSIF p_id_sportu IS NULL THEN
        RETURN FALSE;
    ELSE 
        RETURN TRUE;
    END IF;
END;
/

/* ==========================================================================
   SEKCJA 4: PROCEDURY BIZNESOWE
   ========================================================================== */
-- Dodaj zakład
CREATE OR REPLACE PROCEDURE proj_dodaj_zaklad (
    p_id_uzytkownika IN NUMBER, 
    p_id_kursu       IN NUMBER, 
    p_stawka         IN NUMBER
) IS
    v_saldo         proj_uzytkownik.saldo%TYPE;
    v_kurs          proj_kurs.kurs%TYPE;
    e_brak_srodkow  EXCEPTION;
BEGIN
    -- 1. Walidacja danych wejściowych
    IF p_stawka <= 0 THEN 
        RAISE_APPLICATION_ERROR(-20001, 'Stawka musi być > 0'); 
    END IF;

    -- 2. Sprawdzenie salda użytkownika
    SELECT saldo INTO v_saldo 
    FROM proj_uzytkownik 
    WHERE id_uzytkownika = p_id_uzytkownika;

    IF v_saldo < p_stawka THEN 
        RAISE e_brak_srodkow; 
    END IF;

    -- 3. Pobranie kursu
    SELECT kurs INTO v_kurs 
    FROM proj_kurs 
    WHERE id_kursu = p_id_kursu;

    -- 4. Wstawienie nowego zakładu
    INSERT INTO proj_zaklad (
        id_zakladu, 
        id_uzytkownika, 
        id_kursu, 
        stawka, 
        status, 
        potencjalna_wygrana
    ) VALUES (
        proj_seq_zaklad.NEXTVAL, 
        p_id_uzytkownika, 
        p_id_kursu, 
        p_stawka, 
        'OCZEKUJACY', 
        p_stawka * v_kurs
    );

    -- 5. Aktualizacja salda
    UPDATE proj_uzytkownik 
    SET saldo = saldo - p_stawka 
    WHERE id_uzytkownika = p_id_uzytkownika;

    COMMIT;

EXCEPTION
    WHEN e_brak_srodkow THEN 
        RAISE_APPLICATION_ERROR(-20002, 'Brak środków');
    WHEN OTHERS THEN 
        RAISE_APPLICATION_ERROR(-20099, 'Błąd: ' || SQLERRM);
END;
/

-- Usun zakład
CREATE OR REPLACE PROCEDURE proj_usun_zaklad (
    p_id_zakladu IN NUMBER
) IS
BEGIN
  DELETE FROM proj_zaklad WHERE id_zakladu = p_id_zakladu;
  IF SQL%ROWCOUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20200, 'Zakład nie istnieje'); END IF;
  COMMIT;
END;
/

-- Aktualizuj kurs
CREATE OR REPLACE PROCEDURE proj_aktualizuj_kurs (
    p_id_kursu  IN NUMBER,
    p_nowy_kurs IN NUMBER
) IS
    v_stary_kurs NUMBER;
    v_id_wydarzenia NUMBER;
    v_status_meczu VARCHAR2(20);
BEGIN
    -- 1. Walidacja danych wejściowych
    IF p_nowy_kurs <= 1.0 THEN
        RAISE_APPLICATION_ERROR(-20201, 'Kurs musi być większy niż 1.0');
    END IF;

    -- 2. Pobieranie danych o obecnym kursie i wydarzeniu
    BEGIN
        SELECT 
        k.kurs,
        k.id_wydarzenia,
        w.status
        INTO 
        v_stary_kurs,
        v_id_wydarzenia,
        v_status_meczu
        FROM proj_kurs k
        JOIN proj_wydarzenie w ON k.id_wydarzenia = w.id_wydarzenia
        WHERE k.id_kursu = p_id_kursu;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20202, 'Nie znaleziono kursu o podanym ID.');
    END;

    -- 3. Sprawdzenie czy mecz się nie skończył (nie zmieniamy kursów po meczu)
    IF v_status_meczu = 'ZAKONCZONE' THEN
        RAISE_APPLICATION_ERROR(-20203, 'Nie można zmienić kursu - mecz już zakończony.');
    END IF;

    -- 4. Aktualizacja kursu
    UPDATE proj_kurs
    SET kurs = p_nowy_kurs
    WHERE id_kursu = p_id_kursu;

    -- 5. Logowanie zmiany
    DBMS_OUTPUT.PUT_LINE('Zaktualizowano kurs ID ' || p_id_kursu || 
                         '. Stara wartość: ' || v_stary_kurs || 
                         ', Nowa wartość: ' || p_nowy_kurs);
    COMMIT;
END;
/

-- Rozlicz/zakoncz mecz
CREATE OR REPLACE PROCEDURE proj_rozlicz_mecz (
  p_id_wydarzenia IN NUMBER,
  p_wynik         IN VARCHAR2
) IS
  v_status_obecny VARCHAR2(20);
  v_licznik_wygranych NUMBER := 0;
BEGIN
  -- 1. Sprawdzenie czy mecz nie jest już rozliczony
  SELECT status INTO v_status_obecny 
  FROM proj_wydarzenie WHERE id_wydarzenia = p_id_wydarzenia;
  
  IF v_status_obecny = 'ZAKONCZONE' THEN
     RAISE_APPLICATION_ERROR(-20005, 'Ten mecz został już rozliczony!');
  END IF;

  -- 2. Zaktualizuj status meczu
  UPDATE proj_wydarzenie 
  SET status = 'ZAKONCZONE' 
  WHERE id_wydarzenia = p_id_wydarzenia;

  -- 3. Przejście przez zakłady
  FOR z IN (
    SELECT z.id_zakladu, z.id_uzytkownika, z.potencjalna_wygrana, k.typ_zakladu
    FROM proj_zaklad z
    JOIN proj_kurs k ON z.id_kursu = k.id_kursu
    WHERE k.id_wydarzenia = p_id_wydarzenia 
      AND z.status = 'OCZEKUJACY'
  ) LOOP

    IF UPPER(z.typ_zakladu) = UPPER(p_wynik) THEN
      -- WYGRANA
      UPDATE proj_zaklad 
      SET status = 'WYGRANY' 
      WHERE id_zakladu = z.id_zakladu;
      
      UPDATE proj_uzytkownik 
      SET saldo = saldo + z.potencjalna_wygrana 
      WHERE id_uzytkownika = z.id_uzytkownika;
      
      v_licznik_wygranych := v_licznik_wygranych + 1;
    ELSE
      -- PRZEGRANA
      UPDATE proj_zaklad 
      SET status = 'PRZEGRANY' 
      WHERE id_zakladu = z.id_zakladu;
    END IF;

  END LOOP;
  
  -- Logowanie rozliczenia
  DBMS_OUTPUT.PUT_LINE('Mecz rozliczony. Liczba wygranych zakładów: ' || v_licznik_wygranych);
  
  COMMIT;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
     RAISE_APPLICATION_ERROR(-20006, 'Nie znaleziono wydarzenia o podanym ID.');
  WHEN OTHERS THEN
     ROLLBACK;
     RAISE_APPLICATION_ERROR(-20099, 'Błąd rozliczania: ' || SQLERRM);
END;
/

-- Generuj podsumowanie
CREATE OR REPLACE PROCEDURE proj_generuj_podsumowanie (
    p_typ_okresu IN VARCHAR2 DEFAULT 'M'
) IS
BEGIN
    -- 1. Czyszczenie danych dla wybranego okresu
    DELETE FROM proj_podsumowanie_okresowe 
    WHERE typ_okresu = p_typ_okresu;

    -- 2. Generowanie nowych danych
    IF p_typ_okresu = 'M' THEN
        INSERT INTO proj_podsumowanie_okresowe
        SELECT 
            'M', 
            TO_CHAR(data_zawarcia, 'YYYY-MM'), 
            COUNT(*), 
            SUM(stawka), 
            SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SUM(stawka) - SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SYSDATE 
        FROM proj_zaklad 
        GROUP BY TO_CHAR(data_zawarcia, 'YYYY-MM');

    ELSIF p_typ_okresu = 'Q' THEN
        INSERT INTO proj_podsumowanie_okresowe
        SELECT 
            'Q', 
            TO_CHAR(data_zawarcia, 'YYYY') || '-Q' || TO_CHAR(data_zawarcia, 'Q'), 
            COUNT(*), 
            SUM(stawka), 
            SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SUM(stawka) - SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SYSDATE 
        FROM proj_zaklad 
        GROUP BY TO_CHAR(data_zawarcia, 'YYYY'), TO_CHAR(data_zawarcia, 'Q');

    ELSIF p_typ_okresu = 'Y' THEN
        INSERT INTO proj_podsumowanie_okresowe
        SELECT 
            'Y', 
            TO_CHAR(data_zawarcia, 'YYYY'), 
            COUNT(*), 
            SUM(stawka), 
            SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SUM(stawka) - SUM(CASE WHEN status = 'WYGRANY' THEN potencjalna_wygrana ELSE 0 END), 
            SYSDATE 
        FROM proj_zaklad 
        GROUP BY TO_CHAR(data_zawarcia, 'YYYY');
    END IF;

    COMMIT;
END;
/

/* ==========================================================================
   SEKCJA 5: PROCEDURY IMPORTU
   ========================================================================== */

-- 1. Rozpakuj JSON
CREATE OR REPLACE PROCEDURE proj_rozpakuj_json_param (p_json_clob CLOB) IS
BEGIN
    DELETE FROM proj_stg_events;

    INSERT INTO proj_stg_events (nazwa_meczu, data_txt, nazwa_sportu)
    SELECT jt.strEvent, jt.strTimestamp, jt.strSport
    FROM JSON_TABLE(p_json_clob, '$.events[*]' 
        COLUMNS (
            strEvent VARCHAR2(200) PATH '$.strEvent',
            strTimestamp VARCHAR2(50) PATH '$.strTimestamp',
            strSport VARCHAR2(50) PATH '$.strSport'
        )) jt;
        
    -- DEBUG
    DBMS_OUTPUT.PUT_LINE('Trigger: Dane rozpakowane do STG.');
END;
/

-- 2. Importuj Dane
CREATE OR REPLACE PROCEDURE proj_importuj_dane IS
    v_sport_id NUMBER; v_data_date DATE; v_exists NUMBER; v_licznik NUMBER := 0;
BEGIN
    FOR r IN (SELECT * FROM proj_stg_events WHERE status_load = 'NEW') LOOP
        BEGIN
            -- Konwersja Daty
            BEGIN v_data_date := TO_DATE(REPLACE(r.data_txt, 'T', ' '), 'YYYY-MM-DD HH24:MI:SS');
            EXCEPTION WHEN OTHERS THEN v_data_date := SYSDATE + 7; END;

            -- Sprawdzenie duplikatu (Nazwa + Data)
            SELECT COUNT(*) INTO v_exists FROM proj_wydarzenie 
            WHERE nazwa = r.nazwa_meczu AND data_meczu = v_data_date;
            
            IF v_exists > 0 THEN
                UPDATE proj_stg_events SET status_load = 'DUPLICATE' WHERE nazwa_meczu = r.nazwa_meczu; 
                CONTINUE;
            END IF;

            -- Obsługa Sportu
            BEGIN SELECT id_sportu INTO v_sport_id FROM proj_sport WHERE UPPER(nazwa) = UPPER(r.nazwa_sportu);
            EXCEPTION WHEN NO_DATA_FOUND THEN
                v_sport_id := proj_seq_sport.NEXTVAL;
                INSERT INTO proj_sport (id_sportu, nazwa, opis) VALUES (v_sport_id, r.nazwa_sportu, 'Auto-Import');
            END;

            -- Wstawienie
            INSERT INTO proj_wydarzenie (id_wydarzenia, nazwa, data_meczu, id_sportu, status)
            VALUES (proj_seq_wydarzenie.NEXTVAL, r.nazwa_meczu, v_data_date, v_sport_id, 'ZAPLANOWANY');
            
            v_licznik := v_licznik + 1;
            UPDATE proj_stg_events SET status_load = 'PROCESSED' WHERE nazwa_meczu = r.nazwa_meczu;
        EXCEPTION WHEN OTHERS THEN
            UPDATE proj_stg_events SET status_load = 'ERROR' WHERE nazwa_meczu = r.nazwa_meczu;
        END;
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE('Trigger: Zaimportowano ' || v_licznik || ' wydarzeń.');
END;
/

/* ==========================================================================
   SEKCJA 6: WYZWALACZE
   ========================================================================== */
-- Trigger logujacy zaklad
CREATE OR REPLACE TRIGGER proj_trg_log_zaklad
AFTER INSERT OR UPDATE OR DELETE
ON proj_zaklad
FOR EACH ROW
BEGIN
    INSERT INTO proj_log_operacji 
    VALUES (
        proj_seq_log.NEXTVAL, 
        'PROJ_ZAKLAD', 
        ORA_SYSEVENT, 
        SYSDATE, 
        NVL(:NEW.id_zakladu, :OLD.id_zakladu)
    );
END;
/
-- Trigger archiwizujacy
CREATE OR REPLACE TRIGGER proj_trg_arch_zaklad
BEFORE DELETE
ON proj_zaklad
FOR EACH ROW
BEGIN
    INSERT INTO proj_archiwum_zakladow (
        id_zakladu,
        id_uzytkownika,
        id_kursu,
        stawka,
        data_zawarcia,
        status,
        potencjalna_wygrana
    ) VALUES (
        :OLD.id_zakladu,
        :OLD.id_uzytkownika,
        :OLD.id_kursu,
        :OLD.stawka,
        :OLD.data_zawarcia,
        :OLD.status,
        :OLD.potencjalna_wygrana
    );
END;
/
-- Trigger walidujacy PESEL
CREATE OR REPLACE TRIGGER proj_trg_pesel
BEFORE INSERT
ON proj_uzytkownik
FOR EACH ROW
BEGIN
    IF NOT proj_sprawdz_pesel(:NEW.pesel) THEN
        RAISE_APPLICATION_ERROR(-20100, 'Błędny PESEL');
    END IF;
END;
/
-- Triger walidujacy Wydarzenie
CREATE OR REPLACE TRIGGER proj_trg_valid_wydarzenie
BEFORE INSERT
ON proj_wydarzenie
FOR EACH ROW
BEGIN
    -- 1. Sprawdzenie wymagalności nazwy
    IF :NEW.nazwa IS NULL THEN
        RAISE_APPLICATION_ERROR(-20101, 'Nazwa pusta');
    END IF;

    -- 2. Walidacja daty
    IF :NEW.data_meczu < SYSDATE THEN
        RAISE_APPLICATION_ERROR(-20102, 'Data meczu nie może być w przeszłości');
    ELSIF :NEW.data_meczu IS NULL THEN
        RAISE_APPLICATION_ERROR(-20103, 'Data meczu jest wymagana');
    END IF;

    -- 3. Ustawienie domyślnego statusu
    IF :NEW.status IS NULL THEN
        :NEW.status := 'ZAPLANOWANY';
    ELSIF :NEW.status NOT IN ('ZAPLANOWANY','ZAKONCZONY') THEN
        RAISE_APPLICATION_ERROR(-20104, 'Niepoprawny status wydarzenia');
    END IF;
END;
/

/* ==========================================================================
   SEKCJA 7: TRIGGER AUTOMATYZUJĄCY IMPORT
   ========================================================================== */
CREATE OR REPLACE TRIGGER proj_trg_auto_import
AFTER INSERT ON proj_import_plikow
FOR EACH ROW
BEGIN
    -- 1. Rozpakowuje dane
    proj_rozpakuj_json_param(:NEW.zawartosc_json);
    
    -- 2. Wykonuje import
    proj_importuj_dane;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('CRITICAL ERROR IN TRIGGER: ' || SQLERRM);
END;
/