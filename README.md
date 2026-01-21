# Projekt: Firma Bukmacherska

## Opis
Prosty system firmy bukmacherskiej w Oracle SQL Developer.  
Przechowuje dane użytkowników, zakładów, kursów i wyników wydarzeń sportowych.  
Zawiera mechanizmy rejestrowania operacji w bazie, archiwizacji i generowania raportów miesięcznych.

## Struktura bazy danych
| Tabela | Opis |
| :--- | :--- |
| `proj_uzytkownik` | Dane klientów, saldo, data rejestracji. |
| `proj_wydarzenie` | Mecze, daty spotkań, statusy (np. ZAPLANOWANY, ZAKONCZONY). |
| `proj_kurs` | Kursy dla danych wydarzeń. |
| `proj_sport` | Słownik dyscyplin sportowych. |
| `proj_zaklad` | Zawarte zakłady, stawki, statusy, potencjalne wygrane. |
| `proj_import_plikow` | Bufor dla surowych danych JSON. |
| `proj_stg_events` | Tabela tymczasowa (staging) do przetwarzania i czyszczenia danych JSON przed importem. |
| `proj_log_operacji` | Dziennik zdarzeń systemowych. |
| `proj_archiwum_zakladow` | Historia usuniętych/anulowanych zakładów. |
| `proj_podsumowanie_okresowe` | Wyniki generowanych raportów finansowych (zyski/straty miesięczne). |
## Mechanizmy
- triggery do importu danych, logowania operacji i archiwizacji
- procedury PL/SQL realizujące logikę biznesową
- sekwencje do generowania kluczy głównych
- walidacja danych wejściowych (PESEL, saldo użytkownika)

## Rozszerzenia

## Autor
- Patrycjusz Siwek 164463
- Miłosz Budzichowski 164459
