SET SERVEROUTPUT ON;

PROMPT TEST 1: AUTOMATYCZNY IMPORT DANYCH
-- Symulujemy wpadnięcie danych do tabeli importowej. Trigger 'proj_trg_auto_import' powinien automatycznie:
-- 1. Rozpakować JSON do tabeli 'proj_stg_events'
-- 2. Przenieść poprawne dane do 'proj_wydarzenie' i 'proj_sport'

DECLARE
  v_json_content CLOB;
BEGIN
  -- Przykładowy JSON wzorowany na TheSportsDB
  v_json_content := '{
      "events": [
        {
          "strEvent": "Arsenal vs Liverpool",
          "strTimestamp": "2025-05-15T19:45:00",
          "strSport": "Soccer"
        },
        {
          "strEvent": "Real Madrid vs Barcelona",
          "strTimestamp": "2025-06-01T20:00:00",
          "strSport": "Soccer"
        },
        {
          "strEvent": "Lakers vs Bulls",
          "strTimestamp": "2025-05-20T01:00:00",
          "strSport": "Basketball"
        }
      ]
  }';

  INSERT INTO proj_import_plikow (nazwa_pliku, zawartosc_json) 
  VALUES ('thesportsdb_import_test_001.json', v_json_content);
  
  COMMIT;
END;
/

-- Sprawdzanie wyników importu --
-- Czy dane są w tabeli staging?
SELECT * FROM proj_stg_events;
-- Czy dane trafiły do tabeli wydarzenia?
SELECT id_wydarzenia, nazwa, TO_CHAR(data_meczu, 'YYYY-MM-DD HH24:MI') as data, id_sportu, status 
FROM proj_wydarzenie 
WHERE nazwa IN ('Arsenal vs Liverpool', 'Real Madrid vs Barcelona', 'Lakers vs Bulls');
-- Czy dodał się nowy sport?
SELECT * FROM proj_sport;


PROMPT TEST 2: REJESTRACJA UŻYTKOWNIKA I WALIDACJA PESEL

-- A. Próba dodania użytkownika z błędnym peselem
BEGIN
  INSERT INTO proj_uzytkownik (id_uzytkownika, imie, nazwisko, pesel, email)
  VALUES (proj_seq_uzytkownik.NEXTVAL, 'Tester', 'Bledny', '123', 'fail@test.com');
END;
/

-- B. Dodanie poprawnego użytkownika
INSERT INTO proj_uzytkownik (id_uzytkownika, imie, nazwisko, pesel, email, saldo)
VALUES (proj_seq_uzytkownik.NEXTVAL, 'Anna', 'Kowalska', '90010112345', 'anna@test.pl', 1000);
COMMIT;

SELECT * FROM proj_uzytkownik WHERE email = 'anna@test.pl';

PROMPT TEST 3A: TWORZENIE KURSÓW I ZAKŁADÓW

DECLARE
  v_id_wydarzenia NUMBER;
  v_id_kursu NUMBER;
  v_id_user NUMBER;
BEGIN
  -- Pobieranie ID wydarzenia zaimportowanego w Teście
  SELECT id_wydarzenia INTO v_id_wydarzenia FROM proj_wydarzenie WHERE nazwa = 'Arsenal vs Liverpool' FETCH FIRST 1 ROWS ONLY;

  -- Pobieranie ID utworzonego usera
  SELECT id_uzytkownika INTO v_id_user FROM proj_uzytkownik WHERE email = 'anna@test.pl';

  -- 1. Bukmacher wystawia kurs
  v_id_kursu := proj_seq_kurs.NEXTVAL;
  INSERT INTO proj_kurs (id_kursu, id_wydarzenia, typ_zakladu, kurs)
  VALUES (v_id_kursu, v_id_wydarzenia, 'Wygrana Gospodarzy', 2.50);
  
  -- 2. Użytkownik stawia zakład za 200 PLN
  proj_dodaj_zaklad(v_id_user, v_id_kursu, 200);
  
  COMMIT;
END;
/

PROMPT Wyniki testu:
SELECT u.imie, u.saldo AS obecne_saldo, z.stawka, z.potencjalna_wygrana, z.status
FROM proj_uzytkownik u
JOIN proj_zaklad z ON u.id_uzytkownika = z.id_uzytkownika
WHERE u.email = 'anna@test.pl';

PROMPT TEST 3B: PRÓBA ZAKŁADU PONAD STAN KONTA

DECLARE
  v_id_user NUMBER;
  v_id_kursu NUMBER;
BEGIN
  -- Pobieramy ID uzytkownika
  SELECT id_uzytkownika INTO v_id_user FROM proj_uzytkownik WHERE email = 'anna@test.pl';
  -- Pobieramy dowolny kurs
  SELECT id_kursu INTO v_id_kursu FROM proj_kurs FETCH FIRST 1 ROWS ONLY;

  -- Próba postawienia ponad stan konta
  proj_dodaj_zaklad(v_id_user, v_id_kursu, 1000000);
END;
/

PROMPT TEST 4: LOGOWANIE OPERACJI

-- Sprawdzamy, czy dodanie zakładu w Teście 3 zarejestrowało się w logach
SELECT * FROM proj_log_operacji ORDER BY id_logu DESC FETCH FIRST 5 ROWS ONLY;

PROMPT TEST 5: ROZLICZENIE ISTNIEJĄCEGO ZAKŁADU (Arsenal vs Liverpool)

DECLARE
  v_id_wydarzenia NUMBER;
  v_saldo_przed   NUMBER;
  v_saldo_po      NUMBER;
BEGIN
  -- 1. Szukamy ID meczu
  SELECT id_wydarzenia INTO v_id_wydarzenia 
  FROM proj_wydarzenie WHERE nazwa = 'Arsenal vs Liverpool' FETCH FIRST 1 ROWS ONLY;

  -- 2. Saldo Anny przed zakonczeniem meczu
  SELECT saldo INTO v_saldo_przed 
  FROM proj_uzytkownik WHERE email = 'anna@test.pl';
  
  DBMS_OUTPUT.PUT_LINE('Saldo przed rozliczeniem: ' || v_saldo_przed);

  -- 3. Rozliczamy mecz (Anna postawiła na 'Wygrana Gospodarzy', kurs 2.50)
  proj_rozlicz_mecz(v_id_wydarzenia, 'Wygrana Gospodarzy');

  -- 4. Saldo po rozliczeniu (powinno wzrosnąć o 500 zł)
  SELECT saldo INTO v_saldo_po 
  FROM proj_uzytkownik WHERE email = 'anna@test.pl';
  
  DBMS_OUTPUT.PUT_LINE('Saldo po rozliczeniu:     ' || v_saldo_po);
  DBMS_OUTPUT.PUT_LINE('Różnica (wygrana):        ' || (v_saldo_po - v_saldo_przed));
END;
/

-- Sprawdzamy w tabeli, czy statusy się zmieniły
SELECT w.nazwa AS mecz, w.status AS status_meczu, z.status AS status_zakladu, z.potencjalna_wygrana
FROM proj_zaklad z
JOIN proj_kurs k ON z.id_kursu = k.id_kursu
JOIN proj_wydarzenie w ON k.id_wydarzenia = w.id_wydarzenia
WHERE w.nazwa = 'Arsenal vs Liverpool' AND z.id_uzytkownika = (SELECT id_uzytkownika FROM proj_uzytkownik WHERE email='anna@test.pl');

PROMPT TEST 6: ZMIANA KURSU PRZEZ BUKMACHERA

DECLARE
  v_id_wydarzenia NUMBER;
  v_id_kursu      NUMBER;
  v_id_user_jan   NUMBER;
  v_id_user_anna  NUMBER;
  v_wygrana_jan   NUMBER;
  v_wygrana_anna  NUMBER;
BEGIN
  -- 1. Tworzymy nowy mecz jako zaplanowany
  INSERT INTO proj_wydarzenie (id_wydarzenia, nazwa, data_meczu, id_sportu, status)
  VALUES (proj_seq_wydarzenie.NEXTVAL, 'BVB vs Bayern', SYSDATE+2, 1, 'ZAPLANOWANY');
  v_id_wydarzenia := proj_seq_wydarzenie.CURRVAL;

  -- Wybieramy 2 użytkowników oraz pobieramy ich ID
  SELECT id_uzytkownika INTO v_id_user_jan FROM proj_uzytkownik WHERE email = 'jan@test.pl';
  SELECT id_uzytkownika INTO v_id_user_anna FROM proj_uzytkownik WHERE email = 'anna@test.pl';

  -- 2. Bukmacher wystawia kurs na Bayern: 2.00
  v_id_kursu := proj_seq_kurs.NEXTVAL;
  INSERT INTO proj_kurs (id_kursu, id_wydarzenia, typ_zakladu, kurs)
  VALUES (v_id_kursu, v_id_wydarzenia, 'Wygrana Gosci', 2.00);

  DBMS_OUTPUT.PUT_LINE('--- KROK 1: Jan stawia zakład (Kurs 2.00) ---');
  
  -- 3. JAN stawia 100 PLN po kursie 2.00
  proj_dodaj_zaklad(v_id_user_jan, v_id_kursu, 100);
  
  -- Sprawdzamy potencjalną wygraną Jana
  SELECT potencjalna_wygrana INTO v_wygrana_jan 
  FROM proj_zaklad 
  WHERE id_kursu = v_id_kursu AND id_uzytkownika = v_id_user_jan AND status='OCZEKUJACY'
  FETCH FIRST 1 ROWS ONLY;
  
  DBMS_OUTPUT.PUT_LINE('Jan postawił 100. Potencjalna wygrana: ' || v_wygrana_jan || ' (Oczekiwane: 200)');
  DBMS_OUTPUT.PUT_LINE('--- KROK 2: Bukmacher zmienia kurs na 1.50 ---');
  
  -- 4. Bukmacher zmienia kurs na 1.50 - "Wygrana Gości"
  proj_aktualizuj_kurs(v_id_kursu, 1.50);


  DBMS_OUTPUT.PUT_LINE('--- KROK 3: Anna stawia zakład (Kurs 1.50) ---');
  
  -- 5. ANNA stawia 100 PLN na ten sam zakład co Jan, ale już po nowym kursie
  proj_dodaj_zaklad(v_id_user_anna, v_id_kursu, 100);

  -- Sprawdzamy potencjalną wygraną Anny
  SELECT potencjalna_wygrana INTO v_wygrana_anna
  FROM proj_zaklad 
  WHERE id_kursu = v_id_kursu AND id_uzytkownika = v_id_user_anna AND status='OCZEKUJACY'
  ORDER BY id_zakladu DESC FETCH FIRST 1 ROWS ONLY;

  DBMS_OUTPUT.PUT_LINE('Anna postawiła 100. Potencjalna wygrana: ' || v_wygrana_anna || ' (Oczekiwane: 150)');

  -- 6. OSTATECZNA WERYFIKACJA
  SELECT potencjalna_wygrana INTO v_wygrana_jan 
  FROM proj_zaklad 
  WHERE id_kursu = v_id_kursu AND id_uzytkownika = v_id_user_jan AND status='OCZEKUJACY'
  FETCH FIRST 1 ROWS ONLY;

  IF v_wygrana_jan = 200 AND v_wygrana_anna = 150 THEN
      DBMS_OUTPUT.PUT_LINE('SUKCES: Jan ma stary kurs, Anna ma nowy kurs.');
  ELSE
      DBMS_OUTPUT.PUT_LINE('BŁĄD: Wartości wygranych są niepoprawne!');
  END IF;

END;
/

PROMPT TEST 7: USUWANIE ZAKŁADU I ARCHIWIZACJA

-- Usuwamy zakład. Trigger powinien przenieść go do tabeli ARCHIWUM.
DECLARE
  v_id_zakladu NUMBER;
BEGIN
  SELECT MAX(id_zakladu) INTO v_id_zakladu FROM proj_zaklad;
  
  proj_usun_zaklad(v_id_zakladu);
  DBMS_OUTPUT.PUT_LINE('Usunięto zakład ID: ' || v_id_zakladu);
END;
/

-- Sprawdzenie archiwum:
SELECT * FROM proj_archiwum_zakladow;


PROMPT TEST 8: GENEROWANIE RAPORTU OKRESOWEGO
-- Generujemy raport miesięczny.
DECLARE
  v_id_wydarzenia NUMBER; v_id_kursu NUMBER; v_id_user NUMBER;
BEGIN
   SELECT id_wydarzenia INTO v_id_wydarzenia FROM proj_wydarzenie WHERE rownum=1;
   SELECT id_uzytkownika INTO v_id_user FROM proj_uzytkownik WHERE rownum=1;
   
   INSERT INTO proj_kurs (id_kursu, id_wydarzenia, typ_zakladu, kurs) VALUES (proj_seq_kurs.NEXTVAL, v_id_wydarzenia, 'Remis', 3.0);
   
   -- Dodajemy zakład bezpośrednio
   INSERT INTO proj_zaklad (id_zakladu, id_uzytkownika, id_kursu, stawka, status, potencjalna_wygrana, data_zawarcia)
   VALUES (proj_seq_zaklad.NEXTVAL, v_id_user, proj_seq_kurs.CURRVAL, 500, 'WYGRANY', 1500, SYSDATE);
   
   COMMIT;
END;
/

EXEC proj_generuj_podsumowanie('M');

-- Wynik raportu miesięcznego:
SELECT * FROM proj_podsumowanie_okresowe;